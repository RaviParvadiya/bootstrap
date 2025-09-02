#!/usr/bin/env bash

# components/terminal/tmux.sh - Tmux terminal multiplexer installation and configuration
# This module handles the installation and configuration of Tmux terminal multiplexer
# with plugin management (TPM), theme support, and proper dotfiles integration.

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
readonly TMUX_COMPONENT_NAME="tmux"
readonly TMUX_CONFIG_SOURCE="$PROJECT_ROOT/dotfiles/tmux/.tmux.conf"
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
# Returns: 0 if installed, 1 if not installed
# Requirements: 7.1 - Component installation detection
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
# Returns: 0 if installed, 1 if not installed
is_tpm_installed() {
    [[ -d "$TMUX_PLUGINS_DIR/tpm" ]]
}

# Install Tmux packages
# Returns: 0 if successful, 1 if failed
# Requirements: 7.1 - Package installation with distribution detection
install_tmux_packages() {
    local distro
    distro=$(get_distro)
    
    if [[ -z "${TMUX_PACKAGES[$distro]}" ]]; then
        log_error "Tmux packages not defined for distribution: $distro"
        return 1
    fi
    
    log_info "Installing Tmux packages for $distro..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install packages: ${TMUX_PACKAGES[$distro]}"
        log_info "[DRY-RUN] Would install dependencies: ${TMUX_DEPENDENCIES[$distro]}"
        return 0
    fi
    
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
# Returns: 0 if successful, 1 if failed
install_tpm() {
    log_info "Installing TPM (Tmux Plugin Manager)..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would clone TPM repository to: $TMUX_PLUGINS_DIR/tpm"
        return 0
    fi
    
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
# Returns: 0 if successful, 1 if failed
# Requirements: 7.1, 7.2 - Configuration management with dotfiles integration
configure_tmux() {
    log_info "Configuring Tmux terminal multiplexer..."
    
    if [[ ! -f "$TMUX_CONFIG_SOURCE" ]]; then
        log_error "Tmux configuration source not found: $TMUX_CONFIG_SOURCE"
        return 1
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create symlink: $TMUX_CONFIG_TARGET -> $TMUX_CONFIG_SOURCE"
        return 0
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
# Returns: 0 if successful, 1 if failed
install_tmux_plugins() {
    log_info "Installing Tmux plugins..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install tmux plugins using TPM"
        return 0
    fi
    
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
# Returns: 0 if valid, 1 if invalid
# Requirements: 10.1 - Post-installation validation
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
# Returns: 0 if successful, 1 if failed
test_tmux_functionality() {
    log_info "Testing Tmux functionality..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would test tmux session creation"
        return 0
    fi
    
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
# Returns: 0 if successful, 1 if failed
setup_tmux_autostart() {
    log_info "Setting up Tmux autostart..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would add tmux autostart to shell configuration"
        return 0
    fi
    
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
# Returns: 0 if successful, 1 if failed
# Requirements: 7.1, 7.2 - Complete component installation
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
# Returns: 0 if successful, 1 if failed
uninstall_tmux() {
    log_info "Uninstalling Tmux..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would uninstall Tmux packages and remove configurations"
        return 0
    fi
    
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

# Export functions for use by other modules
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Being sourced, export functions
    export -f install_tmux
    export -f configure_tmux
    export -f is_tmux_installed
    export -f validate_tmux_installation
    export -f uninstall_tmux
    export -f install_tpm
    export -f is_tpm_installed
fi