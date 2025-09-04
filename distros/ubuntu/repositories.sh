#!/usr/bin/env bash

# Ubuntu Repository Management
# Handles PPA and external repository setup

# Initialize all project paths
source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"

# Source core utilities
source "$CORE_DIR/common.sh"
source "$CORE_DIR/logger.sh"

# Setup all Ubuntu repositories
ubuntu_setup_repositories() {
    log_info "Setting up Ubuntu repositories..."
    
    # Enable universe repository
    if ! ubuntu_enable_universe; then
        log_warn "Failed to enable universe repository"
    fi
    
    # Enable multiverse repository
    if ! ubuntu_enable_multiverse; then
        log_warn "Failed to enable multiverse repository"
    fi
    
    # Setup common PPAs for development
    ubuntu_setup_development_ppas
    
    # Setup Hyprland-specific PPAs
    ubuntu_setup_hyprland_ppas
    
    # Setup flatpak if not already done
    ubuntu_setup_flatpak
    
    # Update package database after repository changes
    ubuntu_update_package_database
    
    log_success "Repository setup completed"
    return 0
}

# Enable universe repository
ubuntu_enable_universe() {
    log_info "Enabling universe repository..."
    
    # Check if universe is already enabled
    if ubuntu_is_universe_enabled; then
        log_info "Universe repository already enabled"
        return 0
    fi
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would enable universe repository"
        return 0
    fi
    
    # Enable universe repository
    if sudo add-apt-repository universe -y; then
        log_success "Universe repository enabled"
        return 0
    else
        log_error "Failed to enable universe repository"
        return 1
    fi
}

# Enable multiverse repository
ubuntu_enable_multiverse() {
    log_info "Enabling multiverse repository..."
    
    # Check if multiverse is already enabled
    if grep -q "^deb.*multiverse" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
        log_info "Multiverse repository already enabled"
        return 0
    fi
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would enable multiverse repository"
        return 0
    fi
    
    # Enable multiverse repository
    if sudo add-apt-repository multiverse -y; then
        log_success "Multiverse repository enabled"
        return 0
    else
        log_error "Failed to enable multiverse repository"
        return 1
    fi
}

# Setup development PPAs
ubuntu_setup_development_ppas() {
    log_info "Setting up development PPAs..."
    
    local ppas=(
        # Git (latest version)
        "ppa:git-core/ppa"
        
        # Neovim (stable)
        "ppa:neovim-ppa/stable"
        
        # Fish shell
        "ppa:fish-shell/release-3"
        
        # Kitty terminal
        "ppa:aslatter/ppa"
        
        # Graphics drivers
        "ppa:graphics-drivers/ppa"
        
        # OBS Studio
        "ppa:obsproject/obs-studio"
    )
    
    for ppa in "${ppas[@]}"; do
        ubuntu_add_ppa "$ppa"
    done
}

# Setup Hyprland-specific repositories
ubuntu_setup_hyprland_ppas() {
    log_info "Setting up Hyprland-related PPAs..."
    
    local ppas=(
        # Waybar
        "ppa:alexmurray/waybar"
        
        # Wayland utilities
        "ppa:wayland-team/wayland"
    )
    
    for ppa in "${ppas[@]}"; do
        ubuntu_add_ppa "$ppa"
    done
}

