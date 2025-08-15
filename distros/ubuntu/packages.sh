#!/bin/bash

# Ubuntu package management
# Handles APT, snap, and flatpak package installation

# Install packages using APT
install_apt_packages() {
    local packages=("$@")
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        log_debug "No APT packages to install"
        return 0
    fi
    
    log_info "Installing APT packages: ${packages[*]}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install APT packages: ${packages[*]}"
        return 0
    fi
    
    sudo apt-get install -y "${packages[@]}"
}

# Install snap packages
install_snap_packages() {
    local packages=("$@")
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        log_debug "No snap packages to install"
        return 0
    fi
    
    # Ensure snapd is installed
    ensure_snapd
    
    log_info "Installing snap packages: ${packages[*]}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install snap packages: ${packages[*]}"
        return 0
    fi
    
    for package in "${packages[@]}"; do
        sudo snap install "$package"
    done
}

# Install flatpak packages
install_flatpak_packages() {
    local packages=("$@")
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        log_debug "No flatpak packages to install"
        return 0
    fi
    
    # Ensure flatpak is installed
    ensure_flatpak
    
    log_info "Installing flatpak packages: ${packages[*]}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install flatpak packages: ${packages[*]}"
        return 0
    fi
    
    for package in "${packages[@]}"; do
        flatpak install -y flathub "$package"
    done
}

# Ensure snapd is installed and configured
ensure_snapd() {
    if command_exists snap; then
        return 0
    fi
    
    log_info "Installing snapd..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install snapd"
        return 0
    fi
    
    sudo apt-get install -y snapd
    
    # Add snap bin directory to PATH if not already there
    if [[ ":$PATH:" != *":/snap/bin:"* ]]; then
        echo 'export PATH="$PATH:/snap/bin"' >> "$HOME/.bashrc"
        echo 'export PATH="$PATH:/snap/bin"' >> "$HOME/.zshrc" 2>/dev/null || true
    fi
    
    log_success "Snapd installed successfully"
}

# Ensure flatpak is installed and configured
ensure_flatpak() {
    if command_exists flatpak; then
        return 0
    fi
    
    log_info "Installing flatpak..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install flatpak"
        return 0
    fi
    
    sudo apt-get install -y flatpak
    
    # Add flathub repository
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    
    log_success "Flatpak installed successfully"
}

# Read Ubuntu package list from file
read_ubuntu_package_list() {
    local file="$1"
    local packages=()
    
    if [[ ! -f "$file" ]]; then
        log_warn "Package list file not found: $file"
        return 1
    fi
    
    while IFS= read -r line; do
        # Skip empty lines and comments
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # Handle package source specification (apt:package, snap:package, flatpak:package)
        if [[ "$line" =~ : ]]; then
            local source="${line%:*}"
            local package="${line#*:}"
            
            case "$source" in
                "apt")
                    packages+=("apt:$package")
                    ;;
                "snap")
                    packages+=("snap:$package")
                    ;;
                "flatpak")
                    packages+=("flatpak:$package")
                    ;;
                *)
                    # Default to apt if no source specified
                    packages+=("apt:$line")
                    ;;
            esac
        else
            # Default to apt
            packages+=("apt:$line")
        fi
    done < "$file"
    
    echo "${packages[@]}"
}

# Install packages from categorized list
install_ubuntu_package_category() {
    local category="$1"
    
    log_info "Installing $category packages for Ubuntu..."
    
    case "$category" in
        "base")
            local apt_packages=(curl wget git vim nano build-essential)
            install_apt_packages "${apt_packages[@]}"
            ;;
        "development")
            local apt_packages=(gcc make cmake nodejs npm python3 python3-pip)
            install_apt_packages "${apt_packages[@]}"
            ;;
        "multimedia")
            local apt_packages=(ffmpeg vlc gimp)
            local snap_packages=(discord)
            install_apt_packages "${apt_packages[@]}"
            install_snap_packages "${snap_packages[@]}"
            ;;
        *)
            log_warn "Unknown package category: $category"
            ;;
    esac
}

# Update package databases
update_ubuntu_packages() {
    log_info "Updating package databases..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would update package databases"
        return 0
    fi
    
    # Update APT
    sudo apt-get update
    
    # Update snap if available
    if command_exists snap; then
        sudo snap refresh
    fi
    
    # Update flatpak if available
    if command_exists flatpak; then
        flatpak update -y
    fi
    
    log_success "Package databases updated"
}