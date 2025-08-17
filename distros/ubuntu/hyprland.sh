#!/bin/bash

# Ubuntu Hyprland Installation
# Handles building and configuring Hyprland from source on Ubuntu

# Source core utilities
source "$(dirname "${BASH_SOURCE[0]}")/../../core/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../core/logger.sh"

# Main Hyprland installation function
ubuntu_install_hyprland() {
    log_info "Installing Hyprland on Ubuntu..."
    
    # Install build dependencies
    if ! ubuntu_install_hyprland_dependencies; then
        log_error "Failed to install Hyprland dependencies"
        return 1
    fi
    
    # Build and install Hyprland
    if ! ubuntu_build_hyprland; then
        log_error "Failed to build Hyprland"
        return 1
    fi
    
    # Install additional Wayland tools
    if ! ubuntu_install_wayland_tools; then
        log_error "Failed to install Wayland tools"
        return 1
    fi
    
    # Configure Hyprland session
    if ! ubuntu_configure_hyprland_session; then
        log_error "Failed to configure Hyprland session"
        return 1
    fi
    
    log_success "Hyprland installation completed"
    return 0
}

# Install Hyprland build dependencies
ubuntu_install_hyprland_dependencies() {
    log_info "Installing Hyprland build dependencies..."
    
    local dependencies=(
        # Build tools
        "build-essential"
        "cmake"
        "meson"
        "ninja-build"
        "pkg-config"
        "git"
        
        # Wayland development libraries
        "libwayland-dev"
        "wayland-protocols"
        "libwlroots-dev"
        
        # Graphics and input libraries
        "libegl1-mesa-dev"
        "libgles2-mesa-dev"
        "libdrm-dev"
        "libxkbcommon-dev"
        "libxkbcommon-x11-dev"
        "libpixman-1-dev"
        "libcairo2-dev"
        "libpango1.0-dev"
        "libinput-dev"
        
        # X11 compatibility libraries
        "libxcb1-dev"
        "libxcb-composite0-dev"
        "libxcb-ewmh-dev"
        "libxcb-icccm4-dev"
        "libxcb-image0-dev"
        "libxcb-render-util0-dev"
        "libxcb-xfixes0-dev"
        "libxcb-xinput-dev"
        
        # Additional libraries
        "libtomlplusplus-dev"
        "libzip-dev"
        "librsvg2-dev"
        "libmagic-dev"
        
        # Hyprland-specific dependencies
        "libhyprlang-dev"
        "libhyprutils-dev"
        "libaquamarine-dev"
        
        # Session management
        "seatd"
        "libseat-dev"
    )
    
    # Install dependencies via APT
    source "$(dirname "${BASH_SOURCE[0]}")/packages.sh"
    ubuntu_install_apt_packages "${dependencies[@]}"
}

# Build Hyprland from source
ubuntu_build_hyprland() {
    log_info "Building Hyprland from source..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would build Hyprland from source"
        return 0
    fi
    
    # Create build directory
    local build_dir="$HOME/.local/src"
    mkdir -p "$build_dir"
    
    # Clone Hyprland repository
    local hyprland_dir="$build_dir/Hyprland"
    
    if [[ -d "$hyprland_dir" ]]; then
        log_info "Updating existing Hyprland repository..."
        (cd "$hyprland_dir" && git pull)
    else
        log_info "Cloning Hyprland repository..."
        git clone --recursive https://github.com/hyprwm/Hyprland.git "$hyprland_dir"
    fi
    
    # Build Hyprland
    log_info "Compiling Hyprland (this may take a while)..."
    (
        cd "$hyprland_dir" || exit 1
        
        # Configure build
        meson setup build --buildtype=release
        
        # Compile
        ninja -C build
        
        # Install
        sudo ninja -C build install
    )
    
    local build_result=$?
    
    if [[ $build_result -ne 0 ]]; then
        log_error "Hyprland build failed"
        return 1
    fi
    
    log_success "Hyprland built and installed successfully"
    return 0
}

# Install additional Wayland tools
ubuntu_install_wayland_tools() {
    log_info "Installing additional Wayland tools..."
    
    local wayland_tools=(
        # Screenshot and screen recording
        "grim"
        "slurp"
        "wf-recorder"
        
        # Clipboard
        "wl-clipboard"
        
        # Notification daemon
        "mako-notifier"
        
        # Application launcher
        "wofi"
        
        # Status bar
        "waybar"
        
        # Terminal emulator
        "foot"
        
        # File manager
        "thunar"
        
        # Image viewer
        "imv"
        
        # PDF viewer
        "zathura"
        
        # Desktop portal
        "xdg-desktop-portal-wlr"
        "xdg-desktop-portal-gtk"
        
        # Polkit agent
        "polkit-kde-agent-1"
        
        # Network manager applet
        "network-manager-gnome"
        
        # Audio control
        "pavucontrol"
        
        # Brightness control
        "brightnessctl"
    )
    
    source "$(dirname "${BASH_SOURCE[0]}")/packages.sh"
    ubuntu_install_apt_packages "${wayland_tools[@]}"
}

