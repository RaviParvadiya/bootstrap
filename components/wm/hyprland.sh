#!/usr/bin/env bash
#
# components/wm/hyprland.sh - Hyprland window manager installation and configuration
# Handles package installation, dotfile setup, session integration, and validation.

source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"
source "$CORE_DIR/logger.sh"
source "$CORE_DIR/common.sh"

# Component metadata
readonly HYPRLAND_CONFIG_TARGET="$HOME/.config/hypr"

# Package definitions per distribution
declare -A HYPRLAND_PACKAGES=(
    ["arch"]="hyprland xdg-desktop-portal-hyprland"
    ["ubuntu"]=""  # Ubuntu builds from source
)

# Dependencies for Hyprland
declare -A HYPRLAND_DEPS=(
    ["arch"]="wayland wlroots"
    ["ubuntu"]="wayland-protocols libwayland-dev libxkbcommon-dev libegl1-mesa-dev libgles2-mesa-dev libdrm-dev libxkbcommon-x11-dev libxcb-composite0-dev libxcb-xfixes0-dev libxcb-xinput-dev libxcb-image0-dev libxcb-shm0-dev libxcb-util-dev libxcb-keysyms1-dev libpixman-1-dev libcairo2-dev libpango1.0-dev"
)

# Additional tools for Hyprland ecosystem
declare -A HYPRLAND_TOOLS=(
    ["arch"]="hyprpaper hypridle hyprlock wl-clipboard"
    ["ubuntu"]="grim slurp wl-clipboard"  # hyprpaper, hypridle, hyprlock built from source
)

#######################################
# Hyprland Installation Functions
#######################################

# Install Hyprland packages for Arch Linux
install_hyprland_packages() {
    local distro=$(get_distro)
    log_info "Installing Hyprland for $distro..."
    
    if [[ "$distro" == "arch" ]]; then
        install_packages ${HYPRLAND_DEPS[$distro]} ${HYPRLAND_PACKAGES[$distro]} ${HYPRLAND_TOOLS[$distro]} || return 1
    elif [[ "$distro" == "ubuntu" ]]; then
        install_packages ${HYPRLAND_DEPS[$distro]} build-essential cmake meson ninja-build pkg-config || return 1
        build_hyprland_from_source || return 1
        install_packages ${HYPRLAND_TOOLS[$distro]} || log_warn "Some Hyprland tools may require manual build"
    else
        log_error "Hyprland installation not supported on: $distro"
        return 1
    fi

    log_success "Hyprland installed successfully"
}

# Build and install Hyprland from source for Ubuntu
build_hyprland_from_source() {
    log_info "Building Hyprland from source..."
    
    # Create build directory
    local src_dir="$HOME/.local/src/hyprland"
    mkdir -p "$src_dir"
    
    # Clone Hyprland repository
    if [[ -d "$src_dir/Hyprland" ]]; then
        git -C "$src_dir/Hyprland" pull --quiet || log_warn "Failed to update existing repo"
    else
        git clone --recursive https://github.com/hyprwm/Hyprland.git "$src_dir/Hyprland" || return 1
    fi
    
    cd "$src_dir/Hyprland" || return 1
    make all && sudo make install || { log_error "Hyprland build failed"; return 1; }
    
    log_success "Hyprland built and installed from source"
}

# Configure Hyprland with dotfiles
configure_hyprland() {
    # Stow main Hyprland configuration
    if [[ -d "$DOTFILES_DIR/hyprland" ]]; then
        log_info "Applying Hyprland configuration..."
        if ! (cd "$DOTFILES_DIR" && stow --target="$HOME" hyprland); then
            log_error "Failed to stow Hyprland configuration"
            return 1
        fi
    else
        log_error "Missing hyprland dotfiles directory: $DOTFILES_DIR/hyprland"
        return 1
    fi
    
    # Stow additional Hyprland components if they exist
    for component in hyprmocha hyprlock hyprpaper backgrounds; do
        if [[ -d "$DOTFILES_DIR/$component" ]]; then
            log_info "Applying $component configuration with stow..."
            (cd "$DOTFILES_DIR" && stow --target="$HOME" "$component") || log_warn "Failed to stow $component configuration"
        fi
    done
    
    log_success "Hyprland configuration applied"
}



# Setup Hyprland session files
setup_hyprland_session() {
    # Create desktop session file if it doesn't exist
    local session_file="/usr/share/wayland-sessions/hyprland.desktop"
    
    if [[ ! -f "$session_file" ]]; then
        log_info "Creating Hyprland session file..."
        
        local session_content="[Desktop Entry]
Name=Hyprland
Comment=An intelligent dynamic tiling Wayland compositor
Exec=Hyprland
Type=Application"
        
        if ! echo "$session_content" | sudo tee "$session_file" >/dev/null; then
            log_warn "Failed to create Hyprland session file"
        else
            log_success "Session file created: $session_file"
        fi
    fi
}

# Validate Hyprland installation
validate_hyprland_installation() {
    log_info "Validating Hyprland installation..."
    
    command -v Hyprland >/dev/null || { log_error "Hyprland not found in PATH"; return 1; }
    
    # Check if configuration exists
    [[ -f "$HYPRLAND_CONFIG_TARGET/hyprland.conf" ]] || log_warn "Main config missing: hyprland.conf"
    
    log_success "Hyprland validation passed"
}

#######################################
# Main Installation Function
#######################################

# Main Hyprland installation function
install_hyprland() {
    log_section "Installing Hyprland Window Manager"
    
    install_hyprland_packages || return 1
    configure_hyprland || return 1
    setup_hyprland_session
    validate_hyprland_installation
    
    log_success "Hyprland installation complete"
    log_info "➡ Log out and select 'Hyprland' in your display manager"
}

# Uninstall Hyprland (for testing/cleanup)
uninstall_hyprland() {
    log_info "Uninstalling Hyprland..."
    
    local distro
    distro=$(get_distro)
    
    # Remove packages
    case "$distro" in
        "arch")
            sudo pacman -Rns --noconfirm hyprland xdg-desktop-portal-hyprland 2>/dev/null || true
            ;;
        "ubuntu")
            # Remove built binaries
            sudo rm -f /usr/local/bin/Hyprland /usr/bin/Hyprland
            sudo rm -f /usr/share/wayland-sessions/hyprland.desktop
            ;;
    esac
    
    # Remove configuration
    if [[ -d "$HYPRLAND_CONFIG_TARGET" ]]; then
        rm -rf "$HYPRLAND_CONFIG_TARGET"
        log_info "Hyprland configuration removed"
    fi
    
    log_success "Hyprland uninstalled"
}

# Export essential functions
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && export -f install_hyprland