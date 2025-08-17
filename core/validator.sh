#!/bin/bash

# core/validator.sh - System validation and hardware detection module
# This module provides comprehensive system requirements checking, permission validation,
# dependency verification, and hardware detection capabilities for GPU and system-specific configurations.

# Source required modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/logger.sh"

# Global validation state
VALIDATION_ERRORS=()
VALIDATION_WARNINGS=()
HARDWARE_INFO=()

#######################################
# System Requirements Validation
#######################################

# Check minimum system requirements
# Returns: 0 if all requirements met, 1 if critical requirements missing
# Requirements: 10.4 - System requirements checking
validate_system_requirements() {
    log_section "System Requirements Validation"
    
    local critical_errors=0
    
    # Check Linux kernel version (minimum 5.0 for modern Wayland support)
    local kernel_version
    kernel_version=$(uname -r | cut -d. -f1-2)
    local kernel_major=$(echo "$kernel_version" | cut -d. -f1)
    local kernel_minor=$(echo "$kernel_version" | cut -d. -f2)
    
    if [[ $kernel_major -lt 5 ]]; then
        add_validation_error "Kernel version too old: $kernel_version (minimum: 5.0)"
        ((critical_errors++))
    else
        log_success "Kernel version: $kernel_version ✓"
    fi
    
    # Check available memory (minimum 4GB recommended)
    local total_mem_kb
    total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_mem_gb=$((total_mem_kb / 1024 / 1024))
    
    if [[ $total_mem_gb -lt 2 ]]; then
        add_validation_error "Insufficient memory: ${total_mem_gb}GB (minimum: 2GB)"
        ((critical_errors++))
    elif [[ $total_mem_gb -lt 4 ]]; then
        add_validation_warning "Low memory: ${total_mem_gb}GB (recommended: 4GB+)"
    else
        log_success "Memory: ${total_mem_gb}GB ✓"
    fi
    
    # Check available disk space (minimum 10GB for full installation)
    local available_space_kb
    available_space_kb=$(df / | awk 'NR==2 {print $4}')
    local available_space_gb=$((available_space_kb / 1024 / 1024))
    
    if [[ $available_space_gb -lt 5 ]]; then
        add_validation_error "Insufficient disk space: ${available_space_gb}GB (minimum: 5GB)"
        ((critical_errors++))
    elif [[ $available_space_gb -lt 10 ]]; then
        add_validation_warning "Low disk space: ${available_space_gb}GB (recommended: 10GB+)"
    else
        log_success "Disk space: ${available_space_gb}GB ✓"
    fi
    
    # Check CPU architecture
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)
            log_success "Architecture: $arch ✓"
            ;;
        aarch64|arm64)
            add_validation_warning "ARM architecture detected: $arch (limited support)"
            ;;
        *)
            add_validation_error "Unsupported architecture: $arch"
            ((critical_errors++))
            ;;
    esac
    
    return $critical_errors
}

# Validate distribution compatibility
# Returns: 0 if supported, 1 if unsupported
validate_distribution() {
    log_info "Validating distribution compatibility..."
    
    local distro
    distro=$(get_distro)
    local version
    version=$(get_distro_version)
    
    case "$distro" in
        "arch")
            log_success "Arch Linux detected ✓"
            # Check if system is up to date
            if command -v pacman >/dev/null 2>&1; then
                local updates
                updates=$(pacman -Qu 2>/dev/null | wc -l)
                if [[ $updates -gt 50 ]]; then
                    add_validation_warning "System has $updates pending updates (consider updating first)"
                fi
            fi
            ;;
        "ubuntu")
            log_success "Ubuntu $version detected ✓"
            # Check Ubuntu version compatibility
            local version_num
            version_num=$(echo "$version" | cut -d. -f1)
            if [[ $version_num -lt 20 ]]; then
                add_validation_error "Ubuntu version too old: $version (minimum: 20.04)"
                return 1
            fi
            ;;
        "unsupported")
            add_validation_error "Unsupported distribution detected"
            add_validation_error "Supported distributions: Arch Linux, Ubuntu 20.04+"
            return 1
            ;;
        *)
            add_validation_error "Unknown distribution: $distro"
            return 1
            ;;
    esac
    
    return 0
}

#######################################
# Permission Validation
#######################################