# Configure Hyprland session
ubuntu_configure_hyprland_session() {
    log_info "Configuring Hyprland session..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would configure Hyprland session"
        return 0
    fi
    
    # Create Hyprland desktop entry
    local desktop_entry="/usr/share/wayland-sessions/hyprland.desktop"
    
    sudo tee "$desktop_entry" >/dev/null << 'EOF'
[Desktop Entry]
Name=Hyprland
Comment=An intelligent dynamic tiling Wayland compositor
Exec=Hyprland
Type=Application
EOF
    
    # Create Hyprland wrapper script for proper session setup
    local wrapper_script="/usr/local/bin/hyprland-session"
    
    sudo tee "$wrapper_script" >/dev/null << 'EOF'
#!/bin/bash

# Hyprland session wrapper script

# Set environment variables for Wayland
export XDG_SESSION_TYPE=wayland
export XDG_SESSION_DESKTOP=Hyprland
export XDG_CURRENT_DESKTOP=Hyprland

# NVIDIA specific settings (if NVIDIA GPU is present)
if lspci | grep -i nvidia >/dev/null 2>&1; then
    export LIBVA_DRIVER_NAME=nvidia
    export XDG_SESSION_TYPE=wayland
    export GBM_BACKEND=nvidia-drm
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export WLR_NO_HARDWARE_CURSORS=1
fi

# Intel specific settings
if lspci | grep -i "intel.*graphics" >/dev/null 2>&1; then
    export LIBVA_DRIVER_NAME=i965
fi

# AMD specific settings
if lspci | grep -i "amd\|ati" >/dev/null 2>&1; then
    export LIBVA_DRIVER_NAME=radeonsi
fi

# Start Hyprland
exec Hyprland "$@"
EOF
    
    sudo chmod +x "$wrapper_script"
    
    # Update desktop entry to use wrapper script
    sudo sed -i 's|Exec=Hyprland|Exec=/usr/local/bin/hyprland-session|' "$desktop_entry"
    
    # Configure environment for Hyprland
    ubuntu_configure_hyprland_environment
    
    log_success "Hyprland session configured"
    return 0
}

# Configure Hyprland environment
ubuntu_configure_hyprland_environment() {
    log_info "Configuring Hyprland environment..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would configure Hyprland environment"
        return 0
    fi
    
    # Create environment configuration file
    local env_file="/etc/environment.d/hyprland.conf"
    
    sudo mkdir -p "$(dirname "$env_file")"
    sudo tee "$env_file" >/dev/null << 'EOF'
# Hyprland environment variables
XDG_SESSION_TYPE=wayland
XDG_SESSION_DESKTOP=Hyprland
XDG_CURRENT_DESKTOP=Hyprland

# Wayland specific
WAYLAND_DISPLAY=wayland-1
QT_QPA_PLATFORM=wayland
GDK_BACKEND=wayland
SDL_VIDEODRIVER=wayland
CLUTTER_BACKEND=wayland

# Qt scaling
QT_AUTO_SCREEN_SCALE_FACTOR=1
QT_WAYLAND_DISABLE_WINDOWDECORATION=1

# Java applications
_JAVA_AWT_WM_NONREPARENTING=1

# Firefox
MOZ_ENABLE_WAYLAND=1
EOF
    
    # Configure user-specific environment
    local user_env_dir="$HOME/.config/environment.d"
    mkdir -p "$user_env_dir"
    
    cp "/etc/environment.d/hyprland.conf" "$user_env_dir/"
    
    log_success "Hyprland environment configured"
}

# Install Hyprland ecosystem tools
ubuntu_install_hyprland_ecosystem() {
    log_info "Installing Hyprland ecosystem tools..."
    
    # Install hyprpaper (wallpaper daemon)
    ubuntu_build_hyprpaper
    
    # Install hypridle (idle daemon)
    ubuntu_build_hypridle
    
    # Install hyprlock (screen locker)
    ubuntu_build_hyprlock
    
    # Install hyprpicker (color picker)
    ubuntu_build_hyprpicker
}

