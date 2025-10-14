#!/usr/bin/env bash

# components/wm/hyprland.sh - Hyprland window manager installation and configuration
# This module handles the installation and configuration of Hyprland window manager
# with proper dotfiles integration, session setup, and cross-distribution support.

source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"
source "$CORE_DIR/logger.sh"
source "$CORE_DIR/common.sh"

# Component metadata
readonly HYPRLAND_COMPONENT_NAME="hyprland"
readonly HYPRLAND_CONFIG_SOURCE="$DOTFILES_DIR/hyprland/.config/hypr"
readonly HYPRLAND_CONFIG_TARGET="$HOME/.config/hypr"
readonly HYPRMOCHA_CONFIG_SOURCE="$DOTFILES_DIR/hyprmocha/.config/hypr"
readonly HYPRLOCK_CONFIG_SOURCE="$DOTFILES_DIR/hyprlock/.config/hypr"
readonly HYPRPAPER_CONFIG_SOURCE="$DOTFILES_DIR/hyprpaper/.config/hypr"

# Manual installation packages (not available in all repos or need source build)
declare -A HYPRLAND_MANUAL_PACKAGES=(
    ["arch"]=""  # Available in Arch repos, handled by main system
    ["ubuntu"]="hyprland"  # Ubuntu builds from source
)

# Dependencies for Ubuntu source build
declare -A HYPRLAND_BUILD_DEPS=(
    ["ubuntu"]="wayland-protocols libwayland-dev libxkbcommon-dev libegl1-mesa-dev libgles2-mesa-dev libdrm-dev libxkbcommon-x11-dev libxcb-composite0-dev libxcb-xfixes0-dev libxcb-xinput-dev libxcb-image0-dev libxcb-shm0-dev libxcb-util-dev libxcb-keysyms1-dev libpixman-1-dev libcairo2-dev libpango1.0-dev"
)

# Additional tools for Ubuntu (others handled by main system)
declare -A HYPRLAND_UBUNTU_TOOLS=(
    ["ubuntu"]="grim slurp wl-clipboard"  # hyprpaper, hypridle, hyprlock built from source
)

#######################################
# Hyprland Installation Functions
#######################################

# Check if Hyprland is already installed
is_hyprland_installed() {
    command -v Hyprland >/dev/null 2>&1
}



# Build and install Hyprland from source for Ubuntu
install_hyprland_ubuntu() {
    log_info "Building Hyprland from source for Ubuntu..."
    
    # Install build dependencies
    log_info "Installing build dependencies..."
    local deps
    read -ra deps <<< "${HYPRLAND_BUILD_DEPS[ubuntu]}"
    
    for dep in "${deps[@]}"; do
        if ! install_package "$dep"; then
            log_error "Failed to install build dependency: $dep"
            return 1
        fi
    done
    
    # Install additional build tools
    local build_tools="build-essential cmake meson ninja-build pkg-config"
    read -ra tools <<< "$build_tools"
    
    for tool in "${tools[@]}"; do
        if ! install_package "$tool"; then
            log_error "Failed to install build tool: $tool"
            return 1
        fi
    done
    
    # Create build directory
    local build_dir="$HOME/.local/src/hyprland-build"
    mkdir -p "$build_dir"
    
    # Clone Hyprland repository
    log_info "Cloning Hyprland repository..."
    if [[ -d "$build_dir/Hyprland" ]]; then
        log_info "Hyprland repository already exists, updating..."
        if ! git -C "$build_dir/Hyprland" pull --quiet; then
            log_warn "Failed to update Hyprland repository, using existing version"
        fi
    else
        if ! git clone --recursive https://github.com/hyprwm/Hyprland.git "$build_dir/Hyprland"; then
            log_error "Failed to clone Hyprland repository"
            return 1
        fi
    fi
    
    # Build Hyprland
    log_info "Building Hyprland (this may take several minutes)..."
    cd "$build_dir/Hyprland" || return 1
    
    if ! make all; then
        log_error "Failed to build Hyprland"
        return 1
    fi
    
    # Install Hyprland
    log_info "Installing Hyprland..."
    if ! sudo make install; then
        log_error "Failed to install Hyprland"
        return 1
    fi
    
    # Install additional tools
    local tools
    read -ra tools <<< "${HYPRLAND_UBUNTU_TOOLS[ubuntu]}"
    
    for tool in "${tools[@]}"; do
        if ! install_package "$tool"; then
            log_warn "Failed to install Hyprland tool: $tool (continuing anyway)"
        fi
    done
    
    log_success "Hyprland built and installed successfully for Ubuntu"
    return 0
}