# Validate user permissions and sudo access
# Returns: 0 if valid permissions, 1 if insufficient permissions
# Requirements: 10.4 - Permission validation
validate_permissions() {
    log_info "Validating user permissions..."
    
    # Check if running as root (not recommended)
    if is_root; then
        add_validation_warning "Running as root is not recommended for security reasons"
        add_validation_warning "Consider running as a regular user with sudo privileges"
    fi
    
    # Check sudo access
    if ! has_sudo; then
        add_validation_error "Sudo privileges required but not available"
        add_validation_error "Please run: sudo -v"
        return 1
    else
        log_success "Sudo access available ✓"
    fi
    
    # Check write permissions to common directories
    local test_dirs=(
        "$HOME/.config"
        "$HOME/.local"
        "/tmp"
    )
    
    for dir in "${test_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir" 2>/dev/null || {
                add_validation_error "Cannot create directory: $dir"
                return 1
            }
        fi
        
        if [[ ! -w "$dir" ]]; then
            add_validation_error "No write permission to: $dir"
            return 1
        fi
    done
    
    log_success "Directory permissions ✓"
    
    # Check if user is in required groups (for hardware access)
    local required_groups=("video" "audio")
    local missing_groups=()
    
    for group in "${required_groups[@]}"; do
        if ! groups | grep -q "\b$group\b"; then
            missing_groups+=("$group")
        fi
    done
    
    if [[ ${#missing_groups[@]} -gt 0 ]]; then
        add_validation_warning "User not in groups: ${missing_groups[*]} (may affect hardware access)"
    else
        log_success "User groups ✓"
    fi
    
    return 0
}

#######################################
# Dependency Verification
#######################################

# Verify essential system dependencies
# Returns: 0 if all dependencies available, 1 if missing critical dependencies
validate_dependencies() {
    log_info "Validating system dependencies..."
    
    local critical_deps=("curl" "wget" "git" "tar" "gzip")
    local recommended_deps=("unzip" "rsync" "find" "grep" "awk" "sed")
    local missing_critical=()
    local missing_recommended=()
    
    # Check critical dependencies
    for dep in "${critical_deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_critical+=("$dep")
        fi
    done
    
    # Check recommended dependencies
    for dep in "${recommended_deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_recommended+=("$dep")
        fi
    done
    
    if [[ ${#missing_critical[@]} -gt 0 ]]; then
        add_validation_error "Missing critical dependencies: ${missing_critical[*]}"
        return 1
    else
        log_success "Critical dependencies ✓"
    fi
    
    if [[ ${#missing_recommended[@]} -gt 0 ]]; then
        add_validation_warning "Missing recommended tools: ${missing_recommended[*]}"
    else
        log_success "Recommended dependencies ✓"
    fi
    
    # Validate package managers
    validate_package_managers
    
    return 0
}

# Validate package manager availability
validate_package_managers() {
    local distro
    distro=$(get_distro)
    
    case "$distro" in
        "arch")
            if ! command -v pacman >/dev/null 2>&1; then
                add_validation_error "Pacman package manager not found"
                return 1
            fi
            log_success "Pacman package manager ✓"
            
            # Check for AUR helper (optional but recommended)
            if command -v yay >/dev/null 2>&1; then
                log_success "AUR helper (yay) available ✓"
            elif command -v paru >/dev/null 2>&1; then
                log_success "AUR helper (paru) available ✓"
            else
                add_validation_warning "No AUR helper found (yay/paru recommended)"
            fi
            ;;
        "ubuntu")
            if ! command -v apt >/dev/null 2>&1; then
                add_validation_error "APT package manager not found"
                return 1
            fi
            log_success "APT package manager ✓"
            
            # Check for snap (optional)
            if command -v snap >/dev/null 2>&1; then
                log_success "Snap package manager available ✓"
            else
                add_validation_warning "Snap not available (some packages may be unavailable)"
            fi
            ;;
    esac
    
    return 0
}

#######################################
# Hardware Detection
#######################################

# Detect GPU hardware and capabilities
# Returns: 0 always (detection is informational)
# Requirements: 2.1 - Hardware detection for GPU configurations
detect_gpu_hardware() {
    log_info "Detecting GPU hardware..."
    
    local gpu_info=()
    local nvidia_detected=false
    local amd_detected=false
    local intel_detected=false
    
    # Detect NVIDIA GPUs
    if lspci | grep -i nvidia >/dev/null 2>&1; then
        nvidia_detected=true
        local nvidia_cards
        nvidia_cards=$(lspci | grep -i nvidia | grep -i vga)
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                gpu_info+=("NVIDIA: $line")
                log_success "NVIDIA GPU detected: $line"
            fi
        done <<< "$nvidia_cards"
        
        # Check for NVIDIA driver
        if command -v nvidia-smi >/dev/null 2>&1; then
            local driver_version
            driver_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits 2>/dev/null | head -n1)
            if [[ -n "$driver_version" ]]; then
                log_success "NVIDIA driver installed: $driver_version"
                add_hardware_info "nvidia_driver_version" "$driver_version"
            fi
        else
            add_validation_warning "NVIDIA GPU detected but no driver installed"
        fi
    fi
    
    # Detect AMD GPUs
    if lspci | grep -i amd | grep -i vga >/dev/null 2>&1; then
        amd_detected=true
        local amd_cards
        amd_cards=$(lspci | grep -i amd | grep -i vga)
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                gpu_info+=("AMD: $line")
                log_success "AMD GPU detected: $line"
            fi
        done <<< "$amd_cards"
    fi
    
    # Detect Intel integrated graphics
    if lspci | grep -i intel | grep -i vga >/dev/null 2>&1; then
        intel_detected=true
        local intel_cards
        intel_cards=$(lspci | grep -i intel | grep -i vga)
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                gpu_info+=("Intel: $line")
                log_success "Intel GPU detected: $line"
            fi
        done <<< "$intel_cards"
    fi
    
    # Store GPU detection results
    add_hardware_info "nvidia_gpu" "$nvidia_detected"
    add_hardware_info "amd_gpu" "$amd_detected"
    add_hardware_info "intel_gpu" "$intel_detected"
    
    # Check for multiple GPUs (hybrid graphics)
    local gpu_count=$((nvidia_detected + amd_detected + intel_detected))
    if [[ $gpu_count -gt 1 ]]; then
        add_hardware_info "hybrid_graphics" "true"
        log_info "Hybrid graphics configuration detected"
        
        # Check for ASUS TUF specific configuration
        detect_asus_tuf_hardware
    else
        add_hardware_info "hybrid_graphics" "false"
    fi
    
    if [[ ${#gpu_info[@]} -eq 0 ]]; then
        add_validation_warning "No discrete GPU detected"
    fi
    
    return 0
}

# Detect ASUS TUF specific hardware features
# Requirements: 2.1 - MUX switch support for ASUS TUF Dash F15
detect_asus_tuf_hardware() {
    log_info "Checking for ASUS TUF specific features..."
    
    # Check DMI information for ASUS TUF
    local product_name
    product_name=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "")
    local board_name
    board_name=$(cat /sys/class/dmi/id/board_name 2>/dev/null || echo "")
    
    if [[ "$product_name" =~ TUF.*Dash.*F15 ]] || [[ "$board_name" =~ TUF.*Dash.*F15 ]]; then
        log_success "ASUS TUF Dash F15 detected ✓"
        add_hardware_info "asus_tuf_dash_f15" "true"
        add_hardware_info "mux_switch_support" "true"
        
        # Check for MUX switch capability
        if [[ -d /sys/bus/wmi/devices ]]; then
            if find /sys/bus/wmi/devices -name "*ASUS*" | grep -q .; then
                log_success "ASUS WMI interface detected (MUX switch support) ✓"
            fi
        fi
    else
        add_hardware_info "asus_tuf_dash_f15" "false"
        add_hardware_info "mux_switch_support" "false"
    fi
    
    return 0
}

# Detect system-specific configurations
detect_system_hardware() {
    log_info "Detecting system hardware configuration..."
    
    # Detect CPU information
    local cpu_info
    cpu_info=$(grep "model name" /proc/cpuinfo | head -n1 | cut -d: -f2 | xargs)
    if [[ -n "$cpu_info" ]]; then
        log_success "CPU: $cpu_info"
        add_hardware_info "cpu_model" "$cpu_info"
    fi
    
    # Detect memory configuration
    local total_mem_gb
    total_mem_gb=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024/1024)}')
    add_hardware_info "total_memory_gb" "$total_mem_gb"
    
    # Detect storage information
    local root_fs
    root_fs=$(df -T / | awk 'NR==2 {print $2}')
    add_hardware_info "root_filesystem" "$root_fs"
    
    # Check for SSD vs HDD
    local root_device
    root_device=$(df / | awk 'NR==2 {print $1}' | sed 's/[0-9]*$//')
    if [[ -f "/sys/block/$(basename "$root_device")/queue/rotational" ]]; then
        local is_rotational
        is_rotational=$(cat "/sys/block/$(basename "$root_device")/queue/rotational")
        if [[ "$is_rotational" == "0" ]]; then
            log_success "SSD storage detected ✓"
            add_hardware_info "storage_type" "ssd"
        else
            log_info "HDD storage detected"
            add_hardware_info "storage_type" "hdd"
        fi
    fi
    
    # Detect Wayland/X11 session
    if [[ -n "$WAYLAND_DISPLAY" ]]; then
        log_success "Wayland session detected ✓"
        add_hardware_info "display_server" "wayland"
    elif [[ -n "$DISPLAY" ]]; then
        log_info "X11 session detected"
        add_hardware_info "display_server" "x11"
    else
        log_info "No display server detected (console mode)"
        add_hardware_info "display_server" "console"
    fi
    
    return 0
}

#######################################
# Validation State Management
#######################################

# Add validation error
add_validation_error() {
    local error="$1"
    VALIDATION_ERRORS+=("$error")
    log_error "$error"
}

# Add validation warning
add_validation_warning() {
    local warning="$1"
    VALIDATION_WARNINGS+=("$warning")
    log_warn "$warning"
}

# Add hardware information
add_hardware_info() {
    local key="$1"
    local value="$2"
    HARDWARE_INFO+=("$key=$value")
}

# Get hardware information by key
get_hardware_info() {
    local key="$1"
    for info in "${HARDWARE_INFO[@]}"; do
        if [[ "$info" =~ ^$key= ]]; then
            echo "${info#*=}"
            return 0
        fi
    done
    return 1
}

# Check if hardware feature is available
has_hardware_feature() {
    local feature="$1"
    local value
    value=$(get_hardware_info "$feature")
    [[ "$value" == "true" ]]
}

#######################################
# Comprehensive Validation Functions
#######################################

# Run all validation checks
# Returns: 0 if all critical validations pass, 1 if critical errors found
validate_all() {
    log_section "Comprehensive System Validation"
    
    # Clear previous validation state
    VALIDATION_ERRORS=()
    VALIDATION_WARNINGS=()
    HARDWARE_INFO=()
    
    local critical_failures=0
    
    # Run all validation checks
    validate_system_requirements || ((critical_failures++))
    validate_distribution || ((critical_failures++))
    validate_permissions || ((critical_failures++))
    validate_dependencies || ((critical_failures++))
    
    # Run hardware detection (informational)
    detect_gpu_hardware
    detect_system_hardware
    
    # Display validation summary
    display_validation_summary
    
    return $critical_failures
}

# Display validation summary
display_validation_summary() {
    log_section "Validation Summary"
    
    if [[ ${#VALIDATION_ERRORS[@]} -eq 0 ]]; then
        log_success "All critical validations passed ✓"
    else
        log_error "Found ${#VALIDATION_ERRORS[@]} critical error(s):"
        for error in "${VALIDATION_ERRORS[@]}"; do
            echo "  ❌ $error"
        done
    fi
    
    if [[ ${#VALIDATION_WARNINGS[@]} -gt 0 ]]; then
        log_warn "Found ${#VALIDATION_WARNINGS[@]} warning(s):"
        for warning in "${VALIDATION_WARNINGS[@]}"; do
            echo "  ⚠️  $warning"
        done
    fi
    
    # Display hardware summary
    if [[ ${#HARDWARE_INFO[@]} -gt 0 ]]; then
        echo
        log_info "Hardware Configuration:"
        for info in "${HARDWARE_INFO[@]}"; do
            local key="${info%=*}"
            local value="${info#*=}"
            printf "  %-20s: %s\n" "$key" "$value"
        done
    fi
}

# Validate specific component requirements
# Arguments: $1 - component name
# Returns: 0 if component can be installed, 1 if requirements not met
validate_component() {
    local component="$1"
    
    log_info "Validating requirements for component: $component"
    
    case "$component" in
        "hyprland")
            # Check for Wayland support
            if [[ "$(get_hardware_info "display_server")" == "wayland" ]]; then
                log_success "Wayland session available for Hyprland ✓"
            else
                add_validation_warning "Hyprland works best with Wayland (current: $(get_hardware_info "display_server"))"
            fi
            
            # Check GPU compatibility
            if has_hardware_feature "nvidia_gpu"; then
                log_info "NVIDIA GPU detected - ensure proper drivers are installed"
            fi
            ;;
        "nvidia")
            if ! has_hardware_feature "nvidia_gpu"; then
                add_validation_error "NVIDIA component requested but no NVIDIA GPU detected"
                return 1
            fi
            log_success "NVIDIA GPU available for driver installation ✓"
            ;;
        "gaming")
            # Check for discrete GPU
            if has_hardware_feature "nvidia_gpu" || has_hardware_feature "amd_gpu"; then
                log_success "Discrete GPU available for gaming setup ✓"
            else
                add_validation_warning "No discrete GPU detected - gaming performance may be limited"
            fi
            ;;
    esac
    
    return 0
}

# Source this file to make functions available
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This file should be sourced, not executed directly"
    echo "Usage: source core/validator.sh"
    exit 1
fi