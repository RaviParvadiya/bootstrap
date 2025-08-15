#!/bin/bash

# Common utility functions shared across all modules
# Provides distribution detection, package management, and system utilities

# Source logger functions if available
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/logger.sh" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"
fi

# Detect the current Linux distribution
# Returns: "arch", "ubuntu", or "unknown"
detect_distro() {
    # Check for Arch Linux
    if [[ -f /etc/arch-release ]]; then
        echo "arch"
        return 0
    fi
    
    # Check for Ubuntu using multiple methods
    if [[ -f /etc/lsb-release ]] && grep -q "Ubuntu" /etc/lsb-release; then
        echo "ubuntu"
        return 0
    fi
    
    # Check using os-release (more modern approach)
    if [[ -f /etc/os-release ]]; then
        local id=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
        case "$id" in
            arch|archlinux)
                echo "arch"
                return 0
                ;;
            ubuntu)
                echo "ubuntu"
                return 0
                ;;
        esac
    fi
    
    # Fallback to lsb_release command
    if command -v lsb_release >/dev/null 2>&1; then
        local distro=$(lsb_release -si 2>/dev/null | tr '[:upper:]' '[:lower:]')
        case "$distro" in
            arch|archlinux)
                echo "arch"
                return 0
                ;;
            ubuntu)
                echo "ubuntu"
                return 0
                ;;
        esac
    fi
    
    # Check for specific distribution files
    if [[ -f /etc/debian_version ]] && command -v apt-get >/dev/null 2>&1; then
        # Likely Ubuntu or Debian-based
        if grep -q "ubuntu" /etc/os-release 2>/dev/null; then
            echo "ubuntu"
            return 0
        fi
    fi
    
    echo "unknown"
    return 1
}

# Check internet connectivity using multiple methods
# Returns: 0 if connected, 1 if not connected
check_internet() {
    local test_hosts=("8.8.8.8" "1.1.1.1" "google.com")
    local timeout=5
    
    # Try ping first (fastest)
    for host in "${test_hosts[@]}"; do
        if ping -c 1 -W "$timeout" "$host" >/dev/null 2>&1; then
            return 0
        fi
    done
    
    # Try curl if available
    if command_exists curl; then
        if curl -s --connect-timeout "$timeout" --max-time "$timeout" "http://google.com" >/dev/null 2>&1; then
            return 0
        fi
    fi
    
    # Try wget if available
    if command_exists wget; then
        if wget -q --timeout="$timeout" --tries=1 --spider "http://google.com" >/dev/null 2>&1; then
            return 0
        fi
    fi
    
    return 1
}

# Check internet connectivity with user feedback
check_internet_with_retry() {
    local max_retries=3
    local retry_count=0
    
    while [[ $retry_count -lt $max_retries ]]; do
        if check_internet; then
            log_success "Internet connectivity verified"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $max_retries ]]; then
            log_warn "Internet connectivity check failed (attempt $retry_count/$max_retries)"
            log_info "Retrying in 3 seconds..."
            sleep 3
        fi
    done
    
    log_error "Internet connectivity check failed after $max_retries attempts"
    return 1
}

# Interactive yes/no confirmation prompt
# Args: prompt_message [default_answer]
# Returns: 0 for yes, 1 for no
ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    
    # Skip prompts in non-interactive mode
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        if [[ "$default" == "y" ]]; then
            log_info "Non-interactive mode: answering 'yes' to: $prompt"
            return 0
        else
            log_info "Non-interactive mode: answering 'no' to: $prompt"
            return 1
        fi
    fi
    
    while true; do
        if [[ "$default" == "y" ]]; then
            read -p "$prompt [Y/n]: " response
        else
            read -p "$prompt [y/N]: " response
        fi
        
        response=${response:-$default}
        case "$response" in
            [Yy]|[Yy][Ee][Ss])
                return 0
                ;;
            [Nn]|[Nn][Oo])
                return 1
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

