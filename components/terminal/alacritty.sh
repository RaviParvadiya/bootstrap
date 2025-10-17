#!/usr/bin/env bash
#
# components/terminal/alacritty.sh - Alacritty terminal emulator installation and configuration
# Handles cross-distro Alacritty setup with font dependencies and dotfile linking.

source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"
source "$CORE_DIR/logger.sh"
source "$CORE_DIR/common.sh"

# Component metadata
readonly ALACRITTY_CONFIG_TARGET="$HOME/.config/alacritty"

# Package definitions per distribution
declare -A ALACRITTY_PACKAGES=(
    ["arch"]="alacritty ttf-cascadia-code ttf-firacode-nerd"
    ["ubuntu"]="alacritty fonts-cascadia-code fonts-firacode"
)

#######################################
# Alacritty Installation Functions
#######################################

# Install Alacritty packages
install_alacritty_packages() {
    local distro
    distro=$(get_distro)
    
    log_info "Installing Alacritty packages for $distro..."
    
    install_packages ${ALACRITTY_PACKAGES[$distro]} || {
        log_error "Failed to install Alacritty package(s)"
        return 1
    }
    
    log_success "Alacritty packages installed successfully"
}   

# Configure Alacritty with dotfiles
configure_alacritty() {
    [[ ! -d "$DOTFILES_DIR/alacritty" ]] && {
        log_error "Missing alacritty dotfiles directory: $DOTFILES_DIR/alacritty"
        return 1
    }

    # Stow Alacritty configuration
    log_info "Applying Alacritty configuration..."

    if ! (cd "$DOTFILES_DIR" && stow --target="$HOME" alacritty); then
        log_error "Failed to stow Alacritty configuration"
        return 1
    fi
    
    log_success "Alacritty configuration applied"
}

# Validate Alacritty installation
validate_alacritty_installation() {
    log_info "Validating Alacritty installation..."
    
    # Check if binary is available
    command -v alacritty >/dev/null || {
        log_error "Alacritty binary not found"
        return 1
    }
    
    # Check if configuration exists
    [[ -f "$ALACRITTY_CONFIG_TARGET/alacritty.toml" ]] || \
        log_warn "Missing config: $ALACRITTY_CONFIG_TARGET/alacritty.toml"
    
    log_success "Alacritty validation passed"
}

# Set Alacritty as default terminal (optional)
set_alacritty_as_default() {
    log_info "Setting Alacritty as default terminal..."
    
    # Set as default terminal emulator
    if command -v update-alternatives >/dev/null 2>&1; then
        # Ubuntu/Debian method
        sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator "$(which alacritty)" 50
        sudo update-alternatives --set x-terminal-emulator "$(which alacritty)"
    fi
    
    # Set XDG default
    command -v xdg-settings >/dev/null && \
        xdg-settings set default-terminal-emulator alacritty.desktop || true
    
    log_success "Alacritty set as default terminal"
}

#######################################
# Main Installation Function
#######################################

# Main Alacritty installation function
install_alacritty() {
    log_section "Installing Alacritty Terminal Emulator"

    install_alacritty_packages || return 1
    configure_alacritty || return 1
    validate_alacritty_installation
    
    ask_yes_no "Set Alacritty as default terminal?" "n" && set_alacritty_as_default
    
    log_success "Alacritty setup complete"
}

# Uninstall Alacritty (for testing/cleanup)
uninstall_alacritty() {
    log_info "Uninstalling Alacritty..."
    
    local distro
    distro=$(get_distro)
    
    # Remove packages
    case "$distro" in
        "arch")
            sudo pacman -Rns --noconfirm alacritty 2>/dev/null || true
            ;;
        "ubuntu")
            sudo apt-get remove --purge -y alacritty 2>/dev/null || true
            ;;
    esac
    
    # Unstow configuration
    if [[ -d "$DOTFILES_DIR/alacritty" ]]; then
        log_info "Removing Alacritty configuration with stow..."
        (cd "$DOTFILES_DIR" && stow --target="$HOME" --delete alacritty) || log_warn "Failed to unstow alacritty configuration"
    fi
    
    log_success "Alacritty uninstalled"
}

# Export essential functions
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && export -f install_alacritty