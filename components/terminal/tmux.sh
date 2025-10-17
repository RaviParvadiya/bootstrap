#!/usr/bin/env bash
#
# components/terminal/tmux.sh - Tmux terminal multiplexer installation and configuration
# Handles installation, TPM setup, plugin management, and dotfiles integration.

source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"
source "$CORE_DIR/logger.sh"
source "$CORE_DIR/common.sh"

# Component metadata
readonly TMUX_CONFIG_TARGET="$HOME/.tmux.conf"
readonly TMUX_PLUGINS_DIR="$HOME/.tmux/plugins"
readonly TPM_REPO="https://github.com/tmux-plugins/tpm"

# Package definitions per distribution
declare -A TMUX_PACKAGES=(
    ["arch"]="tmux"
    ["ubuntu"]="tmux"
)

#######################################
# Tmux Installation Functions
#######################################

# Check if TPM (Tmux Plugin Manager) is installed
is_tpm_installed() {
    [[ -d "$TMUX_PLUGINS_DIR/tpm" ]]
}

# Install Tmux packages
install_tmux_packages() {
    local distro
    distro=$(get_distro)
    
    log_info "Installing Tmux packages for $distro..."
    install_packages ${TMUX_PACKAGES[$distro]} || return 1
    
    log_success "Tmux packages installed successfully"
}

# Install TPM (Tmux Plugin Manager)
install_tpm() {
    log_info "Installing TPM (Tmux Plugin Manager)..."
    
    # Create plugins directory
    mkdir -p "$TMUX_PLUGINS_DIR"
    
    # Clone TPM repository
    if [[ -d "$TMUX_PLUGINS_DIR/tpm" ]]; then
        log_info "TPM already exists, updating..."
        git -C "$TMUX_PLUGINS_DIR/tpm" pull >/dev/null 2>&1 || log_warn "TPM update failed"
    else
        log_info "Cloning TPM repository..."
        git clone "$TPM_REPO" "$TMUX_PLUGINS_DIR/tpm" >/dev/null 2>&1 || {
            log_error "Failed to clone TPM repository"
            return 1
        }
    fi
    
    log_success "TPM installed successfully"
}

# Configure Tmux with dotfiles
configure_tmux() {
    [[ ! -d "$DOTFILES_DIR/tmux" ]] && { log_error "Missing tmux dotfiles directory: $DOTFILES_DIR/tmux"; return 1; }
    
    # Stow Tmux configuration
    log_info "Applying Tmux configuration..."
    if ! (cd "$DOTFILES_DIR" && stow --target="$HOME" tmux); then
        log_error "Failed to stow Tmux configuration"
        return 1
    fi
    
    log_success "Tmux configuration applied"
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
    
    [[ -f "$tpm_install_script" ]] && bash "$tpm_install_script" >/dev/null 2>&1 \
        && log_success "Tmux plugins installed" \
        || log_warn "Plugin install script not found or failed"
}

# Validate Tmux installation
validate_tmux_installation() {
    log_info "Validating Tmux installation..."
    
    command -v tmux >/dev/null || { log_error "Tmux not found in PATH"; return 1; }
    tmux -V >/dev/null 2>&1 || { log_error "Tmux version check failed"; return 1; }
    
    [[ -f "$TMUX_CONFIG_TARGET" ]] || log_warn "Config missing: $TMUX_CONFIG_TARGET"
    
    # Check if TPM is installed
    if is_tpm_installed; then
        log_debug "TPM (Tmux Plugin Manager) is installed"
    else
        log_warn "TPM not found, plugins may not work"
    fi
    
    log_success "Tmux validation passed"
}

# Create a test tmux session to verify functionality
test_tmux_functionality() {
    log_info "Testing Tmux functionality..."

    if tmux new-session -d -s "install-test" -c "$HOME" 'echo "Tmux test"; sleep 1'; then
        tmux kill-session -t "install-test" 2>/dev/null
        log_success "Tmux test passed"
    else
        log_warn "Tmux test session failed"
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
}

#######################################
# Main Installation Function
#######################################

# Main Tmux installation function
install_tmux() {
    log_section "Installing Tmux Terminal Multiplexer"

    install_tmux_binary || return 1
    install_tpm || return 1
    configure_tmux || return 1
    
    install_tmux_plugins
    validate_tmux_installation

    ask_yes_no "Run Tmux test?" "y" && test_tmux_functionality
    ask_yes_no "Enable Tmux autostart?" "n" && setup_tmux_autostart
    
    log_success "Tmux installation and configuration complete"
    log_info "Use Prefix + I to reload plugins inside tmux"
}

# Uninstall Tmux (for testing/cleanup)
uninstall_tmux() {
    log_info "Uninstalling Tmux..."
    
    local distro
    distro=$(get_distro)
    
    # Safety check: kill all tmux sessions before unstowing
    if command -v tmux >/dev/null 2>&1; then
        if tmux list-sessions >/dev/null 2>&1; then
            log_warn "Active tmux sessions detected"
            if ask_yes_no "Kill all tmux sessions before uninstalling?" "y"; then
                tmux kill-server 2>/dev/null || true
            else
                log_error "Cannot safely uninstall with active tmux sessions"
                return 1
            fi
        fi
    fi
    
    # Unstow configuration
    if [[ -d "$DOTFILES_DIR/tmux" ]]; then
        log_info "Removing Tmux configuration with stow..."
        (cd "$DOTFILES_DIR" && stow --target="$HOME" --delete tmux) || log_warn "Failed to unstow tmux configuration"
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
    
    # Remove plugins directory
    if [[ -d "$TMUX_PLUGINS_DIR" ]]; then
        rm -rf "$TMUX_PLUGINS_DIR"
        log_info "Tmux plugins removed"
    fi
    
    log_success "Tmux uninstalled"
}

# Export essential functions
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && export -f install_tmux