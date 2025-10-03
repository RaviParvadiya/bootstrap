#!/usr/bin/env bash

# core/validator.sh - Simple system validation for package installation and dotfiles
# Provides basic validation for supported distributions and system requirements

# Initialize paths if needed
if [[ -z "${PATHS_SOURCED:-}" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/init-paths.sh"
fi

# Source dependencies
if [[ -z "${COMMON_SOURCED:-}" ]]; then
    source "$CORE_DIR/common.sh"
fi
if [[ -z "${LOGGER_SOURCED:-}" ]]; then
    source "$CORE_DIR/logger.sh"
fi

# Simple system validation
validate_system() {
    log_info "Validating system requirements..."
    
    # Check if we're running as root (we shouldn't be)
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root"
        return 1
    fi
    
    # Check if we have sudo access
    if ! sudo -n true 2>/dev/null; then
        log_warn "Sudo access may be required for package installation"
        if ! sudo -v; then
            log_error "Sudo access is required but not available"
            return 1
        fi
    fi
    
    # Check basic tools
    local required_tools=("curl" "git")
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install these tools before running the installer"
        return 1
    fi
    
    # Check available disk space (at least 1GB free)
    local available_space
    available_space=$(df / | awk 'NR==2 {print $4}')
    local available_gb=$((available_space / 1024 / 1024))
    
    if [[ $available_gb -lt 1 ]]; then
        log_warn "Low disk space: ${available_gb}GB available (recommended: 1GB+)"
    fi
    
    log_success "System validation passed"
    return 0
}

# Simple distribution support validation
validate_distro_support() {
    local distro
    distro=$(get_distro)
    
    case "$distro" in
        "arch"|"ubuntu")
            log_success "Distribution supported: $distro"
            return 0
            ;;
        *)
            log_error "Unsupported distribution: $distro"
            log_info "Supported distributions: Arch Linux, Ubuntu"
            return 1
            ;;
    esac
}

# Export functions
export -f validate_system
export -f validate_distro_support