# Add PPA repository
ubuntu_add_ppa() {
    local ppa="$1"
    
    if [[ -z "$ppa" ]]; then
        log_error "PPA name is required"
        return 1
    fi
    
    log_info "Adding PPA: $ppa"
    
    # Check if PPA is already added
    local ppa_name="${ppa#ppa:}"
    if grep -q "$ppa_name" /etc/apt/sources.list.d/*.list 2>/dev/null; then
        log_info "PPA $ppa already added"
        return 0
    fi
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would add PPA: $ppa"
        return 0
    fi
    
    # Add PPA
    if sudo add-apt-repository "$ppa" -y; then
        log_success "PPA $ppa added successfully"
        return 0
    else
        log_warn "Failed to add PPA: $ppa"
        return 1
    fi
}

# Remove PPA repository
ubuntu_remove_ppa() {
    local ppa="$1"
    
    if [[ -z "$ppa" ]]; then
        log_error "PPA name is required"
        return 1
    fi
    
    log_info "Removing PPA: $ppa"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would remove PPA: $ppa"
        return 0
    fi
    
    # Remove PPA
    if sudo add-apt-repository --remove "$ppa" -y; then
        log_success "PPA $ppa removed successfully"
        return 0
    else
        log_error "Failed to remove PPA: $ppa"
        return 1
    fi
}

# Add external APT repository
ubuntu_add_external_repository() {
    local repo_name="$1"
    local repo_url="$2"
    local repo_key_url="$3"
    local repo_components="${4:-main}"
    
    if [[ -z "$repo_name" || -z "$repo_url" ]]; then
        log_error "Repository name and URL are required"
        return 1
    fi
    
    log_info "Adding external repository: $repo_name"
    
    local sources_file="/etc/apt/sources.list.d/${repo_name}.list"
    
    # Check if repository already exists
    if [[ -f "$sources_file" ]]; then
        log_info "Repository $repo_name already exists"
        return 0
    fi
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would add repository: $repo_name -> $repo_url"
        return 0
    fi
    
    # Add GPG key if provided
    if [[ -n "$repo_key_url" ]]; then
        log_info "Adding GPG key for repository..."
        local keyring_file="/usr/share/keyrings/${repo_name}-keyring.gpg"
        
        if ! curl -fsSL "$repo_key_url" | sudo gpg --dearmor -o "$keyring_file"; then
            log_error "Failed to add GPG key for repository: $repo_name"
            return 1
        fi
        
        # Create sources list entry with signed-by
        local ubuntu_codename
        ubuntu_codename=$(ubuntu_get_codename)
        echo "deb [arch=$(dpkg --print-architecture) signed-by=$keyring_file] $repo_url $ubuntu_codename $repo_components" | \
            sudo tee "$sources_file" >/dev/null
    else
        # Create sources list entry without GPG key
        local ubuntu_codename
        ubuntu_codename=$(ubuntu_get_codename)
        echo "deb $repo_url $ubuntu_codename $repo_components" | \
            sudo tee "$sources_file" >/dev/null
    fi
    
    log_success "External repository $repo_name added"
    return 0
}

# Setup Docker repository
ubuntu_setup_docker_repository() {
    log_info "Setting up Docker repository..."
    
    ubuntu_add_external_repository \
        "docker" \
        "https://download.docker.com/linux/ubuntu" \
        "https://download.docker.com/linux/ubuntu/gpg" \
        "stable"
}

# Setup Google Chrome repository
ubuntu_setup_chrome_repository() {
    log_info "Setting up Google Chrome repository..."
    
    ubuntu_add_external_repository \
        "google-chrome" \
        "https://dl.google.com/linux/chrome/deb/" \
        "https://dl.google.com/linux/linux_signing_key.pub" \
        "stable"
}

# Setup VS Code repository
ubuntu_setup_vscode_repository() {
    log_info "Setting up VS Code repository..."
    
    ubuntu_add_external_repository \
        "vscode" \
        "https://packages.microsoft.com/repos/code" \
        "https://packages.microsoft.com/keys/microsoft.asc" \
        "stable"
}

# Setup Node.js repository (NodeSource)
ubuntu_setup_nodejs_repository() {
    local node_version="${1:-18}"  # Default to Node.js 18
    
    log_info "Setting up Node.js $node_version repository..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would setup Node.js $node_version repository"
        return 0
    fi
    
    # Download and run NodeSource setup script
    curl -fsSL "https://deb.nodesource.com/setup_${node_version}.x" | sudo -E bash -
    
    log_success "Node.js $node_version repository configured"
}

# Setup flatpak
ubuntu_setup_flatpak() {
    log_info "Setting up Flatpak..."
    
    # Check if flatpak is already installed
    if command -v flatpak >/dev/null 2>&1; then
        log_info "Flatpak already installed"
    else
        log_info "Installing Flatpak..."
        if [[ "${DRY_RUN:-false}" != "true" ]]; then
            sudo apt install -y flatpak
        fi
    fi
    
    # Add Flathub repository
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would add Flathub repository"
        return 0
    fi
    
    if ! flatpak remote-list | grep -q "flathub"; then
        log_info "Adding Flathub repository..."
        sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
        log_success "Flathub repository added"
    else
        log_info "Flathub repository already configured"
    fi
}

# Update package database
ubuntu_update_package_database() {
    log_info "Updating package database..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would run: apt update"
        return 0
    fi
    
    if ! sudo apt update; then
        log_error "Failed to update package database"
        return 1
    fi
    
    log_success "Package database updated"
    return 0
}

# List configured PPAs
ubuntu_list_ppas() {
    log_info "Configured PPAs:"
    
    if [[ -d "/etc/apt/sources.list.d" ]]; then
        find /etc/apt/sources.list.d -name "*.list" -exec grep -l "ppa.launchpad.net" {} \; | \
        while read -r file; do
            local ppa_info
            ppa_info=$(grep "ppa.launchpad.net" "$file" | head -n1 | awk '{print $2}' | sed 's|http://ppa.launchpad.net/||; s|/ubuntu||')
            if [[ -n "$ppa_info" ]]; then
                log_info "  - ppa:$ppa_info"
            fi
        done
    fi
}

# List external repositories
ubuntu_list_external_repositories() {
    log_info "External repositories:"
    
    if [[ -d "/etc/apt/sources.list.d" ]]; then
        find /etc/apt/sources.list.d -name "*.list" -exec grep -v "ppa.launchpad.net" {} \; | \
        grep "^deb " | \
        while read -r line; do
            local repo_url
            repo_url=$(echo "$line" | awk '{print $2}')
            log_info "  - $repo_url"
        done
    fi
}

# Remove external repository
ubuntu_remove_external_repository() {
    local repo_name="$1"
    
    if [[ -z "$repo_name" ]]; then
        log_error "Repository name is required"
        return 1
    fi
    
    log_info "Removing external repository: $repo_name"
    
    local sources_file="/etc/apt/sources.list.d/${repo_name}.list"
    local keyring_file="/usr/share/keyrings/${repo_name}-keyring.gpg"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would remove repository: $repo_name"
        return 0
    fi
    
    # Remove sources list file
    if [[ -f "$sources_file" ]]; then
        sudo rm "$sources_file"
        log_info "Removed sources file: $sources_file"
    fi
    
    # Remove keyring file
    if [[ -f "$keyring_file" ]]; then
        sudo rm "$keyring_file"
        log_info "Removed keyring file: $keyring_file"
    fi
    
    log_success "External repository $repo_name removed"
    
    # Update package database
    ubuntu_update_package_database
    
    return 0
}

# Check if repository is configured
ubuntu_is_repository_configured() {
    local repo_identifier="$1"
    
    if [[ -z "$repo_identifier" ]]; then
        log_error "Repository identifier is required"
        return 1
    fi
    
    # Check in sources.list and sources.list.d
    if grep -r "$repo_identifier" /etc/apt/sources.list /etc/apt/sources.list.d/ >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Export functions for external use
export -f ubuntu_setup_repositories
export -f ubuntu_enable_universe
export -f ubuntu_enable_multiverse
export -f ubuntu_setup_development_ppas
export -f ubuntu_setup_hyprland_ppas
export -f ubuntu_add_ppa
export -f ubuntu_remove_ppa
export -f ubuntu_add_external_repository
export -f ubuntu_setup_docker_repository
export -f ubuntu_setup_chrome_repository
export -f ubuntu_setup_vscode_repository
export -f ubuntu_setup_nodejs_repository
export -f ubuntu_setup_flatpak
export -f ubuntu_update_package_database
export -f ubuntu_list_ppas
export -f ubuntu_list_external_repositories
export -f ubuntu_remove_external_repository
export -f ubuntu_is_repository_configured