# Install manual Hyprland packages (Ubuntu source build)
install_hyprland_manual_packages() {
    local distro
    distro=$(get_distro)
    
    if [[ -z "${HYPRLAND_MANUAL_PACKAGES[$distro]}" ]]; then
        log_info "No manual packages needed for $distro"
        return 0
    fi
    
    case "$distro" in
        "ubuntu")
            install_hyprland_ubuntu
            ;;
        *)
            log_warn "Manual package installation not implemented for: $distro"
            ;;
    esac
}

# Configure Hyprland with dotfiles
configure_hyprland() {
    log_info "Configuring Hyprland window manager..."
    
    if [[ ! -d "$HYPRLAND_CONFIG_SOURCE" ]]; then
        log_error "Hyprland configuration source not found: $HYPRLAND_CONFIG_SOURCE"
        return 1
    fi
    
    # Create configuration directory
    if ! mkdir -p "$HYPRLAND_CONFIG_TARGET"; then
        log_error "Failed to create Hyprland config directory: $HYPRLAND_CONFIG_TARGET"
        return 1
    fi
    
    # Copy main Hyprland configuration files
    log_info "Creating symlinks for Hyprland configuration files..."
    
    # Main Hyprland configs
    while IFS= read -r -d '' config_file; do
        local relative_path="${config_file#$HYPRLAND_CONFIG_SOURCE/}"
        local target_file="$HYPRLAND_CONFIG_TARGET/$relative_path"
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
    done < <(find "$HYPRLAND_CONFIG_SOURCE" -type f -print0)
    
    # Copy Hyprmocha theme configuration
    if [[ -d "$HYPRMOCHA_CONFIG_SOURCE" ]]; then
        log_info "Installing Hyprmocha theme configuration..."
        while IFS= read -r -d '' config_file; do
            local relative_path="${config_file#$HYPRMOCHA_CONFIG_SOURCE/}"
            local target_file="$HYPRLAND_CONFIG_TARGET/$relative_path"
            local target_dir
            target_dir=$(dirname "$target_file")
            
            # Create target directory if needed
            if [[ ! -d "$target_dir" ]]; then
                mkdir -p "$target_dir"
            fi
            
            # Create symlink
            if ! create_symlink "$config_file" "$target_file"; then
                log_warn "Failed to create symlink for Hyprmocha: $relative_path"
            else
                log_debug "Created Hyprmocha symlink: $target_file -> $config_file"
            fi
        done < <(find "$HYPRMOCHA_CONFIG_SOURCE" -type f -print0)
    fi
    
    # Copy Hyprlock configuration
    if [[ -d "$HYPRLOCK_CONFIG_SOURCE" ]]; then
        log_info "Installing Hyprlock configuration..."
        while IFS= read -r -d '' config_file; do
            local relative_path="${config_file#$HYPRLOCK_CONFIG_SOURCE/}"
            local target_file="$HYPRLAND_CONFIG_TARGET/$relative_path"
            local target_dir
            target_dir=$(dirname "$target_file")
            
            # Create target directory if needed
            if [[ ! -d "$target_dir" ]]; then
                mkdir -p "$target_dir"
            fi
            
            # Create symlink
            if ! create_symlink "$config_file" "$target_file"; then
                log_warn "Failed to create symlink for Hyprlock: $relative_path"
            else
                log_debug "Created Hyprlock symlink: $target_file -> $config_file"
            fi
        done < <(find "$HYPRLOCK_CONFIG_SOURCE" -type f -print0)
    fi
    
    # Copy Hyprpaper configuration
    if [[ -d "$HYPRPAPER_CONFIG_SOURCE" ]]; then
        log_info "Installing Hyprpaper configuration..."
        while IFS= read -r -d '' config_file; do
            local relative_path="${config_file#$HYPRPAPER_CONFIG_SOURCE/}"
            local target_file="$HYPRLAND_CONFIG_TARGET/$relative_path"
            local target_dir
            target_dir=$(dirname "$target_file")
            
            # Create target directory if needed
            if [[ ! -d "$target_dir" ]]; then
                mkdir -p "$target_dir"
            fi
            
            # Create symlink
            if ! create_symlink "$config_file" "$target_file"; then
                log_warn "Failed to create symlink for Hyprpaper: $relative_path"
            else
                log_debug "Created Hyprpaper symlink: $target_file -> $config_file"
            fi
        done < <(find "$HYPRPAPER_CONFIG_SOURCE" -type f -print0)
    fi
    
    # Setup wallpapers directory
    setup_hyprland_wallpapers
    
    log_success "Hyprland configuration completed"
    return 0
}

