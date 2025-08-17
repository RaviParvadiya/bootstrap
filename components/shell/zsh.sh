#!/bin/bash

# components/shell/zsh.sh - Zsh shell installation and configuration
# This module handles the installation and configuration of Zsh shell with
# plugin management via Zinit, proper dotfiles integration, and cross-distribution support.

# Source required modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Source core modules if not already loaded
if [[ -z "${LOGGER_SOURCED:-}" ]]; then
    source "$PROJECT_ROOT/core/logger.sh"
fi
if ! declare -f detect_distro >/dev/null 2>&1; then
    source "$PROJECT_ROOT/core/common.sh"
fi

# Component metadata
readonly ZSH_COMPONENT_NAME="zsh"
readonly ZSH_CONFIG_SOURCE="$PROJECT_ROOT/dotfiles/zshrc/.zshrc"
readonly ZSH_CONFIG_TARGET="$HOME/.zshrc"
readonly ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

# Package definitions per distribution
declare -A ZSH_PACKAGES=(
    ["arch"]="zsh zsh-completions"
    ["ubuntu"]="zsh"
)

# Additional tools that enhance Zsh experience
declare -A ZSH_OPTIONAL_PACKAGES=(
    ["arch"]="fzf exa zoxide"
    ["ubuntu"]="fzf exa zoxide"
)

#######################################
# Zsh Installation Functions
#######################################

# Check if Zsh is already installed
# Returns: 0 if installed, 1 if not installed
# Requirements: 7.1 - Component installation detection
is_zsh_installed() {
    if command -v zsh >/dev/null 2>&1; then
        return 0
    fi
    
    # Also check if package is installed via package manager
    local distro
    distro=$(get_distro)
    
    case "$distro" in
        "arch")
            pacman -Qi zsh >/dev/null 2>&1
            ;;
        "ubuntu")
            dpkg -l zsh >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

# Check if Zsh is the current user's default shell
# Returns: 0 if default, 1 if not default
is_zsh_default_shell() {
    [[ "$SHELL" == *"zsh"* ]]
}

# Install Zsh packages
# Returns: 0 if successful, 1 if failed
# Requirements: 7.1 - Package installation with distribution detection
install_zsh_packages() {
    local distro
    distro=$(get_distro)
    
    if [[ -z "${ZSH_PACKAGES[$distro]}" ]]; then
        log_error "Zsh packages not defined for distribution: $distro"
        return 1
    fi
    
    log_info "Installing Zsh packages for $distro..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install packages: ${ZSH_PACKAGES[$distro]}"
        log_info "[DRY-RUN] Would install optional packages: ${ZSH_OPTIONAL_PACKAGES[$distro]:-none}"
        return 0
    fi
    
    # Install main Zsh packages
    local packages
    read -ra packages <<< "${ZSH_PACKAGES[$distro]}"
    
    for package in "${packages[@]}"; do
        if ! install_package "$package"; then
            log_error "Failed to install Zsh package: $package"
            return 1
        fi
    done
    
    # Install optional packages for enhanced experience
    if [[ -n "${ZSH_OPTIONAL_PACKAGES[$distro]:-}" ]]; then
        log_info "Installing optional Zsh enhancement packages..."
        local optional_packages
        read -ra optional_packages <<< "${ZSH_OPTIONAL_PACKAGES[$distro]}"
        
        for opt_package in "${optional_packages[@]}"; do
            if ! install_package "$opt_package"; then
                log_warn "Failed to install optional package: $opt_package (continuing anyway)"
            fi
        done
    fi
    
    log_success "Zsh packages installed successfully"
    return 0
}

# Install Zinit plugin manager
# Returns: 0 if successful, 1 if failed
# Requirements: 7.1 - Plugin management setup
install_zinit() {
    log_info "Installing Zinit plugin manager..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would clone Zinit to: $ZINIT_HOME"
        return 0
    fi
    
    # Check if Zinit is already installed
    if [[ -d "$ZINIT_HOME" ]]; then
        log_info "Zinit already installed, updating..."
        if ! git -C "$ZINIT_HOME" pull --quiet; then
            log_warn "Failed to update Zinit, continuing with existing installation"
        fi
        return 0
    fi
    
    # Create directory and clone Zinit
    local zinit_dir
    zinit_dir=$(dirname "$ZINIT_HOME")
    
    if ! mkdir -p "$zinit_dir"; then
        log_error "Failed to create Zinit directory: $zinit_dir"
        return 1
    fi
    
    log_info "Cloning Zinit plugin manager..."
    if ! git clone --quiet https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"; then
        log_error "Failed to clone Zinit repository"
        return 1
    fi
    
    log_success "Zinit plugin manager installed successfully"
    return 0
}

