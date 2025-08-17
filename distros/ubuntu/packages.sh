#!/bin/bash

# Ubuntu Package Management
# Handles APT, snap, and flatpak package installation

# Source core utilities
source "$(dirname "${BASH_SOURCE[0]}")/../../core/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../core/logger.sh"

# Install packages using APT
ubuntu_install_apt_packages() {
    local packages=("$@")
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        log_warn "No packages specified for APT installation"
        return 0
    fi
    
    log_info "Installing APT packages: ${packages[*]}"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would run: apt install -y ${packages[*]}"
        return 0
    fi
    
    # Update package database first
    sudo apt update
    
    # Install packages
    if ! sudo apt install -y "${packages[@]}"; then
        log_error "Failed to install some APT packages"
        return 1
    fi
    
    log_success "APT packages installed successfully"
    return 0
}

# Install packages using snap
ubuntu_install_snap_packages() {
    local packages=("$@")
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        log_warn "No packages specified for snap installation"
        return 0
    fi
    
    # Check if snapd is installed
    if ! command -v snap >/dev/null 2>&1; then
        log_info "Installing snapd..."
        if ! ubuntu_install_apt_packages snapd; then
            log_error "Failed to install snapd"
            return 1
        fi
    fi
    
    log_info "Installing snap packages: ${packages[*]}"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would run: snap install ${packages[*]}"
        return 0
    fi
    
    # Install snap packages
    for package in "${packages[@]}"; do
        # Handle different snap installation modes
        if [[ "$package" == *"--classic" ]]; then
            # Package with classic confinement
            local pkg_name="${package%% *}"
            if ! sudo snap install "$pkg_name" --classic; then
                log_warn "Failed to install snap package: $pkg_name (classic)"
            fi
        elif [[ "$package" == *"--edge" ]]; then
            # Package from edge channel
            local pkg_name="${package%% *}"
            if ! sudo snap install "$pkg_name" --edge; then
                log_warn "Failed to install snap package: $pkg_name (edge)"
            fi
        else
            # Regular snap package
            if ! sudo snap install "$package"; then
                log_warn "Failed to install snap package: $package"
            fi
        fi
    done
    
    log_success "Snap packages installation completed"
    return 0
}

# Install packages using flatpak
ubuntu_install_flatpak_packages() {
    local packages=("$@")
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        log_warn "No packages specified for flatpak installation"
        return 0
    fi
    
    # Check if flatpak is installed
    if ! command -v flatpak >/dev/null 2>&1; then
        log_info "Installing flatpak..."
        if ! ubuntu_install_apt_packages flatpak; then
            log_error "Failed to install flatpak"
            return 1
        fi
        
        # Add flathub repository
        log_info "Adding Flathub repository..."
        if [[ "${DRY_RUN:-false}" != "true" ]]; then
            sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
        fi
    fi
    
    log_info "Installing flatpak packages: ${packages[*]}"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would run: flatpak install -y flathub ${packages[*]}"
        return 0
    fi
    
    # Install flatpak packages
    for package in "${packages[@]}"; do
        if ! sudo flatpak install -y flathub "$package"; then
            log_warn "Failed to install flatpak package: $package"
        fi
    done
    
    log_success "Flatpak packages installation completed"
    return 0
}

# Install packages from package list file
ubuntu_install_from_package_list() {
    local package_list_file="$1"
    local package_type="${2:-apt}"  # apt, snap, or flatpak
    
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
                    if ubuntu_has_nvidia_gpu; then
                        packages+=("$package")
                    fi
                    ;;
                "intel")
                    if ubuntu_has_intel_gpu; then
                        packages+=("$package")
                    fi
                    ;;
                "wayland")
                    if ubuntu_is_wayland_session; then
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
        "apt")
            ubuntu_install_apt_packages "${packages[@]}"
            ;;
        "snap")
            ubuntu_install_snap_packages "${packages[@]}"
            ;;
        "flatpak")
            ubuntu_install_flatpak_packages "${packages[@]}"
            ;;
        *)
            log_error "Unknown package type: $package_type"
            return 1
            ;;
    esac
}

