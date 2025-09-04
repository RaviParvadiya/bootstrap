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
    
    # Enable multilib repository
    if ! arch_enable_multilib; then
        log_warn "Failed to enable multilib repository"
    fi
    
    # Setup chaotic-aur repository
    if ! arch_setup_chaotic_aur; then
        log_warn "Failed to setup chaotic-aur repository"
    fi
    
    # Update package database after repository changes
    arch_update_package_database
    
    log_success "Repository setup completed"
    return 0
}

# Enable multilib repository
arch_enable_multilib() {
    log_info "Enabling multilib repository..."
    
    local pacman_conf="/etc/pacman.conf"
    
    # Check if multilib is already enabled
    if grep -q "^\[multilib\]" "$pacman_conf"; then
        log_info "Multilib repository already enabled"
        return 0
    fi
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would enable multilib repository in $pacman_conf"
        return 0
    fi
    
    # Create backup of pacman.conf
    if ! sudo cp "$pacman_conf" "$pacman_conf.backup.$(date +%Y%m%d_%H%M%S)"; then
        log_error "Failed to backup pacman.conf"
        return 1
    fi
    
    # Enable multilib repository by uncommenting the section
    if sudo sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' "$pacman_conf"; then
        log_success "Multilib repository enabled"
        return 0
    else
        log_error "Failed to enable multilib repository"
        return 1
    fi
}

# Setup chaotic-aur repository
arch_setup_chaotic_aur() {
    log_info "Setting up chaotic-aur repository..."
    
    local pacman_conf="/etc/pacman.conf"
    
    # Check if chaotic-aur is already configured
    if grep -q "\[chaotic-aur\]" "$pacman_conf"; then
        log_info "Chaotic-aur repository already configured"
        return 0
    fi
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would setup chaotic-aur repository"
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
    
    # Install chaotic keyring and mirrorlist packages
    if ! sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'; then
        log_error "Failed to install chaotic-keyring"
        return 1
    fi
    
    if ! sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'; then
        log_error "Failed to install chaotic-mirrorlist"
        return 1
    fi
    
    # Add chaotic-aur repository to pacman.conf
    log_info "Adding chaotic-aur repository to pacman.conf..."
    
    # Create backup
    sudo cp "$pacman_conf" "$pacman_conf.backup.chaotic.$(date +%Y%m%d_%H%M%S)"
    
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
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would run: pacman -Sy"
        return 0
    fi
    
    if ! sudo pacman -Sy; then
        log_error "Failed to update package database"
        return 1
    fi
    
    log_success "Package database updated"
    return 0
}

# Add custom repository
arch_add_custom_repository() {
    local repo_name="$1"
    local repo_url="$2"
    local repo_key="$3"  # Optional GPG key
    
    if [[ -z "$repo_name" || -z "$repo_url" ]]; then
        log_error "Repository name and URL are required"
        return 1
    fi
    
    log_info "Adding custom repository: $repo_name"
    
    local pacman_conf="/etc/pacman.conf"
    
    # Check if repository already exists
    if grep -q "\[$repo_name\]" "$pacman_conf"; then
        log_info "Repository $repo_name already exists"
        return 0
    fi
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would add repository: $repo_name -> $repo_url"
        return 0
    fi
    
    # Add GPG key if provided
    if [[ -n "$repo_key" ]]; then
        log_info "Adding GPG key for repository..."
        if ! sudo pacman-key --recv-keys "$repo_key"; then
            log_warn "Failed to receive GPG key: $repo_key"
        elif ! sudo pacman-key --lsign-key "$repo_key"; then
            log_warn "Failed to sign GPG key: $repo_key"
        fi
    fi
    
    # Create backup
    sudo cp "$pacman_conf" "$pacman_conf.backup.custom.$(date +%Y%m%d_%H%M%S)"
    
    # Add repository configuration
    cat << EOF | sudo tee -a "$pacman_conf" >/dev/null

# Custom repository: $repo_name
[$repo_name]
Server = $repo_url
EOF
    
    log_success "Custom repository $repo_name added"
    
    # Update package database
    arch_update_package_database
    
    return 0
}

# Remove repository
arch_remove_repository() {
    local repo_name="$1"
    
    if [[ -z "$repo_name" ]]; then
        log_error "Repository name is required"
        return 1
    fi
    
    log_info "Removing repository: $repo_name"
    
    local pacman_conf="/etc/pacman.conf"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would remove repository: $repo_name"
        return 0
    fi
    
    # Create backup
    sudo cp "$pacman_conf" "$pacman_conf.backup.remove.$(date +%Y%m%d_%H%M%S)"
    
    # Remove repository section
    if sudo sed -i "/^\[$repo_name\]/,/^$/d" "$pacman_conf"; then
        log_success "Repository $repo_name removed"
        arch_update_package_database
        return 0
    else
        log_error "Failed to remove repository: $repo_name"
        return 1
    fi
}

# List configured repositories
arch_list_repositories() {
    log_info "Configured repositories:"
    
    # Extract repository names from pacman.conf
    grep "^\[" /etc/pacman.conf | sed 's/\[//g; s/\]//g' | while read -r repo; do
        if [[ "$repo" != "options" ]]; then
            log_info "  - $repo"
        fi
    done
}

# Check repository status
arch_check_repository_status() {
    local repo_name="$1"
    
    if [[ -z "$repo_name" ]]; then
        log_error "Repository name is required"
        return 1
    fi
    
    if grep -q "^\[$repo_name\]" /etc/pacman.conf; then
        log_info "Repository $repo_name is configured"
        return 0
    else
        log_info "Repository $repo_name is not configured"
        return 1
    fi
}

# Restore pacman.conf from backup
arch_restore_pacman_conf() {
    local backup_file="$1"
    
    if [[ -z "$backup_file" ]]; then
        # Find the most recent backup
        backup_file=$(ls -t /etc/pacman.conf.backup.* 2>/dev/null | head -n1)
    fi
    
    if [[ -z "$backup_file" || ! -f "$backup_file" ]]; then
        log_error "No backup file found or specified"
        return 1
    fi
    
    log_info "Restoring pacman.conf from: $backup_file"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would restore pacman.conf from $backup_file"
        return 0
    fi
    
    if sudo cp "$backup_file" /etc/pacman.conf; then
        log_success "pacman.conf restored from backup"
        arch_update_package_database
        return 0
    else
        log_error "Failed to restore pacman.conf"
        return 1
    fi
}

# Export functions for external use
export -f arch_setup_repositories
export -f arch_enable_multilib
export -f arch_setup_chaotic_aur
export -f arch_update_package_database
export -f arch_add_custom_repository
export -f arch_remove_repository
export -f arch_list_repositories
export -f arch_check_repository_status
export -f arch_restore_pacman_conf