#!/usr/bin/env bash

# components/shell/starship.sh - Starship prompt installation and configuration
# This module handles the installation and configuration of Starship cross-shell prompt
# with proper dotfiles integration, theme support, and cross-distribution compatibility.

source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"
source "$CORE_DIR/logger.sh"
source "$CORE_DIR/common.sh"

# Component metadata
readonly STARSHIP_COMPONENT_NAME="starship"
readonly STARSHIP_CONFIG_SOURCE="$DOTFILES_DIR/starship/.config/starship.toml"
readonly STARSHIP_CONFIG_TARGET="$HOME/.config/starship.toml"
readonly STARSHIP_INSTALL_URL="https://starship.rs/install.sh"

# Package definitions per distribution (Starship is usually installed via script)
declare -A STARSHIP_PACKAGES=(
    ["arch"]="starship"  # Available in Arch repos
    ["ubuntu"]=""        # Not in Ubuntu repos, use install script
)

# Font dependencies for proper icon display
declare -A STARSHIP_FONT_PACKAGES=(
    ["arch"]="ttf-nerd-fonts-symbols ttf-jetbrains-mono-nerd"
    ["ubuntu"]="fonts-noto-color-emoji"
)

#######################################
# Starship Installation Functions
#######################################

# Check if Starship is already installed
is_starship_installed() {
    command -v starship >/dev/null 2>&1
}

# Install Starship via package manager (Arch) or install script (Ubuntu)
install_starship_binary() {
    local distro
    distro=$(get_distro)
    
    log_info "Installing Starship binary for $distro..."
    
    case "$distro" in
        "arch")
            # Install from official Arch repositories
            if [[ -n "${STARSHIP_PACKAGES[$distro]}" ]]; then
                if ! install_package "${STARSHIP_PACKAGES[$distro]}"; then
                    log_error "Failed to install Starship package"
                    return 1
                fi
            else
                log_warn "Starship package not available, falling back to install script"
                install_starship_via_script
            fi
            ;;
        "ubuntu")
            # Use official install script for Ubuntu
            install_starship_via_script
            ;;
        *)
            log_error "Starship installation not supported on: $distro"
            return 1
            ;;
    esac
    
    log_success "Starship binary installed successfully"
    return 0
}

# Install Starship via official install script
install_starship_via_script() {
    log_info "Installing Starship via official install script..."
    
    # Check internet connectivity
    if ! check_internet; then
        log_error "Internet connection required for Starship installation"
        return 1
    fi
    
    # Download and run install script
    if command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL "$STARSHIP_INSTALL_URL" | sh -s -- --yes; then
            log_error "Failed to install Starship via curl"
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -qO- "$STARSHIP_INSTALL_URL" | sh -s -- --yes; then
            log_error "Failed to install Starship via wget"
            return 1
        fi
    else
        log_error "Neither curl nor wget available for Starship installation"
        return 1
    fi
    
    # Add ~/.local/bin to PATH if not already there (where Starship installs by default)
    local local_bin="$HOME/.local/bin"
    if [[ -d "$local_bin" ]] && [[ ":$PATH:" != *":$local_bin:"* ]]; then
        log_info "Adding $local_bin to PATH for current session"
        export PATH="$local_bin:$PATH"
    fi
    
    return 0
}

# Install font dependencies for proper Starship display
install_starship_fonts() {
    local distro
    distro=$(get_distro)
    
    if [[ -z "${STARSHIP_FONT_PACKAGES[$distro]:-}" ]]; then
        log_info "No specific font packages defined for $distro"
        return 0
    fi
    
    log_info "Installing Starship font dependencies..."
    
    local font_packages
    read -ra font_packages <<< "${STARSHIP_FONT_PACKAGES[$distro]}"
    
    for font_package in "${font_packages[@]}"; do
        if ! install_package "$font_package"; then
            log_warn "Failed to install font package: $font_package (continuing anyway)"
        fi
    done
    
    log_success "Starship font dependencies installed"
    return 0
}

# Configure Starship with dotfiles
configure_starship() {
    log_info "Configuring Starship prompt..."
    
    if [[ ! -f "$STARSHIP_CONFIG_SOURCE" ]]; then
        log_error "Starship configuration source not found: $STARSHIP_CONFIG_SOURCE"
        return 1
    fi
    
    # Create configuration directory
    local config_dir
    config_dir=$(dirname "$STARSHIP_CONFIG_TARGET")
    if ! mkdir -p "$config_dir"; then
        log_error "Failed to create Starship config directory: $config_dir"
        return 1
    fi
    
    # Create symlink for starship.toml
    log_info "Creating symlink for Starship configuration..."
    if ! create_symlink "$STARSHIP_CONFIG_SOURCE" "$STARSHIP_CONFIG_TARGET"; then
        log_error "Failed to create Starship configuration symlink"
        return 1
    fi
    
    log_success "Starship configuration completed"
    return 0
}