# Install base packages required for Hyprland environment
ubuntu_install_base_packages() {
    log_info "Installing base packages for Ubuntu Hyprland environment..."
    
    local base_packages=(
        # Build essentials
        "build-essential"
        "cmake"
        "meson"
        "ninja-build"
        "pkg-config"
        
        # Development tools
        "git"
        "curl"
        "wget"
        "unzip"
        "tar"
        "gzip"
        "software-properties-common"
        "apt-transport-https"
        "ca-certificates"
        "gnupg"
        "lsb-release"
        
        # Wayland and graphics libraries
        "libwayland-dev"
        "wayland-protocols"
        "libxkbcommon-dev"
        "libegl1-mesa-dev"
        "libgles2-mesa-dev"
        "libdrm-dev"
        "libxkbcommon-x11-dev"
        "libpixman-1-dev"
        "libcairo2-dev"
        "libpango1.0-dev"
        
        # Additional libraries for Hyprland
        "libwlroots-dev"
        "libinput-dev"
        "libxcb1-dev"
        "libxcb-composite0-dev"
        "libxcb-ewmh-dev"
        "libxcb-icccm4-dev"
        "libxcb-image0-dev"
        "libxcb-render-util0-dev"
        "libxcb-xfixes0-dev"
        "libxcb-xinput-dev"
        
        # Audio
        "pipewire"
        "pipewire-pulse"
        "wireplumber"
        
        # Fonts
        "fonts-noto"
        "fonts-noto-color-emoji"
        "fonts-liberation"
        
        # Utilities
        "xdg-desktop-portal-wlr"
        "xdg-utils"
        "grim"
        "slurp"
        "wl-clipboard"
    )
    
    ubuntu_install_apt_packages "${base_packages[@]}"
}

# Hardware detection helpers
ubuntu_has_nvidia_gpu() {
    lspci | grep -i nvidia >/dev/null 2>&1
}

ubuntu_has_intel_gpu() {
    lspci | grep -i "intel.*graphics\|intel.*vga" >/dev/null 2>&1
}

ubuntu_has_amd_gpu() {
    lspci | grep -i "amd\|ati" >/dev/null 2>&1
}

# Check if package is installed (APT)
ubuntu_is_apt_package_installed() {
    local package="$1"
    dpkg -l "$package" 2>/dev/null | grep -q "^ii"
}

# Check if snap package is installed
ubuntu_is_snap_package_installed() {
    local package="$1"
    snap list "$package" >/dev/null 2>&1
}

# Check if flatpak package is installed
ubuntu_is_flatpak_package_installed() {
    local package="$1"
    flatpak list | grep -q "$package"
}

# Get installed package version (APT)
ubuntu_get_apt_package_version() {
    local package="$1"
    dpkg -l "$package" 2>/dev/null | awk '/^ii/ {print $3}'
}

# Remove APT packages
ubuntu_remove_apt_packages() {
    local packages=("$@")
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        log_warn "No packages specified for removal"
        return 0
    fi
    
    log_info "Removing APT packages: ${packages[*]}"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would run: apt remove -y ${packages[*]}"
        return 0
    fi
    
    if ! sudo apt remove -y "${packages[@]}"; then
        log_error "Failed to remove some packages"
        return 1
    fi
    
    log_success "Packages removed successfully"
    return 0
}

# Remove snap packages
ubuntu_remove_snap_packages() {
    local packages=("$@")
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        log_warn "No snap packages specified for removal"
        return 0
    fi
    
    log_info "Removing snap packages: ${packages[*]}"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would run: snap remove ${packages[*]}"
        return 0
    fi
    
    for package in "${packages[@]}"; do
        if ! sudo snap remove "$package"; then
            log_warn "Failed to remove snap package: $package"
        fi
    done
    
    log_success "Snap packages removal completed"
    return 0
}

# Clean package cache
ubuntu_clean_package_cache() {
    log_info "Cleaning package cache..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would run: apt autoremove -y && apt autoclean"
        return 0
    fi
    
    # Remove unnecessary packages
    sudo apt autoremove -y
    
    # Clean package cache
    sudo apt autoclean
    
    log_success "Package cache cleaned"
    return 0
}

# Update all package managers
ubuntu_update_all_packages() {
    log_info "Updating all package managers..."
    
    # Update APT packages
    log_info "Updating APT packages..."
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
        sudo apt update && sudo apt upgrade -y
    fi
    
    # Update snap packages
    if command -v snap >/dev/null 2>&1; then
        log_info "Updating snap packages..."
        if [[ "${DRY_RUN:-false}" != "true" ]]; then
            sudo snap refresh
        fi
    fi
    
    # Update flatpak packages
    if command -v flatpak >/dev/null 2>&1; then
        log_info "Updating flatpak packages..."
        if [[ "${DRY_RUN:-false}" != "true" ]]; then
            sudo flatpak update -y
        fi
    fi
    
    log_success "All package managers updated"
    return 0
}

# Export functions for external use
export -f ubuntu_install_apt_packages
export -f ubuntu_install_snap_packages
export -f ubuntu_install_flatpak_packages
export -f ubuntu_install_from_package_list
export -f ubuntu_install_base_packages
export -f ubuntu_has_nvidia_gpu
export -f ubuntu_has_intel_gpu
export -f ubuntu_has_amd_gpu
export -f ubuntu_is_apt_package_installed
export -f ubuntu_is_snap_package_installed
export -f ubuntu_is_flatpak_package_installed
export -f ubuntu_get_apt_package_version
export -f ubuntu_remove_apt_packages
export -f ubuntu_remove_snap_packages
export -f ubuntu_clean_package_cache
export -f ubuntu_update_all_packages