# Interactive multiple choice prompt
# Args: prompt_message option1 option2 [option3 ...]
# Returns: index of selected option (0-based)
ask_multiple_choice() {
    local prompt="$1"
    shift
    local options=("$@")
    
    if [[ ${#options[@]} -eq 0 ]]; then
        log_error "No options provided for multiple choice prompt"
        return 1
    fi
    
    echo "$prompt"
    for i in "${!options[@]}"; do
        echo "  $((i + 1))) ${options[i]}"
    done
    
    while true; do
        read -p "Please select an option (1-${#options[@]}): " response
        
        if [[ "$response" =~ ^[0-9]+$ ]] && [[ $response -ge 1 ]] && [[ $response -le ${#options[@]} ]]; then
            return $((response - 1))
        else
            echo "Invalid selection. Please choose a number between 1 and ${#options[@]}."
        fi
    done
}

# Universal package installation wrapper
# Args: package_name [distribution] [package_manager]
# Returns: 0 on success, 1 on failure
install_package() {
    local package="$1"
    local distro="${2:-$DETECTED_DISTRO}"
    local pkg_manager="${3:-auto}"
    
    if [[ -z "$package" ]]; then
        log_error "Package name is required"
        return 1
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install package: $package ($distro)"
        return 0
    fi
    
    case "$distro" in
        "arch")
            # Check if package is already installed
            if pacman -Qi "$package" >/dev/null 2>&1; then
                log_debug "Package $package already installed"
                return 0
            fi
            
            # Try official repositories first
            if sudo pacman -S --noconfirm "$package" 2>/dev/null; then
                log_success "Installed package: $package (pacman)"
                return 0
            fi
            
            # Try AUR if official installation failed
            if command_exists yay; then
                if yay -S --noconfirm "$package"; then
                    log_success "Installed package: $package (AUR via yay)"
                    return 0
                fi
            elif command_exists paru; then
                if paru -S --noconfirm "$package"; then
                    log_success "Installed package: $package (AUR via paru)"
                    return 0
                fi
            fi
            
            log_error "Failed to install package: $package"
            return 1
            ;;
        "ubuntu")
            # Check if package is already installed
            if dpkg -l "$package" 2>/dev/null | grep -q "^ii"; then
                log_debug "Package $package already installed"
                return 0
            fi
            
            # Update package list if it's old
            local last_update=$(stat -c %Y /var/lib/apt/lists 2>/dev/null || echo 0)
            local current_time=$(date +%s)
            local age=$((current_time - last_update))
            
            if [[ $age -gt 3600 ]]; then  # 1 hour
                log_info "Updating package lists..."
                sudo apt-get update -qq
            fi
            
            # Install package
            if sudo apt-get install -y "$package"; then
                log_success "Installed package: $package (apt)"
                return 0
            fi
            
            log_error "Failed to install package: $package"
            return 1
            ;;
        *)
            log_error "Unsupported distribution for package installation: $distro"
            return 1
            ;;
    esac
}

# Install multiple packages
# Args: package_array_name [distribution]
install_packages() {
    local -n packages_ref=$1
    local distro="${2:-$DETECTED_DISTRO}"
    local failed_packages=()
    local success_count=0
    
    if [[ ${#packages_ref[@]} -eq 0 ]]; then
        log_warn "No packages to install"
        return 0
    fi
    
    log_info "Installing ${#packages_ref[@]} packages..."
    
    for package in "${packages_ref[@]}"; do
        # Skip empty lines and comments
        [[ -z "$package" || "$package" =~ ^[[:space:]]*# ]] && continue
        
        if install_package "$package" "$distro"; then
            success_count=$((success_count + 1))
        else
            failed_packages+=("$package")
        fi
    done
    
    log_info "Package installation complete: $success_count successful"
    
    if [[ ${#failed_packages[@]} -gt 0 ]]; then
        log_warn "Failed to install ${#failed_packages[@]} packages: ${failed_packages[*]}"
        return 1
    fi
    
    return 0
}

# Safe symlink creation with backup
# Args: source_path target_path [backup_directory] [force]
# Returns: 0 on success, 1 on failure
create_symlink() {
    local source="$1"
    local target="$2"
    local backup_dir="${3:-$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)}"
    local force="${4:-false}"
    
    if [[ -z "$source" || -z "$target" ]]; then
        log_error "Source and target paths are required for symlink creation"
        return 1
    fi
    
    # Convert to absolute paths
    source=$(realpath "$source" 2>/dev/null || echo "$source")
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create symlink: $target -> $source"
        return 0
    fi
    
    # Check if source exists
    if [[ ! -e "$source" ]]; then
        log_error "Source file does not exist: $source"
        return 1
    fi
    
    # Create target directory if it doesn't exist
    local target_dir=$(dirname "$target")
    if ! mkdir -p "$target_dir"; then
        log_error "Failed to create target directory: $target_dir"
        return 1
    fi
    
    # Handle existing target
    if [[ -e "$target" || -L "$target" ]]; then
        # Check if it's already the correct symlink
        if [[ -L "$target" ]] && [[ "$(readlink "$target")" == "$source" ]]; then
            log_debug "Symlink already exists and is correct: $target -> $source"
            return 0
        fi
        
        if [[ "$force" != "true" ]]; then
            if ! ask_yes_no "Target exists: $target. Replace it?" "n"; then
                log_info "Skipping symlink creation for: $target"
                return 0
            fi
        fi
        
        # Create backup
        log_info "Backing up existing file: $target"
        if ! mkdir -p "$backup_dir"; then
            log_error "Failed to create backup directory: $backup_dir"
            return 1
        fi
        
        local backup_name=$(basename "$target")
        local backup_path="$backup_dir/$backup_name"
        
        # Handle backup name conflicts
        local counter=1
        while [[ -e "$backup_path" ]]; do
            backup_path="$backup_dir/${backup_name}.${counter}"
            counter=$((counter + 1))
        done
        
        if ! mv "$target" "$backup_path"; then
            log_error "Failed to backup existing file: $target"
            return 1
        fi
        
        log_info "Backed up to: $backup_path"
    fi
    
    # Create symlink
    if ln -sf "$source" "$target"; then
        log_success "Created symlink: $target -> $source"
        return 0
    else
        log_error "Failed to create symlink: $target -> $source"
        return 1
    fi
}

# Create multiple symlinks from a directory
# Args: source_directory target_directory [backup_directory] [pattern]
create_symlinks_from_dir() {
    local source_dir="$1"
    local target_dir="$2"
    local backup_dir="${3:-$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)}"
    local pattern="${4:-*}"
    
    if [[ ! -d "$source_dir" ]]; then
        log_error "Source directory does not exist: $source_dir"
        return 1
    fi
    
    local created_count=0
    local failed_count=0
    
    while IFS= read -r -d '' file; do
        local relative_path="${file#$source_dir/}"
        local target_path="$target_dir/$relative_path"
        
        if create_symlink "$file" "$target_path" "$backup_dir" "true"; then
            created_count=$((created_count + 1))
        else
            failed_count=$((failed_count + 1))
        fi
    done < <(find "$source_dir" -name "$pattern" -type f -print0)
    
    log_info "Symlink creation complete: $created_count created, $failed_count failed"
    return $([[ $failed_count -eq 0 ]] && echo 0 || echo 1)
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Get system architecture
get_architecture() {
    uname -m
}

# Check if running in a virtual machine
is_vm() {
    if [[ "$VM_MODE" == "true" ]]; then
        return 0
    fi
    
    # Check for common VM indicators
    if command_exists systemd-detect-virt; then
        systemd-detect-virt -q && return 0
    fi
    
    # Check DMI information
    if [[ -r /sys/class/dmi/id/product_name ]]; then
        local product_name=$(cat /sys/class/dmi/id/product_name)
        case "$product_name" in
            *VirtualBox*|*VMware*|*QEMU*|*KVM*)
                return 0
                ;;
        esac
    fi
    
    return 1
}

# Create directory with proper permissions
create_directory() {
    local dir="$1"
    local mode="${2:-755}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create directory: $dir (mode: $mode)"
        return 0
    fi
    
    mkdir -p "$dir"
    chmod "$mode" "$dir"
}

# Download file with progress
download_file() {
    local url="$1"
    local output="$2"
    local show_progress="${3:-true}"
    
    if [[ -z "$url" || -z "$output" ]]; then
        log_error "URL and output path are required for download"
        return 1
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would download: $url -> $output"
        return 0
    fi
    
    # Create output directory if needed
    local output_dir=$(dirname "$output")
    mkdir -p "$output_dir"
    
    # Download with progress
    if command_exists curl; then
        if [[ "$show_progress" == "true" ]]; then
            curl -L --progress-bar -o "$output" "$url"
        else
            curl -L -s -o "$output" "$url"
        fi
    elif command_exists wget; then
        if [[ "$show_progress" == "true" ]]; then
            wget --progress=bar -O "$output" "$url"
        else
            wget -q -O "$output" "$url"
        fi
    else
        log_error "Neither curl nor wget available for downloading"
        return 1
    fi
}

# ============================================================================
# SYSTEM VALIDATION FUNCTIONS
# ============================================================================

# Check if running as root (should not be for most operations)
check_not_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root"
        log_info "Please run as a regular user. Sudo will be used when needed."
        return 1
    fi
    return 0
}

# Check if user has sudo privileges
check_sudo_access() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would check sudo access"
        return 0
    fi
    
    if ! sudo -n true 2>/dev/null; then
        log_info "Sudo access required. Please enter your password:"
        if ! sudo -v; then
            log_error "Sudo access is required for this installation"
            return 1
        fi
    fi
    
    log_success "Sudo access verified"
    return 0
}

# Check system prerequisites
check_system_prerequisites() {
    local required_commands=("bash" "grep" "sed" "awk" "find" "xargs")
    local missing_commands=()
    
    log_info "Checking system prerequisites..."
    
    # Check required commands
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        return 1
    fi
    
    # Check bash version (need 4.0+)
    local bash_version=$(bash --version | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -n1)
    local bash_major=$(echo "$bash_version" | cut -d. -f1)
    
    if [[ $bash_major -lt 4 ]]; then
        log_error "Bash 4.0 or higher is required (current: $bash_version)"
        return 1
    fi
    
    log_success "System prerequisites check passed"
    return 0
}

# Check available disk space
check_disk_space() {
    local required_space_gb="${1:-5}"  # Default 5GB
    local target_path="${2:-$HOME}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would check disk space: ${required_space_gb}GB required"
        return 0
    fi
    
    local available_space=$(df -BG "$target_path" | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [[ $available_space -lt $required_space_gb ]]; then
        log_error "Insufficient disk space. Required: ${required_space_gb}GB, Available: ${available_space}GB"
        return 1
    fi
    
    log_success "Disk space check passed: ${available_space}GB available"
    return 0
}

# Check system memory
check_memory() {
    local required_memory_gb="${1:-2}"  # Default 2GB
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would check memory: ${required_memory_gb}GB required"
        return 0
    fi
    
    local total_memory_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_memory_gb=$((total_memory_kb / 1024 / 1024))
    
    if [[ $total_memory_gb -lt $required_memory_gb ]]; then
        log_error "Insufficient memory. Required: ${required_memory_gb}GB, Available: ${total_memory_gb}GB"
        return 1
    fi
    
    log_success "Memory check passed: ${total_memory_gb}GB available"
    return 0
}

# Validate distribution support
validate_distribution() {
    local distro=$(detect_distro)
    
    case "$distro" in
        "arch"|"ubuntu")
            log_success "Supported distribution detected: $distro"
            export DETECTED_DISTRO="$distro"
            return 0
            ;;
        "unknown")
            log_error "Unsupported or unrecognized Linux distribution"
            log_info "This framework supports Arch Linux and Ubuntu only"
            return 1
            ;;
        *)
            log_error "Unsupported distribution: $distro"
            return 1
            ;;
    esac
}

# Check package manager availability
check_package_manager() {
    local distro="${1:-$DETECTED_DISTRO}"
    
    case "$distro" in
        "arch")
            if ! command_exists pacman; then
                log_error "pacman package manager not found"
                return 1
            fi
            log_success "Package manager available: pacman"
            ;;
        "ubuntu")
            if ! command_exists apt-get; then
                log_error "apt-get package manager not found"
                return 1
            fi
            log_success "Package manager available: apt-get"
            ;;
        *)
            log_error "Unknown distribution for package manager check: $distro"
            return 1
            ;;
    esac
    
    return 0
}

# Comprehensive system validation
validate_system() {
    local errors=0
    
    log_section "System Validation"
    
    # Check if not running as root
    if ! check_not_root; then
        errors=$((errors + 1))
    fi
    
    # Check sudo access
    if ! check_sudo_access; then
        errors=$((errors + 1))
    fi
    
    # Check system prerequisites
    if ! check_system_prerequisites; then
        errors=$((errors + 1))
    fi
    
    # Validate distribution
    if ! validate_distribution; then
        errors=$((errors + 1))
    fi
    
    # Check package manager
    if ! check_package_manager; then
        errors=$((errors + 1))
    fi
    
    # Check internet connectivity
    if ! check_internet_with_retry; then
        errors=$((errors + 1))
    fi
    
    # Check disk space (5GB minimum)
    if ! check_disk_space 5; then
        errors=$((errors + 1))
    fi
    
    # Check memory (2GB minimum)
    if ! check_memory 2; then
        errors=$((errors + 1))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "All system validation checks passed"
        return 0
    else
        log_error "System validation failed with $errors error(s)"
        return 1
    fi
}

# Get system information summary
get_system_info() {
    local distro=$(detect_distro)
    local arch=$(get_architecture)
    local kernel=$(uname -r)
    local memory_gb=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024))
    local disk_space=$(df -h "$HOME" | awk 'NR==2 {print $4}')
    
    echo "System Information:"
    echo "  Distribution: $distro"
    echo "  Architecture: $arch"
    echo "  Kernel: $kernel"
    echo "  Memory: ${memory_gb}GB"
    echo "  Available disk space: $disk_space"
    echo "  Virtual Machine: $(is_vm && echo "Yes" || echo "No")"
}