#!/usr/bin/env bash

# components/terminal/alacritty.sh - Alacritty terminal emulator installation and configuration
# This module handles the installation and configuration of Alacritty terminal emulator
# with proper dotfiles integration and cross-distribution support.

source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"
source "$CORE_DIR/logger.sh"
source "$CORE_DIR/common.sh"

# Component metadata
readonly ALACRITTY_COMPONENT_NAME="alacritty"
readonly ALACRITTY_CONFIG_SOURCE="$DOTFILES_DIR/alacritty/.config/alacritty"
readonly ALACRITTY_CONFIG_TARGET="$HOME/.config/alacritty"

#######################################
# Alacritty Installation Functions
#######################################

# Check if Alacritty is already installed
is_alacritty_installed() {
    command -v alacritty >/dev/null 2>&1
}

# Configure Alacritty with dotfiles
configure_alacritty() {
    log_info "Configuring Alacritty terminal emulator..."
    
    if [[ ! -d "$ALACRITTY_CONFIG_SOURCE" ]]; then
        log_error "Alacritty configuration source not found: $ALACRITTY_CONFIG_SOURCE"
        return 1
    fi
    
    # Create configuration directory
    if ! mkdir -p "$ALACRITTY_CONFIG_TARGET"; then
        log_error "Failed to create Alacritty config directory: $ALACRITTY_CONFIG_TARGET"
        return 1
    fi
    
    # Copy configuration files using symlinks for easy updates
    log_info "Creating symlinks for Alacritty configuration files..."
    
    # Find all configuration files in the source directory
    while IFS= read -r -d '' config_file; do
        local relative_path="${config_file#$ALACRITTY_CONFIG_SOURCE/}"
        local target_file="$ALACRITTY_CONFIG_TARGET/$relative_path"
        local target_dir
        target_dir=$(dirname "$target_file")
        
        # Create target directory if needed
        if [[ ! -d "$target_dir" ]]; then
            mkdir -p "$target_dir"
        fi
        
        # Create symlink
        if ! create_symlink "$config_file" "$target_file"; then
            log_warn "Failed to create symlink for: $relative_path"
        else
            log_debug "Created symlink: $target_file -> $config_file"
        fi
    done < <(find "$ALACRITTY_CONFIG_SOURCE" -type f -print0)
    
    log_success "Alacritty configuration completed"
    return 0
}

# Validate Alacritty installation
validate_alacritty_installation() {
    log_info "Validating Alacritty installation..."
    
    # Check if binary is available
    if ! command -v alacritty >/dev/null 2>&1; then
        log_error "Alacritty binary not found in PATH"
        return 1
    fi
    
    # Check if configuration exists
    if [[ ! -f "$ALACRITTY_CONFIG_TARGET/alacritty.toml" ]]; then
        log_warn "Alacritty configuration file not found: $ALACRITTY_CONFIG_TARGET/alacritty.toml"
    fi
    
    # Test Alacritty version (basic functionality test)
    if ! alacritty --version >/dev/null 2>&1; then
        log_error "Alacritty version check failed"
        return 1
    fi
    
    log_success "Alacritty installation validation passed"
    return 0
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
    if command -v xdg-settings >/dev/null 2>&1; then
        xdg-settings set default-terminal-emulator alacritty.desktop
    fi
    
    log_success "Alacritty set as default terminal"
    return 0
}

#######################################
# Main Installation Function
#######################################

# Main Alacritty installation function
install_alacritty() {
    log_section "Configuring Alacritty Terminal Emulator"
    
    # Check if already installed (packages should be installed by main system)
    if ! is_alacritty_installed; then
        log_error "Alacritty not found. Ensure packages are installed by the main system first."
        return 1
    fi
    
    # Configure Alacritty
    if ! configure_alacritty; then
        log_error "Failed to configure Alacritty"
        return 1
    fi
    
    # Validate installation
    if ! validate_alacritty_installation; then
        log_error "Alacritty installation validation failed"
        return 1
    fi
    
    # Ask if user wants to set as default
    if ask_yes_no "Set Alacritty as default terminal?" "n"; then
        set_alacritty_as_default
    fi
    
    log_success "Alacritty configuration completed successfully"
    return 0
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
    
    # Remove configuration (with backup)
    if [[ -d "$ALACRITTY_CONFIG_TARGET" ]]; then
        local backup_dir="$HOME/.config/install-backups/alacritty-$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$(dirname "$backup_dir")"
        mv "$ALACRITTY_CONFIG_TARGET" "$backup_dir"
        log_info "Alacritty configuration backed up to: $backup_dir"
    fi
    
    log_success "Alacritty uninstalled successfully"
    return 0
}

# Export essential functions
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && export -f install_alacritty configure_alacritty is_alacritty_installed