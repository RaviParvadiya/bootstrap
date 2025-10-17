#!/usr/bin/env bash
#
# components/terminal/kitty.sh - Kitty terminal emulator installation and configuration
# Handles Kitty installation, font dependencies, theme setup, and dotfile linking.

source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"
source "$CORE_DIR/logger.sh"
source "$CORE_DIR/common.sh"

# Component metadata
readonly KITTY_CONFIG_TARGET="$HOME/.config/kitty"

# Package definitions per distribution

declare -A KITTY_PACKAGES=(
    ["arch"]="kitty ttf-jetbrains-mono-nerd ttf-firacode-nerd"
    ["ubuntu"]="kitty fonts-jetbrains-mono fonts-firacode"
)

#######################################
# Kitty Installation Functions
#######################################

# Install Kitty packages
install_kitty_packages() {
    local distro
    distro=$(get_distro)
    
    log_info "Installing Kitty for $distro..."
    
    install_packages ${KITTY_PACKAGES[$distro]} || {
        log_error "Kitty installation failed"
        return 1
    }

    log_success "Kitty packages installed"
}

# Configure Kitty with dotfiles
configure_kitty() {
    if [[ ! -d "$DOTFILES_DIR/kitty" ]]; then
        log_error "Missing kitty dotfiles directory: $DOTFILES_DIR/kitty"
        return 1
    fi
    
    # Stow Kitty configuration
    log_info "Applying Kitty configuration..."
    if ! (cd "$DOTFILES_DIR" && stow --target="$HOME" kitty); then
        log_error "Failed to stow Kitty configuration"
        return 1
    fi
    
    log_success "Kitty configuration applied"
}



# Validate Kitty installation
validate_kitty_installation() {
    log_info "Validating Kitty installation..."
    
    # Check if binary is available
    command -v kitty >/dev/null || { log_error "Kitty not found"; return 1; }
    
    # Check if configuration exists
    [[ -f "$KITTY_CONFIG_TARGET/kitty.conf" ]] || log_warn "kitty.conf missing"
    
    log_success "Kitty validation passed"
}

# Set Kitty as default terminal (optional)
set_kitty_as_default() {
    log_info "Setting Kitty as default terminal..."
    
    # Set as default terminal emulator
    if command -v update-alternatives >/dev/null 2>&1; then
        # Ubuntu/Debian method
        sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator "$(which kitty)" 60
        sudo update-alternatives --set x-terminal-emulator "$(which kitty)"
    fi
    
    # Set XDG default
    if command -v xdg-settings >/dev/null 2>&1; then
        xdg-settings set default-terminal-emulator kitty.desktop
    fi
    
    # Set TERMINAL environment variable
    if ! grep -q "export TERMINAL=kitty" "$HOME/.bashrc" 2>/dev/null; then
        echo "export TERMINAL=kitty" >> "$HOME/.bashrc"
    fi
    
    if [[ -f "$HOME/.zshrc" ]] && ! grep -q "export TERMINAL=kitty" "$HOME/.zshrc" 2>/dev/null; then
        echo "export TERMINAL=kitty" >> "$HOME/.zshrc"
    fi
    
    log_success "Kitty set as default terminal"
}

#######################################
# Main Installation Function
#######################################

# Main Kitty installation function
install_kitty() {
    log_section "Installing Kitty Terminal Emulator"
    
    install_kitty_packages || return 1
    configure_kitty || return 1
    validate_kitty_installation || return 1
    
    ask_yes_no "Set Kitty as default terminal?" "y" && set_kitty_as_default
    
    log_success "Kitty setup complete"
}

# Uninstall Kitty (for testing/cleanup)
uninstall_kitty() {
    log_info "Uninstalling Kitty..."
    
    local distro
    distro=$(get_distro)
    
    # Remove packages
    case "$distro" in
        "arch")
            sudo pacman -Rns --noconfirm kitty 2>/dev/null || true
            ;;
        "ubuntu")
            sudo apt-get remove --purge -y kitty 2>/dev/null || true
            ;;
    esac
    
    # Unstow configuration
    if [[ -d "$DOTFILES_DIR/kitty" ]]; then
        log_info "Removing Kitty configuration with stow..."
        (cd "$DOTFILES_DIR" && stow --target="$HOME" --delete kitty) || log_warn "Failed to unstow kitty configuration"
    fi
    
    log_success "Kitty uninstalled"
}

# Export essential functions
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && export -f install_kitty