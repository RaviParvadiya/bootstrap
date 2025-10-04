#!/usr/bin/env bash

# components/terminal/tmux.sh - Tmux terminal multiplexer installation and configuration
# This module handles the installation and configuration of Tmux terminal multiplexer
# with plugin management (TPM), theme support, and proper dotfiles integration.

source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"
source "$CORE_DIR/logger.sh"
source "$CORE_DIR/common.sh"

# Component metadata
readonly TMUX_COMPONENT_NAME="tmux"
readonly TMUX_CONFIG_SOURCE="$DOTFILES_DIR/tmux/.tmux.conf"
readonly TMUX_CONFIG_TARGET="$HOME/.tmux.conf"
readonly TMUX_PLUGINS_DIR="$HOME/.tmux/plugins"
readonly TPM_REPO="https://github.com/tmux-plugins/tpm"

# Package definitions per distribution
declare -A TMUX_PACKAGES=(
    ["arch"]="tmux"
    ["ubuntu"]="tmux"
)

# Additional dependencies for tmux functionality
declare -A TMUX_DEPENDENCIES=(
    ["arch"]="git curl"
    ["ubuntu"]="git curl"
)

#######################################
# Tmux Installation Functions
#######################################

# Check if Tmux is already installed
is_tmux_installed() {
    if command -v tmux >/dev/null 2>&1; then
        return 0
    fi
    
    # Also check if package is installed via package manager
    local distro
    distro=$(get_distro)
    
    case "$distro" in
        "arch")
            pacman -Qi tmux >/dev/null 2>&1
            ;;
        "ubuntu")
            dpkg -l tmux >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

# Check if TPM (Tmux Plugin Manager) is installed
is_tpm_installed() {
    [[ -d "$TMUX_PLUGINS_DIR/tpm" ]]
}

# Install Tmux packages
install_tmux_packages() {
    local distro
    distro=$(get_distro)
    
    if [[ -z "${TMUX_PACKAGES[$distro]}" ]]; then
        log_error "Tmux packages not defined for distribution: $distro"
        return 1
    fi
    
    log_info "Installing Tmux packages for $distro..."
    
    # Install dependencies first
    local dependencies
    read -ra dependencies <<< "${TMUX_DEPENDENCIES[$distro]}"
    
    for dep in "${dependencies[@]}"; do
        if ! install_package "$dep"; then
            log_warn "Failed to install dependency: $dep (continuing anyway)"
        fi
    done
    
    # Install main Tmux package
    local packages
    read -ra packages <<< "${TMUX_PACKAGES[$distro]}"
    
    for package in "${packages[@]}"; do
        if ! install_package "$package"; then
            log_error "Failed to install Tmux package: $package"
            return 1
        fi
    done
    
    log_success "Tmux packages installed successfully"
    return 0
}

# Install TPM (Tmux Plugin Manager)
install_tpm() {
    log_info "Installing TPM (Tmux Plugin Manager)..."
    
    # Create plugins directory
    if ! mkdir -p "$TMUX_PLUGINS_DIR"; then
        log_error "Failed to create tmux plugins directory: $TMUX_PLUGINS_DIR"
        return 1
    fi
    
    # Clone TPM repository
    if [[ -d "$TMUX_PLUGINS_DIR/tpm" ]]; then
        log_info "TPM already exists, updating..."
        if ! git -C "$TMUX_PLUGINS_DIR/tpm" pull; then
            log_warn "Failed to update TPM, continuing with existing version"
        fi
    else
        log_info "Cloning TPM repository..."
        if ! git clone "$TPM_REPO" "$TMUX_PLUGINS_DIR/tpm"; then
            log_error "Failed to clone TPM repository"
            return 1
        fi
    fi
    
    log_success "TPM installed successfully"
    return 0
}

# Configure Tmux with dotfiles
configure_tmux() {
    log_info "Configuring Tmux terminal multiplexer..."
    
    if [[ ! -f "$TMUX_CONFIG_SOURCE" ]]; then
        log_error "Tmux configuration source not found: $TMUX_CONFIG_SOURCE"
        return 1
    fi
    
    # Create symlink for tmux configuration
    if ! create_symlink "$TMUX_CONFIG_SOURCE" "$TMUX_CONFIG_TARGET"; then
        log_error "Failed to create symlink for tmux configuration"
        return 1
    fi
    
    log_success "Tmux configuration completed"
    return 0
}

# Install Tmux plugins using TPM
install_tmux_plugins() {
    log_info "Installing Tmux plugins..."
    
    # Check if TPM is installed
    if ! is_tpm_installed; then
        log_error "TPM not installed, cannot install plugins"
        return 1
    fi
    
    # Install plugins using TPM
    local tpm_install_script="$TMUX_PLUGINS_DIR/tpm/scripts/install_plugins.sh"
    
    if [[ -f "$tpm_install_script" ]]; then
        log_info "Running TPM plugin installation..."
        if bash "$tpm_install_script"; then
            log_success "Tmux plugins installed successfully"
        else
            log_warn "Plugin installation completed with warnings"
        fi
    else
        log_warn "TPM install script not found, plugins may need manual installation"
    fi
    
    return 0
}