# Build hyprpaper
ubuntu_build_hyprpaper() {
    log_info "Building hyprpaper..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would build hyprpaper"
        return 0
    fi
    
    local build_dir="$HOME/.local/src"
    local hyprpaper_dir="$build_dir/hyprpaper"
    
    if [[ -d "$hyprpaper_dir" ]]; then
        (cd "$hyprpaper_dir" && git pull)
    else
        git clone https://github.com/hyprwm/hyprpaper.git "$hyprpaper_dir"
    fi
    
    (
        cd "$hyprpaper_dir" || exit 1
        meson setup build --buildtype=release
        ninja -C build
        sudo ninja -C build install
    )
    
    log_success "hyprpaper installed"
}

# Build hypridle
ubuntu_build_hypridle() {
    log_info "Building hypridle..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would build hypridle"
        return 0
    fi
    
    local build_dir="$HOME/.local/src"
    local hypridle_dir="$build_dir/hypridle"
    
    if [[ -d "$hypridle_dir" ]]; then
        (cd "$hypridle_dir" && git pull)
    else
        git clone https://github.com/hyprwm/hypridle.git "$hypridle_dir"
    fi
    
    (
        cd "$hypridle_dir" || exit 1
        meson setup build --buildtype=release
        ninja -C build
        sudo ninja -C build install
    )
    
    log_success "hypridle installed"
}

# Build hyprlock
ubuntu_build_hyprlock() {
    log_info "Building hyprlock..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would build hyprlock"
        return 0
    fi
    
    local build_dir="$HOME/.local/src"
    local hyprlock_dir="$build_dir/hyprlock"
    
    if [[ -d "$hyprlock_dir" ]]; then
        (cd "$hyprlock_dir" && git pull)
    else
        git clone https://github.com/hyprwm/hyprlock.git "$hyprlock_dir"
    fi
    
    (
        cd "$hyprlock_dir" || exit 1
        meson setup build --buildtype=release
        ninja -C build
        sudo ninja -C build install
    )
    
    log_success "hyprlock installed"
}

# Build hyprpicker
ubuntu_build_hyprpicker() {
    log_info "Building hyprpicker..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would build hyprpicker"
        return 0
    fi
    
    local build_dir="$HOME/.local/src"
    local hyprpicker_dir="$build_dir/hyprpicker"
    
    if [[ -d "$hyprpicker_dir" ]]; then
        (cd "$hyprpicker_dir" && git pull)
    else
        git clone https://github.com/hyprwm/hyprpicker.git "$hyprpicker_dir"
    fi
    
    (
        cd "$hyprpicker_dir" || exit 1
        meson setup build --buildtype=release
        ninja -C build
        sudo ninja -C build install
    )
    
    log_success "hyprpicker installed"
}

# Check if Hyprland is installed
ubuntu_is_hyprland_installed() {
    command -v Hyprland >/dev/null 2>&1
}

# Get Hyprland version
ubuntu_get_hyprland_version() {
    if ubuntu_is_hyprland_installed; then
        Hyprland --version 2>/dev/null | head -n1
    else
        echo "Not installed"
    fi
}

# Uninstall Hyprland
ubuntu_uninstall_hyprland() {
    log_info "Uninstalling Hyprland..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would uninstall Hyprland"
        return 0
    fi
    
    # Remove desktop entry
    sudo rm -f /usr/share/wayland-sessions/hyprland.desktop
    
    # Remove wrapper script
    sudo rm -f /usr/local/bin/hyprland-session
    
    # Remove environment configuration
    sudo rm -f /etc/environment.d/hyprland.conf
    rm -f "$HOME/.config/environment.d/hyprland.conf"
    
    # Remove build directories (optional)
    if ask_yes_no "Remove Hyprland source code directories?"; then
        rm -rf "$HOME/.local/src/Hyprland"
        rm -rf "$HOME/.local/src/hyprpaper"
        rm -rf "$HOME/.local/src/hypridle"
        rm -rf "$HOME/.local/src/hyprlock"
        rm -rf "$HOME/.local/src/hyprpicker"
    fi
    
    log_success "Hyprland uninstalled"
}

# Export functions for external use
export -f ubuntu_install_hyprland
export -f ubuntu_install_hyprland_dependencies
export -f ubuntu_build_hyprland
export -f ubuntu_install_wayland_tools
export -f ubuntu_configure_hyprland_session
export -f ubuntu_configure_hyprland_environment
export -f ubuntu_install_hyprland_ecosystem
export -f ubuntu_build_hyprpaper
export -f ubuntu_build_hypridle
export -f ubuntu_build_hyprlock
export -f ubuntu_build_hyprpicker
export -f ubuntu_is_hyprland_installed
export -f ubuntu_get_hyprland_version
export -f ubuntu_uninstall_hyprland