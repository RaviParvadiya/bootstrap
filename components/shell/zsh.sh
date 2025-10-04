#!/usr/bin/env bash

# components/shell/zsh.sh - Zsh shell installation and configuration
# This module handles the installation and configuration of Zsh shell with
# plugin management via Zinit, proper dotfiles integration, and cross-distribution support.

source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"
source "$CORE_DIR/logger.sh"
source "$CORE_DIR/common.sh"

# Helper functions
_dry_run_check() {
    [[ "$DRY_RUN" == "true" ]] && { log_info "[DRY-RUN] Would $1"; return 0; }
    return 1
}

# Component metadata
readonly ZSH_COMPONENT_NAME="zsh"
readonly ZSH_CONFIG_SOURCE="$DOTFILES_DIR/zshrc/.zshrc"
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
is_zsh_default_shell() {
    [[ "$SHELL" == *"zsh"* ]]
}

# Install Zsh packages
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

# Check if user's current shell is zsh and change to bash if needed
restore_bash_shell() {
    log_info "Checking if shell needs to be changed back to bash..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        if [[ "$SHELL" == *"zsh"* ]]; then
            log_info "[DRY-RUN] Would change default shell from zsh to bash"
        else
            log_info "[DRY-RUN] Current shell is not zsh, no change needed"
        fi
        return 0
    fi
    
    # Check if current shell is zsh
    if [[ "$SHELL" != *"zsh"* ]]; then
        log_info "Current shell is not zsh, no change needed"
        return 0
    fi
    
    # Find bash path
    local bash_path
    bash_path=$(which bash 2>/dev/null)
    
    if [[ -z "$bash_path" ]]; then
        log_error "Bash binary not found in PATH"
        return 1
    fi
    
    # Check if bash is in /etc/shells
    if ! grep -q "$bash_path" /etc/shells 2>/dev/null; then
        log_info "Adding bash to /etc/shells..."
        if ! echo "$bash_path" | sudo tee -a /etc/shells >/dev/null; then
            log_error "Failed to add bash to /etc/shells"
            return 1
        fi
    fi
    
    # Change default shell back to bash
    log_info "Changing default shell from zsh to bash..."
    if ! chsh -s "$bash_path"; then
        log_error "Failed to change default shell to bash"
        log_info "You can manually change it later with: chsh -s $bash_path"
        return 1
    fi
    
    log_success "Default shell changed to bash (will take effect on next login)"
    return 0
}

# Backup current shell information
# Arguments: $1 - backup session directory
backup_shell_info() {
    local session_dir="$1"
    
    if [[ -z "$session_dir" ]]; then
        log_error "Session directory is required for shell backup"
        return 1
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would backup shell information to: $session_dir/shell_info"
        return 0
    fi
    
    local shell_backup_file="$session_dir/shell_info"
    
    # Create shell info backup
    cat > "$shell_backup_file" << EOF
# Shell Information Backup
ORIGINAL_SHELL=$SHELL
BACKUP_DATE=$(date -Iseconds 2>/dev/null || date)
USER_NAME=$USER
SHELLS_FILE_BACKUP=true
EOF
    
    # Also backup /etc/shells if we can read it
    if [[ -r /etc/shells ]]; then
        cp /etc/shells "$session_dir/etc_shells_backup" 2>/dev/null || true
    fi
    
    log_debug "Shell information backed up to: $shell_backup_file"
    return 0
}

# Restore shell information from backup
# Arguments: $1 - backup session directory
restore_shell_info() {
    local session_dir="$1"
    
    if [[ -z "$session_dir" ]]; then
        log_error "Session directory is required for shell restore"
        return 1
    fi
    
    local shell_backup_file="$session_dir/shell_info"
    
    if [[ ! -f "$shell_backup_file" ]]; then
        log_debug "No shell information backup found"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would restore shell information from backup"
        return 0
    fi
    
    # Read original shell from backup
    local original_shell
    while IFS='=' read -r key value; do
        case "$key" in
            "ORIGINAL_SHELL") original_shell="$value" ;;
        esac
    done < "$shell_backup_file"
    
    if [[ -z "$original_shell" ]]; then
        log_warn "No original shell information found in backup"
        return 1
    fi
    
    # Check if the original shell binary still exists
    if [[ ! -x "$original_shell" ]]; then
        log_warn "Original shell binary not found: $original_shell"
        log_info "Falling back to bash"
        restore_bash_shell
        return $?
    fi
    
    # Check if current shell is different from original
    if [[ "$SHELL" == "$original_shell" ]]; then
        log_info "Shell is already set to original: $original_shell"
        return 0
    fi
    
    # Restore original shell
    log_info "Restoring original shell: $original_shell"
    if ! chsh -s "$original_shell"; then
        log_error "Failed to restore original shell: $original_shell"
        log_info "You can manually change it with: chsh -s $original_shell"
        return 1
    fi
    
    log_success "Original shell restored: $original_shell"
    return 0
}

# Uninstall Zsh (for testing/cleanup)
uninstall_zsh() {
    log_info "Uninstalling Zsh..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would uninstall Zsh packages and remove configurations"
        if [[ "$SHELL" == *"zsh"* ]]; then
            log_info "[DRY-RUN] Would change shell back to bash (current shell is zsh)"
        fi
        return 0
    fi
    
    # Check if zsh is the current default shell and change to bash if needed
    if [[ "$SHELL" == *"zsh"* ]]; then
        log_warn "Zsh is currently your default shell"
        if ask_yes_no "Change default shell to bash before uninstalling zsh?" "y"; then
            if ! restore_bash_shell; then
                log_error "Failed to change shell to bash"
                if ! ask_yes_no "Continue with zsh uninstall anyway? (This may cause login issues)" "n"; then
                    log_info "Zsh uninstall cancelled by user"
                    return 1
                fi
            fi
        else
            log_warn "Keeping zsh as default shell - you may experience login issues after uninstall"
            log_warn "You can manually change your shell later with: chsh -s /bin/bash"
        fi
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
    
    # Final reminder about shell change
    if [[ "$SHELL" == *"zsh"* ]]; then
        log_warn "IMPORTANT: Your default shell is still set to zsh"
        log_warn "Please log out and back in, or run: chsh -s /bin/bash"
    fi
    
    return 0
}

# Export essential functions
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && export -f install_zsh configure_zsh is_zsh_installed set_zsh_as_default