#!/bin/bash

# Arch Linux Package Management
# Handles pacman and AUR package installation

# Source core utilities
source "$(dirname "${BASH_SOURCE[0]}")/../../core/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../core/logger.sh"

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
            
            # Simple condition evaluation (can be extended)
            case "$condition" in
                "nvidia")
                    if arch_has_nvidia_gpu; then
                        packages+=("$package")
                    fi
                    ;;
                "intel")
                    if arch_has_intel_gpu; then
                        packages+=("$package")
                    fi
                    ;;
                *)
                    # Default: include package
                    packages+=("$package")
                    ;;
            esac
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