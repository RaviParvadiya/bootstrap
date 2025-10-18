#!/usr/bin/env bash

# Ubuntu package management with APT support

source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"
source "$CORE_DIR/common.sh"
source "$CORE_DIR/logger.sh"

ubuntu_install_apt_packages() {
    local packages=("$@")
    
    [[ ${#packages[@]} -eq 0 ]] && { log_warn "No APT packages specified"; return 0; }
    
    log_info "Installing APT packages: ${packages[*]}"
    
    sudo apt update
    
    if ! sudo apt install -y "${packages[@]}"; then
        log_error "Failed to install APT packages"
        return 1
    fi
    
    log_success "APT packages installed"
}



# Install packages from package list file
ubuntu_install_from_package_list() {
    local package_list_file="$1"
    local package_type="${2:-auto}"  # apt or auto
    
    if [[ ! -f "$package_list_file" ]]; then
        log_error "Package list file not found: $package_list_file"
        return 1
    fi
    
    log_info "Installing packages from: $package_list_file"
    
    # Separate packages by type
    local apt_packages=()
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        # Handle conditional packages (package|condition)
        local package_entry="$line"
        local condition=""
        if [[ "$line" =~ \| ]]; then
            package_entry="${line%%|*}"
            condition="${line##*|}"
            
            # Evaluate condition
            local include_package=false
            case "$condition" in
                "nvidia")
                    ubuntu_has_nvidia_gpu && include_package=true
                    ;;
                "intel")
                    ubuntu_has_intel_gpu && include_package=true
                    ;;
                "amd")
                    ubuntu_has_amd_gpu && include_package=true
                    ;;
                "wayland")
                    ubuntu_is_wayland_session && include_package=true
                    ;;
                "x11")
                    ubuntu_is_x11_session && include_package=true
                    ;;
                "gaming"|"laptop"|"vm")
                    # These conditions can be set as environment variables
                    [[ "${!condition^^}" == "TRUE" || "${!condition^^}" == "1" ]] && include_package=true
                    ;;
                *)
                    # Default: include package
                    include_package=true
                    ;;
            esac
            
            if [[ "$include_package" != "true" ]]; then
                continue
            fi
        fi
        
        # All packages are APT packages (no prefixes supported)
        apt_packages+=("$package_entry")
    done < "$package_list_file"
    
    # Install packages by type
    local install_success=true
    
    if [[ ${#apt_packages[@]} -gt 0 ]]; then
        log_info "Installing ${#apt_packages[@]} APT packages..."
        if ! ubuntu_install_apt_packages "${apt_packages[@]}"; then
            install_success=false
        fi
    fi
    

    
    if [[ "$install_success" == "true" ]]; then
        log_success "Package installation from $package_list_file completed successfully"
        return 0
    else
        log_warn "Some packages from $package_list_file failed to install"
        return 1
    fi
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

# Install packages from Ubuntu package list
ubuntu_install_packages_from_list() {
    local package_list_file="${1:-$(dirname "${BASH_SOURCE[0]}")/../../data/ubuntu-packages.lst}"
    
    if [[ ! -f "$package_list_file" ]]; then
        log_error "Ubuntu package list not found: $package_list_file"
        return 1
    fi
    
    log_info "Installing packages from Ubuntu package list..."
    ubuntu_install_from_package_list "$package_list_file" "auto"
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

# Export functions for external use
export -f ubuntu_install_apt_packages

export -f ubuntu_install_from_package_list
export -f ubuntu_install_base_packages
export -f ubuntu_install_packages_from_list
export -f ubuntu_has_nvidia_gpu
export -f ubuntu_has_intel_gpu
export -f ubuntu_has_amd_gpu