# Validate Tmux installation
validate_tmux_installation() {
    log_info "Validating Tmux installation..."
    
    # Check if binary is available
    if ! command -v tmux >/dev/null 2>&1; then
        log_error "Tmux binary not found in PATH"
        return 1
    fi
    
    # Check if configuration exists
    if [[ ! -f "$TMUX_CONFIG_TARGET" ]]; then
        log_warn "Tmux configuration file not found: $TMUX_CONFIG_TARGET"
    fi
    
    # Test Tmux version (basic functionality test)
    if ! tmux -V >/dev/null 2>&1; then
        log_error "Tmux version check failed"
        return 1
    fi
    
    # Check if TPM is installed
    if is_tpm_installed; then
        log_debug "TPM (Tmux Plugin Manager) is installed"
    else
        log_warn "TPM not found, plugins may not work"
    fi
    
    # Check if plugins directory exists
    if [[ -d "$TMUX_PLUGINS_DIR" ]]; then
        local plugin_count
        plugin_count=$(find "$TMUX_PLUGINS_DIR" -maxdepth 1 -type d | wc -l)
        log_debug "Found $((plugin_count - 1)) tmux plugins"
    fi
    
    log_success "Tmux installation validation passed"
    return 0
}

# Create a test tmux session to verify functionality
test_tmux_functionality() {
    log_info "Testing Tmux functionality..."
    
    # Create a test session and immediately detach
    if tmux new-session -d -s "install-test" -c "$HOME" 'echo "Tmux test session"; sleep 1'; then
        log_debug "Test session created successfully"
        
        # Kill the test session
        if tmux kill-session -t "install-test" 2>/dev/null; then
            log_debug "Test session cleaned up"
        fi
        
        log_success "Tmux functionality test passed"
        return 0
    else
        log_error "Failed to create tmux test session"
        return 1
    fi
}

# Setup tmux to start automatically (optional)
setup_tmux_autostart() {
    log_info "Setting up Tmux autostart..."
    
    local tmux_autostart='
# Auto-start tmux session
if command -v tmux &> /dev/null && [ -n "$PS1" ] && [[ ! "$TERM" =~ screen ]] && [[ ! "$TERM" =~ tmux ]] && [ -z "$TMUX" ]; then
    exec tmux new-session -A -s main
fi'
    
    # Add to .bashrc if it exists
    if [[ -f "$HOME/.bashrc" ]]; then
        if ! grep -q "Auto-start tmux session" "$HOME/.bashrc"; then
            echo "$tmux_autostart" >> "$HOME/.bashrc"
            log_debug "Added tmux autostart to .bashrc"
        fi
    fi
    
    # Add to .zshrc if it exists
    if [[ -f "$HOME/.zshrc" ]]; then
        if ! grep -q "Auto-start tmux session" "$HOME/.zshrc"; then
            echo "$tmux_autostart" >> "$HOME/.zshrc"
            log_debug "Added tmux autostart to .zshrc"
        fi
    fi
    
    log_success "Tmux autostart configured"
    return 0
}

#######################################
# Main Installation Function
#######################################

# Main Tmux installation function
install_tmux() {
    log_section "Installing Tmux Terminal Multiplexer"
    
    # Check if already installed
    if is_tmux_installed; then
        log_info "Tmux is already installed"
        if ! ask_yes_no "Do you want to reconfigure Tmux?" "n"; then
            log_info "Skipping Tmux installation"
            return 0
        fi
    fi
    
    # Validate distribution support
    local distro
    distro=$(get_distro)
    if [[ -z "${TMUX_PACKAGES[$distro]}" ]]; then
        log_error "Tmux installation not supported on: $distro"
        return 1
    fi
    
    # Install packages
    if ! install_tmux_packages; then
        log_error "Failed to install Tmux packages"
        return 1
    fi
    
    # Install TPM (Tmux Plugin Manager)
    if ! install_tpm; then
        log_error "Failed to install TPM"
        return 1
    fi
    
    # Configure Tmux
    if ! configure_tmux; then
        log_error "Failed to configure Tmux"
        return 1
    fi
    
    # Install plugins
    if ! install_tmux_plugins; then
        log_warn "Plugin installation failed, but continuing"
    fi
    
    # Validate installation
    if ! validate_tmux_installation; then
        log_error "Tmux installation validation failed"
        return 1
    fi
    
    # Test functionality
    if ! test_tmux_functionality; then
        log_warn "Tmux functionality test failed, but installation appears complete"
    fi
    
    # Ask if user wants autostart
    if ask_yes_no "Enable Tmux autostart in terminal sessions?" "n"; then
        setup_tmux_autostart
    fi
    
    log_success "Tmux installation completed successfully"
    log_info "To reload plugins in tmux, press: Prefix + I (default: Ctrl-s + I)"
    return 0
}

# Uninstall Tmux (for testing/cleanup)
uninstall_tmux() {
    log_info "Uninstalling Tmux..."
    
    local distro
    distro=$(get_distro)
    
    # Kill all tmux sessions
    if command -v tmux >/dev/null 2>&1; then
        tmux kill-server 2>/dev/null || true
    fi
    
    # Remove packages
    case "$distro" in
        "arch")
            sudo pacman -Rns --noconfirm tmux 2>/dev/null || true
            ;;
        "ubuntu")
            sudo apt-get remove --purge -y tmux 2>/dev/null || true
            ;;
    esac
    
    # Remove configuration (with backup)
    if [[ -f "$TMUX_CONFIG_TARGET" ]]; then
        local backup_dir="$HOME/.config/install-backups/tmux-$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup_dir"
        cp "$TMUX_CONFIG_TARGET" "$backup_dir/"
        rm -f "$TMUX_CONFIG_TARGET"
        log_info "Tmux configuration backed up to: $backup_dir"
    fi
    
    # Remove plugins directory (with backup)
    if [[ -d "$TMUX_PLUGINS_DIR" ]]; then
        local backup_dir="$HOME/.config/install-backups/tmux-plugins-$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$(dirname "$backup_dir")"
        mv "$TMUX_PLUGINS_DIR" "$backup_dir"
        log_info "Tmux plugins backed up to: $backup_dir"
    fi
    
    log_success "Tmux uninstalled successfully"
    return 0
}

# Export essential functions
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && export -f install_tmux configure_tmux is_tmux_installed install_tpm