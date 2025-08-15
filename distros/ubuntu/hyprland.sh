#!/bin/bash

# Hyprland installation for Ubuntu
# Builds and configures Hyprland from source on Ubuntu

# Install Hyprland on Ubuntu
install_hyprland_ubuntu() {
    log_section "Installing Hyprland on Ubuntu"
    
    # Install build dependencies
    install_hyprland_dependencies
    
    # Build and install Hyprland
    build_hyprland
    
    # Install Wayland session
    install_hyprland_session
    
    # Configure Hyprland environment
    configure_hyprland_environment
    
    log_success "Hyprland installation completed"
}

# Install Hyprland build dependencies
install_hyprland_dependencies() {
    log_info "Installing Hyprland build dependencies..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install Hyprland dependencies"
        return 0
    fi
    
    # Build tools and libraries
    local build_deps=(
        build-essential
        cmake
        meson
        ninja-build
        pkg-config
        libwayland-dev
        libwayland-client0
        libwayland-cursor0
        libwayland-server0
        wayland-protocols
        libxkbcommon-dev
        libxkbcommon-x11-dev
        libpixman-1-dev
        libcairo2-dev
        libpango1.0-dev
        libdrm-dev
        libxcb1-dev
        libxcb-composite0-dev
        libxcb-xfixes0-dev
        libxcb-xinput-dev
        libxcb-image0-dev
        libxcb-shm0-dev
        libxcb-util0-dev
        libxcb-keysyms1-dev
        libxcb-randr0-dev
        libxcb-icccm4-dev
        libxcb-cursor-dev
        libinput-dev
        libxcb-dri3-dev
        libxcb-present-dev
        libxcb-sync-dev
        libxcb-ewmh-dev
        libtomlplusplus-dev
        libjpeg-dev
        libwebp-dev
        libmagic-dev
        libhyprlang-dev
        libhyprutils-dev
        libhyprcursor-dev
        libaquamarine-dev
        libseat-dev
        libudev-dev
        libgbm-dev
        libegl1-mesa-dev
        libgles2-mesa-dev
        libdisplay-info-dev
        libliftoff-dev
        liblibliftoff-dev
        hwdata
    )
    
    # Install dependencies
    sudo apt-get update
    sudo apt-get install -y "${build_deps[@]}"
    
    log_success "Hyprland dependencies installed"
}

# Build Hyprland from source
build_hyprland() {
    log_info "Building Hyprland from source..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would build Hyprland from source"
        return 0
    fi
    
    local build_dir="$HOME/.local/src"
    mkdir -p "$build_dir"
    cd "$build_dir"
    
    # Clone Hyprland repository
    if [[ -d "Hyprland" ]]; then
        log_info "Updating existing Hyprland repository..."
        cd Hyprland
        git pull
    else
        log_info "Cloning Hyprland repository..."
        git clone --recursive https://github.com/hyprwm/Hyprland.git
        cd Hyprland
    fi
    
    # Build Hyprland
    log_info "Compiling Hyprland (this may take a while)..."
    make all
    
    # Install Hyprland
    sudo make install
    
    log_success "Hyprland built and installed"
}

# Install Hyprland Wayland session
install_hyprland_session() {
    log_info "Installing Hyprland Wayland session..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install Hyprland session"
        return 0
    fi
    
    # Create desktop entry for display managers
    sudo tee /usr/share/wayland-sessions/hyprland.desktop > /dev/null << 'EOF'
[Desktop Entry]
Name=Hyprland
Comment=An intelligent dynamic tiling Wayland compositor
Exec=Hyprland
Type=Application
EOF
    
    # Create Hyprland wrapper script
    sudo tee /usr/local/bin/Hyprland > /dev/null << 'EOF'
#!/bin/bash
cd ~
export _JAVA_AWT_WM_NONREPARENTING=1
export XCURSOR_SIZE=24
export WLR_NO_HARDWARE_CURSORS=1
exec /usr/local/bin/hyprland
EOF
    
    sudo chmod +x /usr/local/bin/Hyprland
    
    log_success "Hyprland session installed"
}

# Configure Hyprland environment
configure_hyprland_environment() {
    log_info "Configuring Hyprland environment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would configure Hyprland environment"
        return 0
    fi
    
    # Create Hyprland config directory
    mkdir -p "$HOME/.config/hypr"
    
    # Create basic Hyprland configuration if it doesn't exist
    if [[ ! -f "$HOME/.config/hypr/hyprland.conf" ]]; then
        cat > "$HOME/.config/hypr/hyprland.conf" << 'EOF'
# Hyprland configuration
# See https://wiki.hyprland.org/Configuring/Configuring-Hyprland/

# Monitor configuration
monitor=,preferred,auto,auto

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

# Key bindings
$mainMod = SUPER

bind = $mainMod, Q, exec, kitty
bind = $mainMod, C, killactive,
bind = $mainMod, M, exit,
bind = $mainMod, E, exec, dolphin
bind = $mainMod, V, togglefloating,
bind = $mainMod, R, exec, wofi --show drun
bind = $mainMod, P, pseudo,
bind = $mainMod, J, togglesplit,

# Move focus
bind = $mainMod, left, movefocus, l
bind = $mainMod, right, movefocus, r
bind = $mainMod, up, movefocus, u
bind = $mainMod, down, movefocus, d

# Switch workspaces
bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4
bind = $mainMod, 5, workspace, 5

# Move active window to workspace
bind = $mainMod SHIFT, 1, movetoworkspace, 1
bind = $mainMod SHIFT, 2, movetoworkspace, 2
bind = $mainMod SHIFT, 3, movetoworkspace, 3
bind = $mainMod SHIFT, 4, movetoworkspace, 4
bind = $mainMod SHIFT, 5, movetoworkspace, 5

# Mouse bindings
bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod, mouse:273, resizewindow
EOF
    fi
    
    log_success "Hyprland environment configured"
}

# Install additional Hyprland tools
install_hyprland_tools() {
    log_info "Installing additional Hyprland tools..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install Hyprland tools"
        return 0
    fi
    
    # Install Waybar (status bar)
    sudo apt-get install -y waybar
    
    # Install Wofi (application launcher)
    sudo apt-get install -y wofi
    
    # Install screenshot tools
    sudo apt-get install -y grim slurp
    
    # Install notification daemon
    sudo apt-get install -y mako-notifier
    
    # Install file manager
    sudo apt-get install -y thunar
    
    log_success "Hyprland tools installed"
}