# Configure Zsh with dotfiles
# Returns: 0 if successful, 1 if failed
# Requirements: 7.1, 7.2 - Configuration management with dotfiles integration
configure_zsh() {
    log_info "Configuring Zsh shell..."
    
    if [[ ! -f "$ZSH_CONFIG_SOURCE" ]]; then
        log_error "Zsh configuration source not found: $ZSH_CONFIG_SOURCE"
        return 1
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create symlink: $ZSH_CONFIG_TARGET -> $ZSH_CONFIG_SOURCE"
        log_info "[DRY-RUN] Would install Zinit plugin manager"
        return 0
    fi
    
    # Install Zinit first
    if ! install_zinit; then
        log_error "Failed to install Zinit plugin manager"
        return 1
    fi
    
    # Create symlink for .zshrc
    log_info "Creating symlink for Zsh configuration..."
    if ! create_symlink "$ZSH_CONFIG_SOURCE" "$ZSH_CONFIG_TARGET"; then
        log_error "Failed to create Zsh configuration symlink"
        return 1
    fi
    
    # Create history file directory if needed
    local histfile_dir="$HOME"
    if [[ ! -d "$histfile_dir" ]]; then
        mkdir -p "$histfile_dir"
    fi
    
    # Create completion dump directory
    local zcompdump_dir="$HOME"
    if [[ ! -d "$zcompdump_dir" ]]; then
        mkdir -p "$zcompdump_dir"
    fi
    
    # Create local bin directory for user scripts
    local local_bin="$HOME/.local/bin"
    if [[ ! -d "$local_bin" ]]; then
        mkdir -p "$local_bin"
    fi
    
    log_success "Zsh configuration completed"
    return 0
}

# Set Zsh as default shell
# Returns: 0 if successful, 1 if failed
# Requirements: 7.1 - Shell configuration
set_zsh_as_default() {
    log_info "Setting Zsh as default shell..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would set Zsh as default shell for user: $USER"
        return 0
    fi
    
    # Check if Zsh is already the default shell
    if is_zsh_default_shell; then
        log_info "Zsh is already the default shell"
        return 0
    fi
    
    # Get Zsh path
    local zsh_path
    zsh_path=$(which zsh)
    
    if [[ -z "$zsh_path" ]]; then
        log_error "Zsh binary not found in PATH"
        return 1
    fi
    
    # Check if Zsh is in /etc/shells
    if ! grep -q "$zsh_path" /etc/shells 2>/dev/null; then
        log_info "Adding Zsh to /etc/shells..."
        if ! echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null; then
            log_error "Failed to add Zsh to /etc/shells"
            return 1
        fi
    fi
    
    # Change default shell
    log_info "Changing default shell to Zsh..."
    if ! chsh -s "$zsh_path"; then
        log_error "Failed to change default shell to Zsh"
        log_info "You can manually change it later with: chsh -s $zsh_path"
        return 1
    fi
    
    log_success "Zsh set as default shell (will take effect on next login)"
    return 0
}

# Initialize Zsh plugins (run Zsh once to trigger plugin installation)
# Returns: 0 if successful, 1 if failed
initialize_zsh_plugins() {
    log_info "Initializing Zsh plugins..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would initialize Zsh plugins"
        return 0
    fi
    
    # Run Zsh with a simple command to trigger plugin installation
    log_info "Running Zsh to initialize plugins (this may take a moment)..."
    
    # Use a timeout to prevent hanging
    if ! timeout 60 zsh -c "
        source '$ZSH_CONFIG_TARGET' 2>/dev/null || true
        echo 'Zsh plugins initialized'
        exit 0
    " >/dev/null 2>&1; then
        log_warn "Zsh plugin initialization timed out or failed (plugins will install on first use)"
    else
        log_success "Zsh plugins initialized successfully"
    fi
    
    return 0
}

