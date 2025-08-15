#!/bin/bash

# Ubuntu repository management
# Handles PPA and external repository setup

# Setup Ubuntu repositories
setup_ubuntu_repositories() {
    log_info "Setting up Ubuntu repositories..."
    
    # Enable universe repository
    enable_universe_repo
    
    # Add useful PPAs
    add_common_ppas
    
    # Update package database
    sudo apt-get update
    
    log_success "Ubuntu repositories configured"
}

# Enable universe repository
enable_universe_repo() {
    log_info "Enabling universe repository..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would enable universe repository"
        return 0
    fi
    
    # Check if universe is already enabled
    if grep -q "^deb.*universe" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
        log_info "Universe repository already enabled"
        return 0
    fi
    
    # Enable universe repository
    sudo add-apt-repository universe -y
    
    log_success "Universe repository enabled"
}

# Add common useful PPAs
add_common_ppas() {
    log_info "Adding common PPAs..."
    
    # Git PPA for latest Git version
    if ask_yes_no "Add Git PPA for latest Git version?"; then
        add_ppa "git-core/ppa" "Git PPA"
    fi
    
    # Neovim PPA
    if ask_yes_no "Add Neovim unstable PPA?"; then
        add_ppa "neovim-ppa/unstable" "Neovim PPA"
    fi
    
    # Flatpak PPA
    if ask_yes_no "Add Flatpak PPA?"; then
        add_ppa "flatpak/stable" "Flatpak PPA"
    fi
}

# Add a PPA repository
add_ppa() {
    local ppa="$1"
    local description="${2:-$ppa}"
    
    log_info "Adding PPA: $description"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would add PPA: $ppa"
        return 0
    fi
    
    # Install software-properties-common if not present
    if ! command_exists add-apt-repository; then
        sudo apt-get install -y software-properties-common
    fi
    
    # Add PPA
    sudo add-apt-repository "ppa:$ppa" -y
    
    log_success "PPA added: $description"
}

# Add external repository with GPG key
add_external_repo() {
    local repo_name="$1"
    local repo_url="$2"
    local gpg_key_url="$3"
    local description="${4:-$repo_name}"
    
    log_info "Adding external repository: $description"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would add external repository: $repo_name"
        return 0
    fi
    
    # Download and add GPG key
    curl -fsSL "$gpg_key_url" | sudo gpg --dearmor -o "/usr/share/keyrings/$repo_name-keyring.gpg"
    
    # Add repository
    echo "deb [signed-by=/usr/share/keyrings/$repo_name-keyring.gpg] $repo_url" | sudo tee "/etc/apt/sources.list.d/$repo_name.list"
    
    log_success "External repository added: $description"
}

# Setup Docker repository
setup_docker_repo() {
    log_info "Setting up Docker repository..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would setup Docker repository"
        return 0
    fi
    
    # Install prerequisites
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    
    # Add Docker GPG key and repository
    local ubuntu_codename=$(lsb_release -cs)
    add_external_repo "docker" \
        "https://download.docker.com/linux/ubuntu $ubuntu_codename stable" \
        "https://download.docker.com/linux/ubuntu/gpg" \
        "Docker CE"
    
    log_success "Docker repository configured"
}

# Setup VS Code repository
setup_vscode_repo() {
    log_info "Setting up VS Code repository..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would setup VS Code repository"
        return 0
    fi
    
    # Add Microsoft GPG key and repository
    add_external_repo "vscode" \
        "https://packages.microsoft.com/repos/code stable main" \
        "https://packages.microsoft.com/keys/microsoft.asc" \
        "Visual Studio Code"
    
    log_success "VS Code repository configured"
}

# Setup Node.js repository
setup_nodejs_repo() {
    local node_version="${1:-18}"
    
    log_info "Setting up Node.js $node_version repository..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would setup Node.js repository"
        return 0
    fi
    
    # Add NodeSource repository
    curl -fsSL "https://deb.nodesource.com/setup_${node_version}.x" | sudo -E bash -
    
    log_success "Node.js $node_version repository configured"
}

# Remove PPA
remove_ppa() {
    local ppa="$1"
    local description="${2:-$ppa}"
    
    log_info "Removing PPA: $description"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would remove PPA: $ppa"
        return 0
    fi
    
    sudo add-apt-repository --remove "ppa:$ppa" -y
    
    log_success "PPA removed: $description"
}

# Clean up package cache
cleanup_package_cache() {
    log_info "Cleaning up package cache..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would clean package cache"
        return 0
    fi
    
    sudo apt-get autoremove -y
    sudo apt-get autoclean
    
    log_success "Package cache cleaned"
}