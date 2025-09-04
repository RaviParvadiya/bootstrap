#!/usr/bin/env bash

# Arch Linux Package Management
# Handles pacman and AUR package installation

# Initialize all project paths
source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"

# Source core utilities
source "$CORE_DIR/common.sh"
source "$CORE_DIR/logger.sh"

# Install packages using pacman
arch_install_pacman_packages() {
    local packages=("$@")
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        log_warn "No packages specified for pacman installation"
        return 0
    fi
    
    log_info "Installing pacman packages: ${packages[*]}"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would run: pacman -S --needed --noconfirm ${packages[*]}"
        return 0
    fi
    
    # Install packages with --needed to skip already installed ones
    if ! sudo pacman -S --needed --noconfirm "${packages[@]}"; then
        log_error "Failed to install some pacman packages"
        return 1
    fi
    
    log_success "Pacman packages installed successfully"
    return 0
}

# Install packages using AUR helper
arch_install_aur_packages() {
    local packages=("$@")
    local aur_helper
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        log_warn "No packages specified for AUR installation"
        return 0
    fi
    
    # Determine which AUR helper to use
    aur_helper=$(arch_get_aur_helper)
    if [[ -z "$aur_helper" ]]; then
        log_error "No AUR helper available"
        return 1
    fi
    
    log_info "Installing AUR packages using $aur_helper: ${packages[*]}"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would run: $aur_helper -S --needed --noconfirm ${packages[*]}"
        return 0
    fi
    
    # Install AUR packages
    if ! $aur_helper -S --needed --noconfirm "${packages[@]}"; then
        log_error "Failed to install some AUR packages"
        return 1
    fi
    
    log_success "AUR packages installed successfully"
    return 0
}

# Get available AUR helper
arch_get_aur_helper() {
    local helpers=("yay" "paru" "trizen" "yaourt")
    
    for helper in "${helpers[@]}"; do
        if command -v "$helper" >/dev/null 2>&1; then
            echo "$helper"
            return 0
        fi
    done
    
    return 1
}

# Ensure AUR helper is installed
arch_ensure_aur_helper() {
    log_info "Checking for AUR helper..."
    
    # Check if any AUR helper is already installed
    if arch_get_aur_helper >/dev/null 2>&1; then
        local current_helper
        current_helper=$(arch_get_aur_helper)
        log_info "AUR helper already available: $current_helper"
        return 0
    fi
    
    log_info "No AUR helper found, installing yay..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would install yay AUR helper"
        return 0
    fi
    
    # Install dependencies for building yay
    if ! sudo pacman -S --needed --noconfirm base-devel git; then
        log_error "Failed to install yay dependencies"
        return 1
    fi
    
    # Create temporary directory for building yay
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Clone and build yay
    (
        cd "$temp_dir" || exit 1
        git clone https://aur.archlinux.org/yay.git
        cd yay || exit 1
        makepkg -si --noconfirm
    )
    
    local build_result=$?
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
    
    if [[ $build_result -ne 0 ]]; then
        log_error "Failed to build and install yay"
        return 1
    fi
    
    log_success "yay AUR helper installed successfully"
    return 0
}

# Install packages from package list file
arch_install_from_package_list() {
    local package_list_file="$1"
    local package_type="${2:-pacman}"  # pacman or aur
    local conditions="${3:-}"  # Optional conditions to filter packages
    
    if [[ ! -f "$package_list_file" ]]; then
        log_error "Package list file not found: $package_list_file"
        return 1
    fi
    
    log_info "Installing packages from: $package_list_file (type: $package_type)"
    
    # Read packages from file, ignoring comments and empty lines
    local packages=()
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        # Handle conditional packages (package|condition)
        if [[ "$line" =~ \| ]]; then
            local package="${line%%|*}"
            local condition="${line##*|}"
            
            # Check if condition should be included
            if arch_should_include_condition "$condition" "$conditions"; then
                packages+=("$package")
            fi
        else
            packages+=("$line")
        fi
    done < "$package_list_file"
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        log_warn "No packages to install from $package_list_file"
        return 0
    fi
    
    # Install packages based on type
    case "$package_type" in
        "pacman")
            arch_install_pacman_packages "${packages[@]}"
            ;;
        "aur")
            arch_install_aur_packages "${packages[@]}"
            ;;
        *)
            log_error "Unknown package type: $package_type"
            return 1
            ;;
    esac
}