# Validate Zsh installation
# Returns: 0 if valid, 1 if invalid
# Requirements: 10.1 - Post-installation validation
validate_zsh_installation() {
    log_info "Validating Zsh installation..."
    
    # Check if binary is available
    if ! command -v zsh >/dev/null 2>&1; then
        log_error "Zsh binary not found in PATH"
        return 1
    fi
    
    # Check if configuration exists
    if [[ ! -f "$ZSH_CONFIG_TARGET" ]]; then
        log_error "Zsh configuration file not found: $ZSH_CONFIG_TARGET"
        return 1
    fi
    
    # Check if Zinit is installed
    if [[ ! -d "$ZINIT_HOME" ]]; then
        log_warn "Zinit plugin manager not found: $ZINIT_HOME"
    fi
    
    # Test Zsh version (basic functionality test)
    if ! zsh --version >/dev/null 2>&1; then
        log_error "Zsh version check failed"
        return 1
    fi
    
    # Check if configuration is syntactically valid
    if ! zsh -n "$ZSH_CONFIG_TARGET" 2>/dev/null; then
        log_error "Zsh configuration has syntax errors"
        return 1
    fi
    
    log_success "Zsh installation validation passed"
    return 0
}

#######################################
# Main Installation Function
#######################################

# Main Zsh installation function
# Returns: 0 if successful, 1 if failed
# Requirements: 7.1, 7.2 - Complete component installation
install_zsh() {
    log_section "Installing Zsh Shell"
    
    # Check if already installed
    if is_zsh_installed; then
        log_info "Zsh is already installed"
        if ! ask_yes_no "Do you want to reconfigure Zsh?" "n"; then
            log_info "Skipping Zsh installation"
            return 0
        fi
    fi
    
    # Validate distribution support
    local distro
    distro=$(get_distro)
    if [[ -z "${ZSH_PACKAGES[$distro]}" ]]; then
        log_error "Zsh installation not supported on: $distro"
        return 1
    fi
    
    # Install packages
    if ! install_zsh_packages; then
        log_error "Failed to install Zsh packages"
        return 1
    fi
    
    # Configure Zsh
    if ! configure_zsh; then
        log_error "Failed to configure Zsh"
        return 1
    fi
    
    # Validate installation
    if ! validate_zsh_installation; then
        log_error "Zsh installation validation failed"
        return 1
    fi
    
    # Ask if user wants to set as default shell
    if ask_yes_no "Set Zsh as default shell?" "y"; then
        set_zsh_as_default
    fi
    
    # Initialize plugins
    if ask_yes_no "Initialize Zsh plugins now?" "y"; then
        initialize_zsh_plugins
    fi
    
    log_success "Zsh installation completed successfully"
    log_info "Note: If you changed your default shell, please log out and back in for changes to take effect"
    return 0
}

# Uninstall Zsh (for testing/cleanup)
# Returns: 0 if successful, 1 if failed
uninstall_zsh() {
    log_info "Uninstalling Zsh..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would uninstall Zsh packages and remove configurations"
        return 0
    fi
    
    local distro
    distro=$(get_distro)
    
    # Remove packages
    case "$distro" in
        "arch")
            sudo pacman -Rns --noconfirm zsh zsh-completions 2>/dev/null || true
            ;;
        "ubuntu")
            sudo apt-get remove --purge -y zsh 2>/dev/null || true
            ;;
    esac
    
    # Remove configuration (with backup)
    if [[ -f "$ZSH_CONFIG_TARGET" ]]; then
        local backup_dir="$HOME/.config/install-backups"
        mkdir -p "$backup_dir"
        mv "$ZSH_CONFIG_TARGET" "$backup_dir/zshrc-$(date +%Y%m%d_%H%M%S)"
        log_info "Zsh configuration backed up to: $backup_dir"
    fi
    
    # Remove Zinit (with backup)
    if [[ -d "$ZINIT_HOME" ]]; then
        local backup_dir="$HOME/.config/install-backups"
        mkdir -p "$backup_dir"
        mv "$ZINIT_HOME" "$backup_dir/zinit-$(date +%Y%m%d_%H%M%S)"
        log_info "Zinit backed up to: $backup_dir"
    fi
    
    log_success "Zsh uninstalled successfully"
    return 0
}

# Export functions for use by other modules
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Being sourced, export functions
    export -f install_zsh
    export -f configure_zsh
    export -f is_zsh_installed
    export -f validate_zsh_installation
    export -f uninstall_zsh
    export -f set_zsh_as_default
fi