# Setup wallpapers for Hyprland
setup_hyprland_wallpapers() {
    local wallpapers_source="$DOTFILES_DIR/backgrounds/.config/backgrounds"
    local wallpapers_target="$HOME/.config/backgrounds"
    
    if [[ -d "$wallpapers_source" ]]; then
        log_info "Setting up wallpapers directory..."
        if ! create_symlink "$wallpapers_source" "$wallpapers_target"; then
            log_warn "Failed to create wallpapers symlink"
        else
            log_debug "Created wallpapers symlink: $wallpapers_target -> $wallpapers_source"
        fi
    else
        log_warn "Wallpapers source directory not found: $wallpapers_source"
    fi
    
    return 0
}

# Setup Hyprland session files
setup_hyprland_session() {
    log_info "Setting up Hyprland session files..."
    
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
            log_success "Created Hyprland session file"
        fi
    fi
    
    return 0
}

# Validate Hyprland installation
validate_hyprland_installation() {
    log_info "Validating Hyprland installation..."
    
    # Check if binary is available
    if ! command -v Hyprland >/dev/null 2>&1; then
        log_error "Hyprland binary not found in PATH"
        return 1
    fi
    
    # Check if configuration exists
    if [[ ! -f "$HYPRLAND_CONFIG_TARGET/hyprland.conf" ]]; then
        log_error "Hyprland configuration file not found: $HYPRLAND_CONFIG_TARGET/hyprland.conf"
        return 1
    fi
    
    # Test Hyprland version (basic functionality test)
    if ! Hyprland --version >/dev/null 2>&1; then
        log_error "Hyprland version check failed"
        return 1
    fi
    
    # Check for additional configuration files
    local config_files=("hypridle.conf" "hyprlock.conf" "hyprpaper.conf" "mocha.conf")
    for config_file in "${config_files[@]}"; do
        if [[ -f "$HYPRLAND_CONFIG_TARGET/$config_file" ]]; then
            log_debug "Found Hyprland config: $config_file"
        else
            log_warn "Hyprland config not found: $config_file"
        fi
    done
    
    log_success "Hyprland installation validation passed"
    return 0
}

#######################################
# Main Installation Function
#######################################

# Main Hyprland installation function
install_hyprland() {
    log_section "Configuring Hyprland Window Manager"
    
    local distro
    distro=$(get_distro)
    
    # For Arch, check if already installed (packages should be installed by main system)
    # For Ubuntu, we need to build from source
    if [[ "$distro" == "arch" ]]; then
        if ! is_hyprland_installed; then
            log_error "Hyprland not found. Ensure packages are installed by the main system first."
            return 1
        fi
    fi
    
    # Validate distribution support
    if [[ "$distro" != "arch" && "$distro" != "ubuntu" ]]; then
        log_error "Hyprland installation not supported on: $distro"
        return 1
    fi
    
    # Install manual packages if needed (Ubuntu source build)
    if ! install_hyprland_manual_packages; then
        log_error "Failed to install manual Hyprland packages"
        return 1
    fi
    
    # Configure Hyprland
    if ! configure_hyprland; then
        log_error "Failed to configure Hyprland"
        return 1
    fi
    
    # Setup session files
    if ! setup_hyprland_session; then
        log_error "Failed to setup Hyprland session"
        return 1
    fi
    
    # Validate installation
    if ! validate_hyprland_installation; then
        log_error "Hyprland installation validation failed"
        return 1
    fi
    
    log_success "Hyprland configuration completed successfully"
    log_info "Note: Log out and select Hyprland from your display manager to use it"
    return 0
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
    
    # Remove configuration (with backup)
    if [[ -d "$HYPRLAND_CONFIG_TARGET" ]]; then
        local backup_dir="$HOME/.config/install-backups/hyprland-$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$(dirname "$backup_dir")"
        mv "$HYPRLAND_CONFIG_TARGET" "$backup_dir"
        log_info "Hyprland configuration backed up to: $backup_dir"
    fi
    
    log_success "Hyprland uninstalled successfully"
    return 0
}

# Export essential functions
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && export -f install_hyprland configure_hyprland is_hyprland_installed