# Check if a condition should be included based on system state and user preferences
arch_should_include_condition() {
    local condition="$1"
    local user_conditions="$2"
    
    case "$condition" in
        "nvidia")
            arch_has_nvidia_gpu && [[ "$user_conditions" =~ nvidia ]]
            ;;
        "amd")
            arch_has_amd_gpu && [[ "$user_conditions" =~ amd ]]
            ;;
        "intel")
            arch_has_intel_gpu && [[ "$user_conditions" =~ intel ]]
            ;;
        "gaming")
            [[ "$user_conditions" =~ gaming ]]
            ;;
        "laptop")
            arch_is_laptop && [[ "$user_conditions" =~ laptop ]]
            ;;
        "vm")
            arch_is_vm && [[ "$user_conditions" =~ vm ]]
            ;;
        "asus")
            arch_is_asus_hardware && [[ "$user_conditions" =~ asus ]]
            ;;
        *)
            # Default: include package if no specific condition
            return 0
            ;;
    esac
}

# Install packages by category with conditions
arch_install_packages_by_category() {
    local category="$1"
    local conditions="${2:-}"
    local data_dir="${3:-$DATA_DIR}"
    
    log_info "Installing $category packages with conditions: $conditions"
    
    case "$category" in
        "base"|"system")
            arch_install_from_package_list "$data_dir/arch-packages.lst" "pacman" "$conditions"
            ;;
        "aur")
            # Ensure AUR helper is available first
            arch_ensure_aur_helper
            arch_install_from_package_list "$data_dir/aur-packages.lst" "aur" "$conditions"
            ;;
        "all")
            arch_install_packages_by_category "base" "$conditions" "$data_dir"
            arch_install_packages_by_category "aur" "$conditions" "$data_dir"
            ;;
        *)
            log_error "Unknown package category: $category"
            return 1
            ;;
    esac
}

# Install base packages required for the framework
arch_install_base_packages() {
    log_info "Installing base packages for Arch Linux..."
    
    local base_packages=(
        "base-devel"
        "git"
        "curl"
        "wget"
        "unzip"
        "tar"
        "gzip"
        "sudo"
        "which"
        "man-db"
        "man-pages"
    )
    
    arch_install_pacman_packages "${base_packages[@]}"
}

# Hardware detection helpers
arch_has_nvidia_gpu() {
    lspci | grep -i nvidia >/dev/null 2>&1
}

arch_has_intel_gpu() {
    lspci | grep -i "intel.*graphics\|intel.*vga" >/dev/null 2>&1
}

arch_has_amd_gpu() {
    lspci | grep -i "amd\|ati" >/dev/null 2>&1
}

arch_is_laptop() {
    # Check if system is a laptop
    [[ -d /sys/class/power_supply/BAT* ]] || \
    [[ -f /sys/class/dmi/id/chassis_type ]] && \
    [[ "$(cat /sys/class/dmi/id/chassis_type 2>/dev/null)" =~ ^(8|9|10|14)$ ]]
}

arch_is_vm() {
    # Check if running in a virtual machine
    systemd-detect-virt >/dev/null 2>&1 || \
    [[ "$(dmidecode -s system-manufacturer 2>/dev/null)" =~ (VMware|VirtualBox|QEMU|Xen|Microsoft Corporation) ]] || \
    [[ -f /proc/cpuinfo ]] && grep -q "hypervisor" /proc/cpuinfo
}

arch_is_asus_hardware() {
    # Check if system is ASUS hardware
    [[ "$(dmidecode -s system-manufacturer 2>/dev/null)" =~ ASUS ]] || \
    [[ "$(dmidecode -s baseboard-manufacturer 2>/dev/null)" =~ ASUS ]]
}

# Check if package is installed
arch_is_package_installed() {
    local package="$1"
    pacman -Qi "$package" >/dev/null 2>&1
}

# Get installed package version
arch_get_package_version() {
    local package="$1"
    pacman -Qi "$package" 2>/dev/null | grep "Version" | awk '{print $3}'
}

# Remove packages
arch_remove_packages() {
    local packages=("$@")
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        log_warn "No packages specified for removal"
        return 0
    fi
    
    log_info "Removing packages: ${packages[*]}"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would run: pacman -Rs --noconfirm ${packages[*]}"
        return 0
    fi
    
    if ! sudo pacman -Rs --noconfirm "${packages[@]}"; then
        log_error "Failed to remove some packages"
        return 1
    fi
    
    log_success "Packages removed successfully"
    return 0
}

# Clean package cache
arch_clean_package_cache() {
    log_info "Cleaning package cache..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would run: pacman -Sc --noconfirm"
        return 0
    fi
    
    if ! sudo pacman -Sc --noconfirm; then
        log_warn "Failed to clean package cache"
        return 1
    fi
    
    log_success "Package cache cleaned"
    return 0
}

