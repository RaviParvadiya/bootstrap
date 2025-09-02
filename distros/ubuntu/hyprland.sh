#!/usr/bin/env bash

# Ubuntu Hyprland Installation
# Builds and configures Hyprland from source on Ubuntu

# Source core utilities
source "$(dirname "${BASH_SOURCE[0]}")/../../core/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../core/logger.sh"

# Hyprland version to build (can be overridden by environment variable)
HYPRLAND_VERSION="${HYPRLAND_VERSION:-v0.34.0}"
HYPRLAND_BUILD_DIR="${HYPRLAND_BUILD_DIR:-/tmp/hyprland-build}"
HYPRLAND_INSTALL_PREFIX="${HYPRLAND_INSTALL_PREFIX:-/usr/local}"

# Main Hyprland installation function
ubuntu_install_hyprland() {
    log_info "Installing Hyprland on Ubuntu..."
    
    # Check if Hyprland is already installed
    if ubuntu_is_hyprland_installed; then
        log_info "Hyprland is already installed"
        if ! ask_yes_no "Reinstall Hyprland?"; then
            log_info "Skipping Hyprland installation"
            return 0
        fi
    fi
    
    # Install build dependencies
    if ! ubuntu_install_hyprland_dependencies; then
        log_error "Failed to install Hyprland build dependencies"
        return 1
    fi
    
    # Build Hyprland from source
    if ! ubuntu_build_hyprland; then
        log_error "Failed to build Hyprland"
        return 1
    fi
    
    # Install Hyprland
    if ! ubuntu_install_hyprland_binary; then
        log_error "Failed to install Hyprland binary"
        return 1
    fi
    
    # Configure Wayland session
    if ! ubuntu_configure_hyprland_session; then
        log_error "Failed to configure Hyprland session"
        return 1
    fi
    
    # Install additional Hyprland ecosystem tools
    if ! ubuntu_install_hyprland_ecosystem; then
        log_error "Failed to install Hyprland ecosystem tools"
        return 1
    fi
    
    # Configure environment for Hyprland
    if ! ubuntu_configure_hyprland_environment; then
        log_error "Failed to configure Hyprland environment"
        return 1
    fi
    
    log_success "Hyprland installation completed successfully"
    
    # Show post-installation information
    ubuntu_show_hyprland_info
    
    return 0
}

