#!/bin/bash

# System validation and prerequisite checking
# Validates system requirements, permissions, and dependencies

# Validate overall system requirements
validate_system() {
    log_info "Validating system requirements..."
    
    local validation_failed=false
    
    # Check if running as root (should not be)
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root"
        validation_failed=true
    fi
    
    # Check sudo access
    if ! validate_sudo; then
        log_error "Sudo access required but not available"
        validation_failed=true
    fi
    
    # Check internet connectivity
    if ! check_internet; then
        log_error "Internet connectivity required but not available"
        validation_failed=true
    fi
    
    # Check disk space
    if ! validate_disk_space; then
        log_error "Insufficient disk space"
        validation_failed=true
    fi
    
    # Check required commands
    if ! validate_required_commands; then
        log_error "Required system commands not available"
        validation_failed=true
    fi
    
    # Distribution-specific validation
    if ! validate_distribution; then
        log_error "Distribution validation failed"
        validation_failed=true
    fi
    
    if [[ "$validation_failed" == "true" ]]; then
        return 1
    fi
    
    log_success "System validation passed"
    return 0
}

# Validate sudo access
validate_sudo() {
    if sudo -n true 2>/dev/null; then
        return 0
    fi
    
    log_info "Testing sudo access..."
    if sudo -v; then
        return 0
    else
        return 1
    fi
}

# Validate available disk space
validate_disk_space() {
    local required_space_gb=5
    local available_space_gb
    
    # Get available space in GB for home directory
    available_space_gb=$(df -BG "$HOME" | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [[ $available_space_gb -lt $required_space_gb ]]; then
        log_error "Insufficient disk space. Required: ${required_space_gb}GB, Available: ${available_space_gb}GB"
        return 1
    fi
    
    log_debug "Disk space check passed: ${available_space_gb}GB available"
    return 0
}

# Validate required system commands
validate_required_commands() {
    local required_commands=("curl" "git" "tar" "unzip")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        return 1
    fi
    
    log_debug "Required commands check passed"
    return 0
}

# Validate distribution-specific requirements
validate_distribution() {
    local distro="$DETECTED_DISTRO"
    
    case "$distro" in
        "arch")
            validate_arch_requirements
            ;;
        "ubuntu")
            validate_ubuntu_requirements
            ;;
        "unknown")
            log_error "Unsupported or undetected Linux distribution"
            return 1
            ;;
        *)
            log_error "Unknown distribution: $distro"
            return 1
            ;;
    esac
}

# Validate Arch Linux specific requirements
validate_arch_requirements() {
    log_debug "Validating Arch Linux requirements..."
    
    # Check if pacman is available
    if ! command_exists pacman; then
        log_error "pacman package manager not found"
        return 1
    fi
    
    # Check if system is up to date
    if ! pacman -Qu >/dev/null 2>&1; then
        log_warn "System packages may be out of date. Consider running 'sudo pacman -Syu'"
    fi
    
    # Check if multilib repository is enabled (for some packages)
    if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
        log_warn "Multilib repository not enabled. Some packages may not be available."
    fi
    
    return 0
}

# Validate Ubuntu specific requirements
validate_ubuntu_requirements() {
    log_debug "Validating Ubuntu requirements..."
    
    # Check if apt is available
    if ! command_exists apt-get; then
        log_error "apt package manager not found"
        return 1
    fi
    
    # Check Ubuntu version
    local ubuntu_version
    if [[ -f /etc/lsb-release ]]; then
        ubuntu_version=$(grep "DISTRIB_RELEASE" /etc/lsb-release | cut -d'=' -f2)
        log_debug "Ubuntu version: $ubuntu_version"
        
        # Check if version is supported (18.04+)
        if [[ $(echo "$ubuntu_version" | cut -d'.' -f1) -lt 18 ]]; then
            log_error "Ubuntu version $ubuntu_version is not supported. Minimum version: 18.04"
            return 1
        fi
    fi
    
    # Check if universe repository is enabled
    if ! grep -q "^deb.*universe" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
        log_warn "Universe repository may not be enabled. Some packages may not be available."
    fi
    
    return 0
}

# Validate hardware requirements
validate_hardware() {
    log_debug "Validating hardware requirements..."
    
    # Check RAM (minimum 4GB recommended)
    local ram_gb=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $ram_gb -lt 4 ]]; then
        log_warn "Low RAM detected: ${ram_gb}GB. Minimum 4GB recommended."
    fi
    
    # Check CPU architecture
    local arch=$(get_architecture)
    case "$arch" in
        x86_64|amd64)
            log_debug "Architecture check passed: $arch"
            ;;
        *)
            log_warn "Untested architecture: $arch. Some components may not work correctly."
            ;;
    esac
    
    return 0
}

# Validate GPU for graphics-intensive components
validate_gpu() {
    log_debug "Validating GPU configuration..."
    
    # Check for NVIDIA GPU
    if lspci | grep -i nvidia >/dev/null 2>&1; then
        log_info "NVIDIA GPU detected"
        
        # Check if NVIDIA drivers are installed
        if ! command_exists nvidia-smi; then
            log_warn "NVIDIA GPU detected but drivers may not be installed"
        fi
    fi
    
    # Check for AMD GPU
    if lspci | grep -i amd >/dev/null 2>&1; then
        log_info "AMD GPU detected"
    fi
    
    # Check for Intel GPU
    if lspci | grep -i intel.*graphics >/dev/null 2>&1; then
        log_info "Intel GPU detected"
    fi
    
    return 0
}

# Validate network configuration
validate_network() {
    log_debug "Validating network configuration..."
    
    # Check DNS resolution
    if ! nslookup google.com >/dev/null 2>&1; then
        log_warn "DNS resolution may be problematic"
    fi
    
    # Check if behind proxy
    if [[ -n "${http_proxy:-}" || -n "${HTTP_PROXY:-}" ]]; then
        log_info "HTTP proxy detected: ${http_proxy:-$HTTP_PROXY}"
    fi
    
    return 0
}

# Validate permissions for specific directories
validate_permissions() {
    local directories=("$HOME/.config" "$HOME/.local" "/tmp")
    
    for dir in "${directories[@]}"; do
        if [[ ! -w "$dir" ]]; then
            log_error "No write permission for directory: $dir"
            return 1
        fi
    done
    
    log_debug "Directory permissions check passed"
    return 0
}