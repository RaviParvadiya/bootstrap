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

#######################################
# Tmux Installation Functions
#######################################

# Check if Tmux is already installed
is_tmux_installed() {
    command -v tmux >/dev/null 2>&1
}

# Check if TPM (Tmux Plugin Manager) is installed
is_tpm_installed() {
    [[ -d "$TMUX_PLUGINS_DIR/tpm" ]]
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
    log_section "Configuring Tmux Terminal Multiplexer"
    
    # Check if already installed (packages should be installed by main system)
    if ! is_tmux_installed; then
        log_error "Tmux not found. Ensure packages are installed by the main system first."
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
    
    log_success "Tmux configuration completed successfully"
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
    
    # Remove configuration
    if [[ -f "$TMUX_CONFIG_TARGET" ]]; then
        rm -f "$TMUX_CONFIG_TARGET"
        log_info "Tmux configuration removed"
    fi
    
    # Remove plugins directory
    if [[ -d "$TMUX_PLUGINS_DIR" ]]; then
        rm -rf "$TMUX_PLUGINS_DIR"
        log_info "Tmux plugins removed"
    fi
    
    log_success "Tmux uninstalled successfully"
    return 0
}

# Export essential functions
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && export -f install_tmux configure_tmux is_tmux_installed install_tpm