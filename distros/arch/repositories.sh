#!/usr/bin/env bash

# Arch Linux Repository Management
# Handles multilib and chaotic-aur repository setup

# Initialize all project paths
source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"

# Source core utilities
source "$CORE_DIR/common.sh"
source "$CORE_DIR/logger.sh"

# Setup all Arch Linux repositories
arch_setup_repositories() {
    log_info "Setting up Arch Linux repositories..."
    
    arch_enable_multilib || log_warn "Failed to enable multilib repository"
    arch_setup_chaotic_aur || log_warn "Failed to setup chaotic-aur repository"
    arch_update_package_database
    
    log_success "Repository setup completed"
}

# Enable multilib repository
arch_enable_multilib() {
    log_info "Enabling multilib repository..."
    
    local pacman_conf="/etc/pacman.conf"
    
    if grep -q "^\[multilib\]" "$pacman_conf"; then
        log_info "Multilib repository already enabled"
        return 0
    fi
    
    if sudo sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' "$pacman_conf"; then
        log_success "Multilib repository enabled"
    else
        log_error "Failed to enable multilib repository"
        return 1
    fi
}

# Setup chaotic-aur repository
arch_setup_chaotic_aur() {
    # DISABLED: Chaotic-AUR setup is temporarily disabled
    # Remove this return statement to re-enable chaotic-aur setup
    log_info "Chaotic-AUR setup is currently disabled"
    log_info "To enable: edit distros/arch/repositories.sh and remove the early return"
    return 0
    
    log_info "Setting up chaotic-aur repository..."
    
    local pacman_conf="/etc/pacman.conf"
    
    # Check if chaotic-aur is already configured
    if grep -q "\[chaotic-aur\]" "$pacman_conf"; then
        log_info "Chaotic-aur repository already configured"
        return 0
    fi
    
    # Install chaotic-aur keyring using the official method
    log_info "Installing chaotic-aur keyring and mirrorlist..."
    
    # Receive and sign the chaotic-aur key
    if ! sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com; then
        log_error "Failed to receive chaotic-aur key"
        return 1
    fi
    
    if ! sudo pacman-key --lsign-key 3056513887B78AEB; then
        log_error "Failed to sign chaotic-aur key"
        return 1
    fi
    
    # Install chaotic keyring and mirrorlist packages - try each separately for better error handling
    local keyring_installed=false
    local mirrorlist_installed=false
    
    # Try to install keyring first
    if sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'; then
        keyring_installed=true
        log_success "Chaotic keyring installed successfully"
    else
        log_warn "Failed to install chaotic-keyring from primary mirror"
    fi
    
    # Try to install mirrorlist
    if sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'; then
        mirrorlist_installed=true
        log_success "Chaotic mirrorlist installed successfully"
    else
        log_warn "Failed to install chaotic-mirrorlist from primary mirror"
    fi
    
    # If either failed, skip chaotic-aur setup but don't fail the entire installation
    if [[ "$keyring_installed" == "false" || "$mirrorlist_installed" == "false" ]]; then
        log_warn "Chaotic-aur packages could not be installed - repository will be skipped"
        log_info "This is not critical - you can install chaotic-aur manually later if needed"
        log_info "Run: sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'"
        return 1
    fi
    
    # Add chaotic-aur repository to pacman.conf
    log_info "Adding chaotic-aur repository to pacman.conf..."
    
    # Add chaotic-aur repository configuration
    echo -e '\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist' | sudo tee -a "$pacman_conf" >/dev/null
    
    # Update package database
    if ! sudo pacman -Sy; then
        log_error "Failed to update package database after adding chaotic-aur"
        return 1
    fi
    
    log_success "Chaotic-aur repository configured successfully"
    return 0
}

# Update package database
arch_update_package_database() {
    log_info "Updating package database..."
    
    if sudo pacman -Sy; then
        log_success "Package database updated"
    else
        log_error "Failed to update package database"
        return 1
    fi
}

# Add custom repository (optional function - remove if not frequently used)
arch_add_custom_repository() {
    local repo_name="$1" repo_url="$2" repo_key="$3"
    local pacman_conf="/etc/pacman.conf"
    
    [[ -z "$repo_name" || -z "$repo_url" ]] && { log_error "Repository name and URL are required"; return 1; }
    
    log_info "Adding custom repository: $repo_name"
    
    if grep -q "\[$repo_name\]" "$pacman_conf"; then
        log_info "Repository $repo_name already exists"
        return 0
    fi
    
    # Add GPG key if provided
    if [[ -n "$repo_key" ]]; then
        sudo pacman-key --recv-keys "$repo_key" && sudo pacman-key --lsign-key "$repo_key" || log_warn "GPG key setup failed"
    fi
    
    cat << EOF | sudo tee -a "$pacman_conf" >/dev/null

# Custom repository: $repo_name
[$repo_name]
Server = $repo_url
EOF
    
    log_success "Custom repository $repo_name added"
    arch_update_package_database
}

# List configured repositories
arch_list_repositories() {
    log_info "Configured repositories:"
    grep "^\[" /etc/pacman.conf | sed 's/[][]//g' | grep -v "^options$" | sed 's/^/  - /'
}

# Check repository status
arch_check_repository_status() {
    local repo_name="$1"
    [[ -z "$repo_name" ]] && { log_error "Repository name is required"; return 1; }
    
    if grep -q "^\[$repo_name\]" /etc/pacman.conf; then
        log_info "Repository $repo_name is configured"
    else
        log_info "Repository $repo_name is not configured"
        return 1
    fi
}

# Export essential functions
export -f arch_setup_repositories arch_enable_multilib arch_update_package_database