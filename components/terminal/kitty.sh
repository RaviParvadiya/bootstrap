#!/usr/bin/env bash
#
# components/terminal/kitty.sh - Kitty terminal emulator installation and configuration
# Handles Kitty installation, font dependencies, theme setup, and dotfile linking.

source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"
source "$CORE_DIR/logger.sh"
source "$CORE_DIR/common.sh"

# Component metadata
readonly KITTY_COMPONENT_NAME="kitty"
readonly KITTY_CONFIG_SOURCE="$DOTFILES_DIR/kitty/.config/kitty"
readonly KITTY_CONFIG_TARGET="$HOME/.config/kitty"
readonly CATPPUCCIN_URL="https://raw.githubusercontent.com/catppuccin/kitty/main/themes/mocha.conf"
readonly CATPPUCCIN_THEME="catppuccin-mocha.conf"

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

# Download and install Kitty themes
install_kitty_themes() {
    log_info "Installing Catppuccin Mocha theme..."
    
    local themes_dir="$KITTY_CONFIG_TARGET/themes"
    
    # Create themes directory
    mkdir -p "$themes_dir"
    
    local CATPPUCCIN_URL="https://raw.githubusercontent.com/catppuccin/kitty/main/themes/mocha.conf"
    local catppuccin_file="$themes_dir/$CATPPUCCIN_THEME"

    if check_internet; then
        if ! curl -fsSL "$CATPPUCCIN_URL" -o "$theme_file" 2>/dev/null && ! wget -q "$CATPPUCCIN_URL" -O "$theme_file" 2>/dev/null; then
            log_warn "Failed to download Catppuccin theme"
            return 0
        fi
        log_success "Downloaded Catppuccin Mocha theme"
    else
        log_warn "No internet; skipping theme download"
    fi

    return 0
}

# Configure Kitty with dotfiles
configure_kitty() {
    log_info "Configuring Kitty terminal emulator..."
    
    if [[ ! -d "$KITTY_CONFIG_SOURCE" ]]; then
        log_error "Kitty configuration source not found: $KITTY_CONFIG_SOURCE"
        return 1
    fi
    
    # Create configuration directory
    if ! mkdir -p "$KITTY_CONFIG_TARGET"; then
        log_error "Failed to create Kitty config directory: $KITTY_CONFIG_TARGET"
        return 1
    fi
    
    # Install themes first
    install_kitty_themes
    
    # Copy configuration files using symlinks for easy updates
    log_info "Creating symlinks for Kitty configuration files..."
    
    # Find all configuration files in the source directory
    while IFS= read -r -d '' config_file; do
        local relative_path="${config_file#$KITTY_CONFIG_SOURCE/}"
        local target_file="$KITTY_CONFIG_TARGET/$relative_path"
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
    done < <(find "$KITTY_CONFIG_SOURCE" -type f -print0)
    
    # Handle the current-theme.conf reference
    setup_kitty_theme_link
    
    log_success "Kitty configuration completed"
    return 0
}

# Setup theme symlink for current-theme.conf
setup_kitty_theme_link() {
    local current_theme_file="$KITTY_CONFIG_TARGET/current-theme.conf"
    local catppuccin_theme="$KITTY_CONFIG_TARGET/themes/$CATPPUCCIN_THEME"
    
    # If Catppuccin theme exists, link to it
    if [[ -f "$catppuccin_theme" ]]; then
        log_info "Linking current theme to Catppuccin Mocha..."
        if ! create_symlink "$catppuccin_theme" "$current_theme_file"; then
            log_warn "Failed to create theme symlink, theme may not work correctly"
        fi
    else
        log_warn "Catppuccin theme not found, current-theme.conf may not work"
    fi
    
    return 0
}

# Validate Kitty installation
validate_kitty_installation() {
    log_info "Validating Kitty installation..."
    
    # Check if binary is available
    command -v kitty >/dev/null || { log_error "Kitty not found"; return 1; }
    
    # Check if configuration exists
    [[ -f "$KITTY_CONFIG_TARGET/kitty.conf" ]] || log_warn "kitty.conf missing"
    
    # Check if theme configuration exists
    [[ -f "$KITTY_CONFIG_TARGET/current-theme.conf" ]] || log_warn "Theme not linked"
    
    log_success "Kitty validation passed"
    return 0
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
    
    # Remove configuration
    if [[ -d "$KITTY_CONFIG_TARGET" ]]; then
        rm -rf "$KITTY_CONFIG_TARGET"
        log_info "Kitty configuration removed"
    fi
    
    log_success "Kitty uninstalled"
}

# Export essential functions
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && export -f install_kitty