# Export functions for external use
export -f arch_install_pacman_packages
export -f arch_install_aur_packages
export -f arch_get_aur_helper
export -f arch_ensure_aur_helper
export -f arch_install_from_package_list
export -f arch_install_base_packages
export -f arch_is_package_installed
export -f arch_get_package_version
export -f arch_remove_packages
export -f arch_clean_package_cache

# Configure pacman for better performance and appearance
arch_configure_pacman() {
    log_info "Configuring pacman for better performance..."
    
    local pacman_conf="/etc/pacman.conf"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would configure pacman settings"
        return 0
    fi
    
    # Create backup
    sudo cp "$pacman_conf" "$pacman_conf.backup.config.$(date +%Y%m%d_%H%M%S)"
    
    # Enable color output, verbose package lists, and parallel downloads
    sudo sed -i 's/^#Color/Color/; s/^#VerbosePkgLists/VerbosePkgLists/; s/^#ParallelDownloads = 5/ParallelDownloads = 5/' "$pacman_conf"
    
    log_success "Pacman configuration updated"
    return 0
}

# Configure makepkg for faster compression
arch_configure_makepkg() {
    log_info "Configuring makepkg for faster compression..."
    
    local makepkg_conf="/etc/makepkg.conf"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would configure makepkg compression settings"
        return 0
    fi
    
    # Create backup
    sudo cp "$makepkg_conf" "$makepkg_conf.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Use faster compression for packages
    sudo sed -i 's/COMPRESSZST=(zstd -c -T0 --ultra -20 -)/COMPRESSZST=(zstd -c -T0 --fast -)/' "$makepkg_conf"
    
    log_success "Makepkg configuration updated for faster compression"
    return 0
}

# Install and configure reflector for mirror management
arch_setup_reflector() {
    log_info "Setting up reflector for mirror management..."
    
    # Install reflector if not already installed
    if ! arch_is_package_installed "reflector"; then
        arch_install_pacman_packages "reflector"
    fi
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would configure reflector service"
        return 0
    fi
    
    # Enable and start reflector timer
    sudo systemctl enable reflector.timer
    sudo systemctl start reflector.timer
    
    log_success "Reflector configured and enabled"
    return 0
}

# Enable SSD TRIM support
arch_enable_trim() {
    log_info "Enabling SSD TRIM support..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would enable fstrim.timer"
        return 0
    fi
    
    # Enable fstrim timer for SSD maintenance
    sudo systemctl enable fstrim.timer
    
    log_success "SSD TRIM support enabled"
    return 0
}

# Complete Arch Linux system setup
arch_setup_system() {
    log_info "Setting up Arch Linux system configuration..."
    
    # Configure pacman
    arch_configure_pacman
    
    # Configure makepkg
    arch_configure_makepkg
    
    # Setup reflector
    arch_setup_reflector
    
    # Enable TRIM for SSDs
    arch_enable_trim
    
    log_success "Arch Linux system setup completed"
    return 0
}

# Install packages with automatic condition detection
arch_install_packages_auto() {
    local category="$1"
    local user_preferences="${2:-}"
    
    # Detect system conditions automatically
    local conditions=()
    
    # Hardware detection
    if arch_has_nvidia_gpu; then
        conditions+=("nvidia")
    fi
    
    if arch_has_amd_gpu; then
        conditions+=("amd")
    fi
    
    if arch_has_intel_gpu; then
        conditions+=("intel")
    fi
    
    # System type detection
    if arch_is_laptop; then
        conditions+=("laptop")
    fi
    
    if arch_is_vm; then
        conditions+=("vm")
    fi
    
    if arch_is_asus_hardware; then
        conditions+=("asus")
    fi
    
    # Add user preferences
    if [[ -n "$user_preferences" ]]; then
        IFS=',' read -ra user_prefs <<< "$user_preferences"
        conditions+=("${user_prefs[@]}")
    fi
    
    # Convert array to space-separated string
    local conditions_str="${conditions[*]}"
    
    log_info "Auto-detected conditions: $conditions_str"
    
    # Install packages with detected conditions
    arch_install_packages_by_category "$category" "$conditions_str"
}

# Export new functions
export -f arch_configure_pacman
export -f arch_configure_makepkg
export -f arch_setup_reflector
export -f arch_enable_trim
export -f arch_setup_system
export -f arch_install_packages_auto
export -f arch_is_laptop
export -f arch_is_vm
export -f arch_is_asus_hardware