# Install Hyprland build dependencies
ubuntu_install_hyprland_dependencies() {
    log_info "Installing Hyprland build dependencies..."
    
    local build_deps=(
        # Core build tools
        "build-essential"
        "cmake"
        "meson"
        "ninja-build"
        "pkg-config"
        "git"
        
        # Wayland development libraries
        "libwayland-dev"
        "wayland-protocols"
        "libwayland-client0"
        "libwayland-cursor0"
        "libwayland-server0"
        
        # Graphics and rendering libraries
        "libegl1-mesa-dev"
        "libgles2-mesa-dev"
        "libdrm-dev"
        "libxkbcommon-dev"
        "libxkbcommon-x11-dev"
        "libpixman-1-dev"
        "libcairo2-dev"
        "libpango1.0-dev"
        "libgdk-pixbuf-2.0-dev"
        
        # Input and system libraries
        "libinput-dev"
        "libseat-dev"
        "libudev-dev"
        "libsystemd-dev"
        "libdisplay-info-dev"
        "libliftoff-dev"
        
        # X11 compatibility libraries
        "libxcb1-dev"
        "libxcb-composite0-dev"
        "libxcb-ewmh-dev"
        "libxcb-icccm4-dev"
        "libxcb-image0-dev"
        "libxcb-render-util0-dev"
        "libxcb-res0-dev"
        "libxcb-xfixes0-dev"
        "libxcb-xinput-dev"
        "libx11-xcb-dev"
        
        # Additional dependencies
        "libtomlplusplus-dev"
        "libzip-dev"
        "librsvg2-dev"
        "libmagic-dev"
        
        # wlroots dependencies (if building from source)
        "libwlroots-dev"
        "hwdata"
        
        # Protocol libraries
        "libxdg-activation-v1-dev"
        "libxdg-decoration-v1-dev"
        "libxdg-foreign-v1-dev"
        "libxdg-output-v1-dev"
        "libxdg-shell-v1-dev"
    )
    
    # Filter out packages that don't exist on this Ubuntu version
    local available_deps=()
    for dep in "${build_deps[@]}"; do
        if apt-cache show "$dep" >/dev/null 2>&1; then
            available_deps+=("$dep")
        else
            log_warn "Package not available: $dep"
        fi
    done
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would install ${#available_deps[@]} build dependencies"
        return 0
    fi
    
    # Install available dependencies
    if ! sudo apt install -y "${available_deps[@]}"; then
        log_error "Failed to install some build dependencies"
        return 1
    fi
    
    # Install additional dependencies that might not be in standard repos
    ubuntu_install_additional_hyprland_deps
    
    log_success "Hyprland build dependencies installed"
    return 0
}

# Install additional Hyprland dependencies not in standard repos
ubuntu_install_additional_hyprland_deps() {
    log_info "Installing additional Hyprland dependencies..."
    
    # Check if we need to build wlroots from source
    if ! ubuntu_check_wlroots_version; then
        log_info "Building wlroots from source..."
        if ! ubuntu_build_wlroots; then
            log_warn "Failed to build wlroots from source, using system version"
        fi
    fi
    
    # Install hyprland-protocols if not available
    if ! pkg-config --exists hyprland-protocols; then
        log_info "Installing hyprland-protocols..."
        ubuntu_install_hyprland_protocols
    fi
    
    return 0
}

# Check if wlroots version is compatible
ubuntu_check_wlroots_version() {
    if ! pkg-config --exists wlroots; then
        return 1
    fi
    
    local wlroots_version
    wlroots_version=$(pkg-config --modversion wlroots 2>/dev/null)
    
    if [[ -z "$wlroots_version" ]]; then
        return 1
    fi
    
    log_info "Found wlroots version: $wlroots_version"
    
    # Check if version is compatible (0.16.x or 0.17.x)
    if [[ "$wlroots_version" =~ ^0\.(16|17)\. ]]; then
        return 0
    else
        log_warn "wlroots version $wlroots_version may not be compatible"
        return 1
    fi
}

# Build wlroots from source
ubuntu_build_wlroots() {
    log_info "Building wlroots from source..."
    
    local wlroots_build_dir="/tmp/wlroots-build"
    local wlroots_version="0.17.1"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would build wlroots $wlroots_version"
        return 0
    fi
    
    # Clean previous build
    rm -rf "$wlroots_build_dir"
    mkdir -p "$wlroots_build_dir"
    
    # Clone wlroots
    if ! git clone --depth 1 --branch "$wlroots_version" \
        https://gitlab.freedesktop.org/wlroots/wlroots.git "$wlroots_build_dir"; then
        log_error "Failed to clone wlroots"
        return 1
    fi
    
    cd "$wlroots_build_dir" || return 1
    
    # Configure build
    if ! meson setup build/ --prefix="$HYPRLAND_INSTALL_PREFIX" --buildtype=release; then
        log_error "Failed to configure wlroots build"
        return 1
    fi
    
    # Build wlroots
    if ! ninja -C build/; then
        log_error "Failed to build wlroots"
        return 1
    fi
    
    # Install wlroots
    if ! sudo ninja -C build/ install; then
        log_error "Failed to install wlroots"
        return 1
    fi
    
    # Update library cache
    sudo ldconfig
    
    log_success "wlroots built and installed successfully"
    return 0
}

# Install hyprland-protocols
ubuntu_install_hyprland_protocols() {
    log_info "Installing hyprland-protocols..."
    
    local protocols_build_dir="/tmp/hyprland-protocols-build"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would install hyprland-protocols"
        return 0
    fi
    
    # Clean previous build
    rm -rf "$protocols_build_dir"
    mkdir -p "$protocols_build_dir"
    
    # Clone hyprland-protocols
    if ! git clone --depth 1 \
        https://github.com/hyprwm/hyprland-protocols.git "$protocols_build_dir"; then
        log_error "Failed to clone hyprland-protocols"
        return 1
    fi
    
    cd "$protocols_build_dir" || return 1
    
    # Configure and install
    if ! meson setup build/ --prefix="$HYPRLAND_INSTALL_PREFIX"; then
        log_error "Failed to configure hyprland-protocols"
        return 1
    fi
    
    if ! ninja -C build/ install; then
        log_error "Failed to install hyprland-protocols"
        return 1
    fi
    
    log_success "hyprland-protocols installed successfully"
    return 0
}

# Build Hyprland from source
ubuntu_build_hyprland() {
    log_info "Building Hyprland $HYPRLAND_VERSION from source..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would build Hyprland $HYPRLAND_VERSION"
        return 0
    fi
    
    # Clean previous build
    rm -rf "$HYPRLAND_BUILD_DIR"
    mkdir -p "$HYPRLAND_BUILD_DIR"
    
    # Clone Hyprland
    log_info "Cloning Hyprland repository..."
    if ! git clone --recursive --depth 1 --branch "$HYPRLAND_VERSION" \
        https://github.com/hyprwm/Hyprland.git "$HYPRLAND_BUILD_DIR"; then
        log_error "Failed to clone Hyprland repository"
        return 1
    fi
    
    cd "$HYPRLAND_BUILD_DIR" || return 1
    
    # Update submodules
    log_info "Updating submodules..."
    if ! git submodule update --init --recursive; then
        log_error "Failed to update submodules"
        return 1
    fi
    
    # Configure build
    log_info "Configuring Hyprland build..."
    if ! meson setup build --prefix="$HYPRLAND_INSTALL_PREFIX" --buildtype=release; then
        log_error "Failed to configure Hyprland build"
        return 1
    fi
    
    # Build Hyprland
    log_info "Building Hyprland (this may take several minutes)..."
    if ! ninja -C build; then
        log_error "Failed to build Hyprland"
        return 1
    fi
    
    log_success "Hyprland built successfully"
    return 0
}

# Install Hyprland binary and files
ubuntu_install_hyprland_binary() {
    log_info "Installing Hyprland binary and files..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would install Hyprland binary"
        return 0
    fi
    
    cd "$HYPRLAND_BUILD_DIR" || return 1
    
    # Install Hyprland
    if ! sudo ninja -C build install; then
        log_error "Failed to install Hyprland"
        return 1
    fi
    
    # Update library cache
    sudo ldconfig
    
    # Verify installation
    if ! command -v Hyprland >/dev/null 2>&1; then
        # Check if it's installed in a non-standard location
        if [[ -f "$HYPRLAND_INSTALL_PREFIX/bin/Hyprland" ]]; then
            log_info "Hyprland installed to $HYPRLAND_INSTALL_PREFIX/bin/Hyprland"
            # Add to PATH if not already there
            if ! echo "$PATH" | grep -q "$HYPRLAND_INSTALL_PREFIX/bin"; then
                echo "export PATH=\"$HYPRLAND_INSTALL_PREFIX/bin:\$PATH\"" >> ~/.bashrc
                echo "export PATH=\"$HYPRLAND_INSTALL_PREFIX/bin:\$PATH\"" >> ~/.zshrc 2>/dev/null || true
            fi
        else
            log_error "Hyprland binary not found after installation"
            return 1
        fi
    fi
    
    log_success "Hyprland binary installed successfully"
    return 0
}

# Configure Hyprland Wayland session
ubuntu_configure_hyprland_session() {
    log_info "Configuring Hyprland Wayland session..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would configure Hyprland session"
        return 0
    fi
    
    # Create Hyprland desktop entry for display managers
    local desktop_entry="/usr/share/wayland-sessions/hyprland.desktop"
    
    log_info "Creating Hyprland desktop entry..."
    sudo tee "$desktop_entry" >/dev/null <<EOF
[Desktop Entry]
Name=Hyprland
Comment=An intelligent dynamic tiling Wayland compositor
Exec=Hyprland
Type=Application
DesktopNames=Hyprland
EOF
    
    # Create xdg-desktop-portal configuration for Hyprland
    local portal_config_dir="$HOME/.config/xdg-desktop-portal"
    local portal_config="$portal_config_dir/hyprland-portals.conf"
    
    mkdir -p "$portal_config_dir"
    
    log_info "Configuring xdg-desktop-portal for Hyprland..."
    tee "$portal_config" >/dev/null <<EOF
[preferred]
default=hyprland;gtk
org.freedesktop.impl.portal.Screenshot=hyprland
org.freedesktop.impl.portal.ScreenCast=hyprland
org.freedesktop.impl.portal.Wallpaper=hyprland
EOF
    
    # Install xdg-desktop-portal-hyprland if available
    if apt-cache show xdg-desktop-portal-hyprland >/dev/null 2>&1; then
        log_info "Installing xdg-desktop-portal-hyprland..."
        sudo apt install -y xdg-desktop-portal-hyprland
    else
        log_warn "xdg-desktop-portal-hyprland not available in repositories"
        log_info "Installing xdg-desktop-portal-wlr as fallback..."
        sudo apt install -y xdg-desktop-portal-wlr
    fi
    
    # Configure environment variables for Hyprland
    local env_config="$HOME/.config/hypr/hyprland.conf"
    local env_dir="$(dirname "$env_config")"
    
    mkdir -p "$env_dir"
    
    # Create basic Hyprland configuration if it doesn't exist
    if [[ ! -f "$env_config" ]]; then
        log_info "Creating basic Hyprland configuration..."
        tee "$env_config" >/dev/null <<EOF
# Hyprland configuration
# See https://wiki.hyprland.org/Configuring/Configuring-Hyprland/

# Environment variables
env = XCURSOR_SIZE,24
env = QT_QPA_PLATFORMTHEME,qt5ct
env = QT_QPA_PLATFORM,wayland;xcb
env = GDK_BACKEND,wayland,x11
env = SDL_VIDEODRIVER,wayland
env = CLUTTER_BACKEND,wayland
env = XDG_CURRENT_DESKTOP,Hyprland
env = XDG_SESSION_TYPE,wayland
env = XDG_SESSION_DESKTOP,Hyprland

# Monitor configuration
monitor=,preferred,auto,1

# Input configuration
input {
    kb_layout = us
    follow_mouse = 1
    touchpad {
        natural_scroll = no
    }
    sensitivity = 0
}

# General configuration
general {
    gaps_in = 5
    gaps_out = 20
    border_size = 2
    col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg
    col.inactive_border = rgba(595959aa)
    layout = dwindle
}

# Decoration
decoration {
    rounding = 10
    blur {
        enabled = true
        size = 3
        passes = 1
    }
    drop_shadow = yes
    shadow_range = 4
    shadow_render_power = 3
    col.shadow = rgba(1a1a1aee)
}

# Animations
animations {
    enabled = yes
    bezier = myBezier, 0.05, 0.9, 0.1, 1.05
    animation = windows, 1, 7, myBezier
    animation = windowsOut, 1, 7, default, popin 80%
    animation = border, 1, 10, default
    animation = borderangle, 1, 8, default
    animation = fade, 1, 7, default
    animation = workspaces, 1, 6, default
}

# Layout
dwindle {
    pseudotile = yes
    preserve_split = yes
}

# Window rules
windowrule = float, ^(kitty)$
windowrule = float, ^(pavucontrol)$
windowrule = float, ^(nm-connection-editor)$

# Key bindings
\$mainMod = SUPER

bind = \$mainMod, Return, exec, kitty
bind = \$mainMod, Q, killactive,
bind = \$mainMod, M, exit,
bind = \$mainMod, E, exec, dolphin
bind = \$mainMod, V, togglefloating,
bind = \$mainMod, D, exec, wofi --show drun
bind = \$mainMod, P, pseudo,
bind = \$mainMod, J, togglesplit,

# Move focus
bind = \$mainMod, left, movefocus, l
bind = \$mainMod, right, movefocus, r
bind = \$mainMod, up, movefocus, u
bind = \$mainMod, down, movefocus, d

# Switch workspaces
bind = \$mainMod, 1, workspace, 1
bind = \$mainMod, 2, workspace, 2
bind = \$mainMod, 3, workspace, 3
bind = \$mainMod, 4, workspace, 4
bind = \$mainMod, 5, workspace, 5
bind = \$mainMod, 6, workspace, 6
bind = \$mainMod, 7, workspace, 7
bind = \$mainMod, 8, workspace, 8
bind = \$mainMod, 9, workspace, 9
bind = \$mainMod, 0, workspace, 10

# Move active window to workspace
bind = \$mainMod SHIFT, 1, movetoworkspace, 1
bind = \$mainMod SHIFT, 2, movetoworkspace, 2
bind = \$mainMod SHIFT, 3, movetoworkspace, 3
bind = \$mainMod SHIFT, 4, movetoworkspace, 4
bind = \$mainMod SHIFT, 5, movetoworkspace, 5
bind = \$mainMod SHIFT, 6, movetoworkspace, 6
bind = \$mainMod SHIFT, 7, movetoworkspace, 7
bind = \$mainMod SHIFT, 8, movetoworkspace, 8
bind = \$mainMod SHIFT, 9, movetoworkspace, 9
bind = \$mainMod SHIFT, 0, movetoworkspace, 10

# Scroll through workspaces
bind = \$mainMod, mouse_down, workspace, e+1
bind = \$mainMod, mouse_up, workspace, e-1

# Move/resize windows
bindm = \$mainMod, mouse:272, movewindow
bindm = \$mainMod, mouse:273, resizewindow

# Screenshot bindings
bind = , Print, exec, grim -g "\$(slurp)" - | wl-copy
bind = SHIFT, Print, exec, grim - | wl-copy

# Audio controls
bind = , XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
bind = , XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bind = , XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle

# Brightness controls
bind = , XF86MonBrightnessUp, exec, brightnessctl set 10%+
bind = , XF86MonBrightnessDown, exec, brightnessctl set 10%-

# Autostart
exec-once = waybar
exec-once = swaync
exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
EOF
    fi
    
    log_success "Hyprland Wayland session configured"
    return 0
}

# Install Hyprland ecosystem tools
ubuntu_install_hyprland_ecosystem() {
    log_info "Installing Hyprland ecosystem tools..."
    
    local ecosystem_packages=(
        # Status bar
        "waybar"
        
        # Application launcher
        "wofi"
        
        # Notification daemon
        "swaync"
        
        # Screenshot tools
        "grim"
        "slurp"
        
        # Clipboard manager
        "wl-clipboard"
        
        # File manager
        "dolphin"
        
        # Terminal (fallback)
        "kitty"
        
        # Audio control
        "pavucontrol"
        "pipewire"
        "pipewire-pulse"
        "wireplumber"
        
        # Brightness control
        "brightnessctl"
        
        # Authentication agent
        "polkit-gnome"
        
        # Network manager
        "network-manager-gnome"
        
        # Wallpaper setter
        "swaybg"
        
        # Lock screen
        "swaylock"
        
        # Idle management
        "swayidle"
    )
    
    # Filter available packages
    local available_packages=()
    for package in "${ecosystem_packages[@]}"; do
        if apt-cache show "$package" >/dev/null 2>&1; then
            available_packages+=("$package")
        else
            log_warn "Package not available: $package"
        fi
    done
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would install ${#available_packages[@]} ecosystem packages"
        return 0
    fi
    
    # Install available packages
    if ! sudo apt install -y "${available_packages[@]}"; then
        log_warn "Some ecosystem packages failed to install"
        return 1
    fi
    
    log_success "Hyprland ecosystem tools installed"
    return 0
}

# Configure environment for Hyprland
ubuntu_configure_hyprland_environment() {
    log_info "Configuring environment for Hyprland..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would configure Hyprland environment"
        return 0
    fi
    
    # Create environment configuration file
    local env_file="$HOME/.config/hypr/hyprland-env.conf"
    local env_dir="$(dirname "$env_file")"
    
    mkdir -p "$env_dir"
    
    tee "$env_file" >/dev/null <<EOF
# Hyprland Environment Configuration
# This file contains environment variables for Hyprland

# Wayland-specific environment variables
env = WAYLAND_DISPLAY,wayland-1
env = XDG_SESSION_TYPE,wayland
env = XDG_SESSION_DESKTOP,Hyprland
env = XDG_CURRENT_DESKTOP,Hyprland

# Qt configuration
env = QT_QPA_PLATFORM,wayland;xcb
env = QT_QPA_PLATFORMTHEME,qt5ct
env = QT_WAYLAND_DISABLE_WINDOWDECORATION,1
env = QT_AUTO_SCREEN_SCALE_FACTOR,1

# GTK configuration
env = GDK_BACKEND,wayland,x11
env = GTK_USE_PORTAL,1

# SDL configuration
env = SDL_VIDEODRIVER,wayland

# Java configuration
env = _JAVA_AWT_WM_NONREPARENTING,1

# Firefox configuration
env = MOZ_ENABLE_WAYLAND,1

# Cursor configuration
env = XCURSOR_SIZE,24
env = XCURSOR_THEME,Adwaita

# Other applications
env = CLUTTER_BACKEND,wayland
env = ELECTRON_OZONE_PLATFORM_HINT,wayland
EOF
    
    # Add environment file to main Hyprland config if not already included
    local main_config="$HOME/.config/hypr/hyprland.conf"
    if [[ -f "$main_config" ]] && ! grep -q "hyprland-env.conf" "$main_config"; then
        echo "" >> "$main_config"
        echo "# Include environment configuration" >> "$main_config"
        echo "source = ~/.config/hypr/hyprland-env.conf" >> "$main_config"
    fi
    
    # Configure systemd user environment
    log_info "Configuring systemd user environment..."
    
    # Create systemd user environment file
    local systemd_env_dir="$HOME/.config/environment.d"
    local systemd_env_file="$systemd_env_dir/hyprland.conf"
    
    mkdir -p "$systemd_env_dir"
    
    tee "$systemd_env_file" >/dev/null <<EOF
# Hyprland environment variables for systemd user services
WAYLAND_DISPLAY=wayland-1
XDG_SESSION_TYPE=wayland
XDG_SESSION_DESKTOP=Hyprland
XDG_CURRENT_DESKTOP=Hyprland
QT_QPA_PLATFORM=wayland;xcb
GDK_BACKEND=wayland,x11
SDL_VIDEODRIVER=wayland
MOZ_ENABLE_WAYLAND=1
EOF
    
    log_success "Hyprland environment configured"
    return 0
}

# Check if Hyprland is installed
ubuntu_is_hyprland_installed() {
    command -v Hyprland >/dev/null 2>&1 || [[ -f "$HYPRLAND_INSTALL_PREFIX/bin/Hyprland" ]]
}

# Get installed Hyprland version
ubuntu_get_hyprland_version() {
    if command -v Hyprland >/dev/null 2>&1; then
        Hyprland --version 2>/dev/null | head -n1 | awk '{print $2}' || echo "unknown"
    elif [[ -f "$HYPRLAND_INSTALL_PREFIX/bin/Hyprland" ]]; then
        "$HYPRLAND_INSTALL_PREFIX/bin/Hyprland" --version 2>/dev/null | head -n1 | awk '{print $2}' || echo "unknown"
    else
        echo "not installed"
    fi
}

# Show post-installation information
ubuntu_show_hyprland_info() {
    log_info "=== Hyprland Installation Complete ==="
    
    local installed_version
    installed_version=$(ubuntu_get_hyprland_version)
    log_info "Installed version: $installed_version"
    
    log_info ""
    log_info "Next steps:"
    log_info "1. Log out of your current session"
    log_info "2. Select 'Hyprland' from the session menu at login"
    log_info "3. Configure Hyprland by editing ~/.config/hypr/hyprland.conf"
    log_info "4. Install additional components (waybar, wofi, etc.) if needed"
    
    log_info ""
    log_info "Useful commands:"
    log_info "  - Super+Return: Open terminal"
    log_info "  - Super+D: Application launcher (wofi)"
    log_info "  - Super+Q: Close window"
    log_info "  - Super+Shift+E: Exit Hyprland"
    
    log_info ""
    log_info "Configuration files:"
    log_info "  - Main config: ~/.config/hypr/hyprland.conf"
    log_info "  - Environment: ~/.config/hypr/hyprland-env.conf"
    log_info "  - Desktop entry: /usr/share/wayland-sessions/hyprland.desktop"
    
    if [[ ! -f "$HOME/.config/hypr/hyprland.conf" ]]; then
        log_warn "No Hyprland configuration found. A basic config was created."
        log_info "Consider copying your dotfiles configuration to ~/.config/hypr/"
    fi
}

# Uninstall Hyprland
ubuntu_uninstall_hyprland() {
    log_info "Uninstalling Hyprland..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would uninstall Hyprland"
        return 0
    fi
    
    # Remove Hyprland binary
    if [[ -f "$HYPRLAND_INSTALL_PREFIX/bin/Hyprland" ]]; then
        sudo rm -f "$HYPRLAND_INSTALL_PREFIX/bin/Hyprland"
    fi
    
    # Remove desktop entry
    sudo rm -f /usr/share/wayland-sessions/hyprland.desktop
    
    # Remove build directory
    rm -rf "$HYPRLAND_BUILD_DIR"
    
    log_info "Hyprland uninstalled (configuration files preserved)"
    log_info "To remove configuration files, delete ~/.config/hypr/"
}

# Clean Hyprland build artifacts
ubuntu_clean_hyprland_build() {
    log_info "Cleaning Hyprland build artifacts..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would clean build artifacts"
        return 0
    fi
    
    # Remove build directories
    rm -rf "$HYPRLAND_BUILD_DIR"
    rm -rf /tmp/wlroots-build
    rm -rf /tmp/hyprland-protocols-build
    
    log_success "Build artifacts cleaned"
}

# Export functions for external use
export -f ubuntu_install_hyprland
export -f ubuntu_install_hyprland_dependencies
export -f ubuntu_install_additional_hyprland_deps
export -f ubuntu_check_wlroots_version
export -f ubuntu_build_wlroots
export -f ubuntu_install_hyprland_protocols
export -f ubuntu_build_hyprland
export -f ubuntu_install_hyprland_binary
export -f ubuntu_configure_hyprland_session
export -f ubuntu_install_hyprland_ecosystem
export -f ubuntu_configure_hyprland_environment
export -f ubuntu_is_hyprland_installed
export -f ubuntu_get_hyprland_version
export -f ubuntu_show_hyprland_info
export -f ubuntu_uninstall_hyprland
export -f ubuntu_clean_hyprland_build