# Add Starship initialization to shell configuration files
setup_starship_shell_integration() {
    log_info "Setting up Starship shell integration..."
    
    local shells_configured=0
    
    # Bash integration
    if [[ -f "$HOME/.bashrc" ]]; then
        if ! grep -q "starship init bash" "$HOME/.bashrc" 2>/dev/null; then
            log_info "Adding Starship initialization to .bashrc..."
            echo "" >> "$HOME/.bashrc"
            echo "# Starship prompt" >> "$HOME/.bashrc"
            echo 'eval "$(starship init bash)"' >> "$HOME/.bashrc"
            ((shells_configured++))
        else
            log_debug "Starship already configured in .bashrc"
        fi
    fi
    
    # Zsh integration (note: this is handled by the zsh dotfile, but we check anyway)
    if [[ -f "$HOME/.zshrc" ]]; then
        if ! grep -q "starship init zsh" "$HOME/.zshrc" 2>/dev/null; then
            log_info "Note: Zsh integration should be handled by Zsh dotfiles"
            log_debug "Starship init should be in the Zsh configuration"
        else
            log_debug "Starship already configured in .zshrc"
            ((shells_configured++))
        fi
    fi
    
    # Fish integration (if fish is installed)
    if command -v fish >/dev/null 2>&1; then
        local fish_config="$HOME/.config/fish/config.fish"
        if [[ -f "$fish_config" ]]; then
            if ! grep -q "starship init fish" "$fish_config" 2>/dev/null; then
                log_info "Adding Starship initialization to Fish config..."
                mkdir -p "$(dirname "$fish_config")"
                echo "" >> "$fish_config"
                echo "# Starship prompt" >> "$fish_config"
                echo "starship init fish | source" >> "$fish_config"
                ((shells_configured++))
            else
                log_debug "Starship already configured in Fish"
            fi
        fi
    fi
    
    if [[ $shells_configured -gt 0 ]]; then
        log_success "Starship shell integration configured for $shells_configured shell(s)"
    else
        log_info "No additional shell integration needed"
    fi
    
    return 0
}

# Validate Starship installation
validate_starship_installation() {
    log_info "Validating Starship installation..."
    
    # Check if binary is available
    if ! command -v starship >/dev/null 2>&1; then
        log_error "Starship binary not found in PATH"
        return 1
    fi
    
    # Check if configuration exists
    if [[ ! -f "$STARSHIP_CONFIG_TARGET" ]]; then
        log_warn "Starship configuration file not found: $STARSHIP_CONFIG_TARGET"
    fi
    
    # Test Starship version (basic functionality test)
    if ! starship --version >/dev/null 2>&1; then
        log_error "Starship version check failed"
        return 1
    fi
    
    # Test configuration validity
    if [[ -f "$STARSHIP_CONFIG_TARGET" ]]; then
        if ! starship config 2>/dev/null | grep -q "starship" 2>/dev/null; then
            log_warn "Starship configuration may have issues"
        else
            log_debug "Starship configuration appears valid"
        fi
    fi
    
    log_success "Starship installation validation passed"
    return 0
}

# Test Starship prompt rendering
test_starship_prompt() {
    log_info "Testing Starship prompt rendering..."
    
    # Test prompt generation
    if command -v starship >/dev/null 2>&1; then
        local test_output
        if test_output=$(starship prompt 2>/dev/null); then
            log_success "Starship prompt test successful"
            log_debug "Prompt preview: ${test_output:0:50}..."
        else
            log_warn "Starship prompt test failed (may work in actual shell)"
        fi
    else
        log_error "Starship binary not available for testing"
        return 1
    fi
    
    return 0
}

#######################################
# Main Installation Function
#######################################

# Main Starship installation function
install_starship() {
    log_section "Installing Starship Cross-Shell Prompt"
    
    # Check if already installed
    if is_starship_installed; then
        log_info "Starship is already installed"
        if ! ask_yes_no "Do you want to reconfigure Starship?" "n"; then
            log_info "Skipping Starship installation"
            return 0
        fi
    fi
    
    # Validate distribution support
    local distro
    distro=$(get_distro)
    
    # Install font dependencies first
    if ! install_starship_fonts; then
        log_warn "Failed to install font dependencies (continuing anyway)"
    fi
    
    # Install Starship binary
    if ! install_starship_binary; then
        log_error "Failed to install Starship binary"
        return 1
    fi
    
    # Configure Starship
    if ! configure_starship; then
        log_error "Failed to configure Starship"
        return 1
    fi
    
    # Setup shell integration
    if ! setup_starship_shell_integration; then
        log_warn "Failed to setup shell integration (you may need to configure manually)"
    fi
    
    # Validate installation
    if ! validate_starship_installation; then
        log_error "Starship installation validation failed"
        return 1
    fi
    
    # Test prompt rendering
    if ask_yes_no "Test Starship prompt rendering?" "y"; then
        test_starship_prompt
    fi
    
    log_success "Starship installation completed successfully"
    log_info "Note: Restart your shell or source your shell config to see the new prompt"
    return 0
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
    
    # Remove configuration (with backup)
    if [[ -f "$STARSHIP_CONFIG_TARGET" ]]; then
        local backup_dir="$HOME/.config/install-backups"
        mkdir -p "$backup_dir"
        mv "$STARSHIP_CONFIG_TARGET" "$backup_dir/starship-$(date +%Y%m%d_%H%M%S).toml"
        log_info "Starship configuration backed up to: $backup_dir"
    fi
    
    log_success "Starship uninstalled successfully"
    log_info "Note: You may need to remove Starship initialization from your shell configs"
    return 0
}

# Export essential functions
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && export -f install_starship configure_starship is_starship_installed