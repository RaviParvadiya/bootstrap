#!/usr/bin/env bash
#
# components/shell/starship.sh - Starship prompt installation and configuration
# Handles Starship prompt installation, font dependencies, and shell integration.

source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"
source "$CORE_DIR/logger.sh"
source "$CORE_DIR/common.sh"

# Component metadata
readonly STARSHIP_COMPONENT_NAME="starship"
readonly STARSHIP_CONFIG_SOURCE="$DOTFILES_DIR/starship/.config/starship.toml"
readonly STARSHIP_CONFIG_TARGET="$HOME/.config/starship.toml"
readonly STARSHIP_INSTALL_URL="https://starship.rs/install.sh"

# Packages per distro
declare -A STARSHIP_PACKAGES=(
    ["arch"]="starship ttf-jetbrains-mono-nerd"
    ["ubuntu"]="fonts-noto-color-emoji" # Not in Ubuntu repos, use install script
)

#######################################
# Starship Installation Functions
#######################################

# Install Starship via package manager (Arch) or install script (Ubuntu)
install_starship_binary() {
    local distro
    distro=$(get_distro)
    
    case "$distro" in
        "arch")
            log_info "Installing Starship from Arch repositories..."
            install_packages ${STARSHIP_PACKAGES[$distro]} || return 1
            ;;
        "ubuntu")
            if [[ -n "${STARSHIP_PACKAGES[$distro]}" ]]; then
                install_packages ${STARSHIP_PACKAGES[$distro]} || log_warn "Some font packages failed to install"
            fi

            # Use official install script for Ubuntu
            install_starship_via_script || return 1
            ;;
        *)
            log_error "Starship installation not supported on: $distro"
            return 1
            ;;
    esac
    
    log_success "Starship binary installed"
}

# Install Starship via official install script
install_starship_via_script() {
    log_info "Installing Starship via official install script..."
    
    # Download and run install script
    local installer="curl -fsSL"
    command -v curl >/dev/null || installer="wget -qO-"

    $installer "$STARSHIP_INSTALL_URL" | sh -s -- --yes || {
        log_error "Starship script installation failed"
        return 1
    }
    
    # Add ~/.local/bin to PATH if not already there (where Starship installs by default)
    local local_bin="$HOME/.local/bin"
    if [[ -d "$local_bin" ]] && [[ ":$PATH:" != *":$local_bin:"* ]]; then
        export PATH="$local_bin:$PATH"
    fi
}

# Configure Starship with dotfiles
configure_starship() {
    log_info "Configuring Starship..."
    
    [[ ! -f "$STARSHIP_CONFIG_SOURCE" ]] && { log_error "Missing $STARSHIP_CONFIG_SOURCE"; return 1; }
    
    # Create configuration directory
    mkdir -p "$(dirname "$STARSHIP_CONFIG_TARGET")"
    
    # Create symlink for starship.toml
    log_info "Creating symlink for Starship configuration..."
    create_symlink "$STARSHIP_CONFIG_SOURCE" "$STARSHIP_CONFIG_TARGET"
    
    log_success "Starship configuration completed"
}

# Validate Starship installation
validate_starship_installation() {
    log_info "Validating Starship installation..."
    
    command -v starship >/dev/null || { log_error "Starship not found"; return 1; }
    
    [[ -f "$STARSHIP_CONFIG_TARGET" ]] || log_warn "Starship configuration file not found: $STARSHIP_CONFIG_TARGET"
    
    log_success "Starship validation passed"
}

# Test Starship prompt rendering
test_starship_prompt() {
    log_info "Testing Starship prompt..."
    
    # Test prompt generation
    if test_output=$(starship prompt 2>/dev/null); then
        log_debug "Prompt preview: ${test_output:0:60}..."
        log_success "Starship prompt test successful"
    else
        log_warn "Prompt test failed (may still work in shell)"
    fi
}

#######################################
# Main Installation Function
#######################################

# Main Starship installation function
install_starship() {
    log_section "Installing Starship Cross-Shell Prompt"
    
    install_starship_binary || return 1
    configure_starship || return 1
    
    validate_starship_installation
    
    ask_yes_no "Test Starship prompt?" "y" && test_starship_prompt
    
    log_success "Starship setup complete — restart your shell to see it"
}

# Uninstall Starship (for testing/cleanup)
uninstall_starship() {
    log_info "Uninstalling Starship..."
    
    local distro
    distro=$(get_distro)
    
    # Remove binary
    case "$distro" in
        "arch")
            if pacman -Qi starship >/dev/null 2>&1; then
                sudo pacman -Rns --noconfirm starship 2>/dev/null || true
            fi
            ;;
        "ubuntu"|*)
            # Remove manually installed binary
            if [[ -f "$HOME/.local/bin/starship" ]]; then
                rm -f "$HOME/.local/bin/starship"
            fi
            if [[ -f "/usr/local/bin/starship" ]]; then
                sudo rm -f "/usr/local/bin/starship"
            fi
            ;;
    esac
    
    # Remove configuration
    if [[ -f "$STARSHIP_CONFIG_TARGET" ]]; then
        rm -f "$STARSHIP_CONFIG_TARGET"
        log_info "Starship configuration removed"
    fi
    
    log_success "Starship uninstalled"
    log_info "Remove any Starship lines from your shell configs if needed"
}

# Export essential functions
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && export -f install_starship