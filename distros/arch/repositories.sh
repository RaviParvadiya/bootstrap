#!/bin/bash

# Arch Linux repository management
# Handles multilib, chaotic-aur, and other repository setup

# Setup Arch Linux repositories
setup_arch_repositories() {
    log_info "Setting up Arch Linux repositories..."
    
    # Enable multilib repository
    enable_multilib_repo
    
    # Setup chaotic-aur repository
    if ask_yes_no "Enable Chaotic-AUR repository for additional packages?"; then
        setup_chaotic_aur
    fi
    
    # Update package database
    update_package_database
}

# Enable multilib repository
enable_multilib_repo() {
    log_info "Enabling multilib repository..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would enable multilib repository"
        return 0
    fi
    
    # Check if multilib is already enabled
    if grep -q "^\[multilib\]" /etc/pacman.conf; then
        log_info "Multilib repository already enabled"
        return 0
    fi
    
    # Enable multilib repository
    sudo sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' /etc/pacman.conf
    
    log_success "Multilib repository enabled"
}

# Setup Chaotic-AUR repository
setup_chaotic_aur() {
    log_info "Setting up Chaotic-AUR repository..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would setup Chaotic-AUR repository"
        return 0
    fi
    
    # Check if chaotic-aur is already configured
    if grep -q "\[chaotic-aur\]" /etc/pacman.conf; then
        log_info "Chaotic-AUR repository already configured"
        return 0
    fi
    
    # Install chaotic-aur keyring and mirrorlist
    sudo pacman-key --recv-key FBA220DFC880C036 --keyserver keyserver.ubuntu.com
    sudo pacman-key --lsign-key FBA220DFC880C036
    sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.xz' 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.xz'
    
    # Add chaotic-aur repository to pacman.conf
    echo "" | sudo tee -a /etc/pacman.conf
    echo "[chaotic-aur]" | sudo tee -a /etc/pacman.conf
    echo "Include = /etc/pacman.d/chaotic-mirrorlist" | sudo tee -a /etc/pacman.conf
    
    log_success "Chaotic-AUR repository configured"
}

# Update package database
update_package_database() {
    log_info "Updating package database..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would update package database"
        return 0
    fi
    
    sudo pacman -Sy
    
    log_success "Package database updated"
}

# Add custom repository
add_custom_repository() {
    local repo_name="$1"
    local repo_url="$2"
    local keyid="${3:-}"
    
    log_info "Adding custom repository: $repo_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would add custom repository: $repo_name"
        return 0
    fi
    
    # Add GPG key if provided
    if [[ -n "$keyid" ]]; then
        sudo pacman-key --recv-key "$keyid" --keyserver keyserver.ubuntu.com
        sudo pacman-key --lsign-key "$keyid"
    fi
    
    # Add repository to pacman.conf
    echo "" | sudo tee -a /etc/pacman.conf
    echo "[$repo_name]" | sudo tee -a /etc/pacman.conf
    echo "Server = $repo_url" | sudo tee -a /etc/pacman.conf
    
    log_success "Custom repository $repo_name added"
}

# Configure pacman settings
configure_pacman() {
    log_info "Configuring pacman settings..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would configure pacman settings"
        return 0
    fi
    
    # Enable parallel downloads
    sudo sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf
    
    # Enable color output
    sudo sed -i 's/^#Color/Color/' /etc/pacman.conf
    
    # Enable verbose package lists
    sudo sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf
    
    log_success "Pacman configuration updated"
}