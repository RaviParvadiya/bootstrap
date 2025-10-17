#!/usr/bin/env bash
#
# components/wm/swaync.sh - SwayNC notification daemon installer
# Handles installation, dotfiles, systemd service, and basic functionality testing.

source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"
source "$CORE_DIR/logger.sh"
source "$CORE_DIR/common.sh"

# Component metadata
readonly SWAYNC_COMPONENT_NAME="swaync"
readonly SWAYNC_CONFIG_SOURCE="$DOTFILES_DIR/swaync/.config/swaync"
readonly SWAYNC_CONFIG_TARGET="$HOME/.config/swaync"
readonly SWAYNC_BUILD_DIR="$HOME/.local/src/swaync-build"
readonly SWAYNC_REPO="https://github.com/ErikReider/SwayNotificationCenter.git"
readonly SWAYNC_SERVICE_FILE="$HOME/.config/systemd/user/swaync.service"

# Package definitions per distribution
declare -A SWAYNC_PACKAGES=(
    ["arch"]="swaync"
    ["ubuntu"]=""  # May need to build from source or use PPA
)

# Dependencies for SwayNC functionality
declare -A SWAYNC_DEPS=(
    ["arch"]=""
    ["ubuntu"]="libnotify-bin libgtk-3-0 libgtk-layer-shell0"
)

# Build dependencies for Ubuntu source build
declare -A SWAYNC_BUILD_DEPS=(
    ["ubuntu"]="build-essential meson ninja-build pkg-config libgtk-3-dev libglib2.0-dev libjson-glib-dev libgtk-layer-shell-dev libpulse-dev"
)

#######################################
# SwayNC Installation Functions
#######################################

# Install SwayNC packages for Arch Linux
install_swaync_packages() {
    local distro=$(get_distro)
    log_info "Installing SwayNC packages for $distro..."
    [[ -n "${SWAYNC_DEPS[$distro]}" ]] && install_packages ${SWAYNC_DEPS[$distro]}
    
    if [[ "$distro" == "arch" ]]; then
        [[ -n "${SWAYNC_PACKAGES[$distro]}" ]] && install_packages ${SWAYNC_PACKAGES[$distro]}
    elif [[ "$distro" == "ubuntu" ]]; then
        log_info "Building SwayNC from source for Ubuntu..."
        install_packages ${SWAYNC_BUILD_DEPS[$distro]}
        mkdir -p "$SWAYNC_BUILD_DIR"
        if [[ -d "$SWAYNC_BUILD_DIR/SwayNotificationCenter" ]]; then
            git -C "$SWAYNC_BUILD_DIR/SwayNotificationCenter" pull --quiet
        else
            git clone "$SWAYNC_REPO" "$SWAYNC_BUILD_DIR/SwayNotificationCenter"
        fi
        cd "$SWAYNC_BUILD_DIR/SwayNotificationCenter" || return 1
        meson setup build
        ninja -C build
        sudo ninja -C build install
    else
        log_error "Unsupported distro: $distro"
        return 1
    fi
    log_success "SwayNC packages installed"
}

# Configure SwayNC with dotfiles
configure_swaync() {
    log_info "Configuring SwayNC notification daemon..."
    
    [[ ! -d "$SWAYNC_CONFIG_SOURCE" ]] && { log_error "Missing config: $SWAYNC_CONFIG_SOURCE"; return 1; }
    mkdir -p "$SWAYNC_CONFIG_TARGET"
    
    # Copy configuration files using symlinks for easy updates
    log_info "Creating symlinks for SwayNC configuration files..."
    
    # Find all configuration files in the source directory
    while IFS= read -r -d '' config_file; do
        local relative_path="${config_file#$SWAYNC_CONFIG_SOURCE/}"
        local target_file="$SWAYNC_CONFIG_TARGET/$relative_path"
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
    done < <(find "$SWAYNC_CONFIG_SOURCE" -type f -print0)
    
    log_success "SwayNC configuration completed"
}

# Setup SwayNC systemd service
setup_swaync_service() {
    log_info "Setting up SwayNC systemd user service..."
    
    local service_dir="$HOME/.config/systemd/user"
    local service_file="$service_dir/swaync.service"
    
    # Create systemd user directory
    mkdir -p "$service_dir"
    
    # Create SwayNC service file
    local service_content="[Unit]
Description=Sway Notification Center
Documentation=https://github.com/ErikReider/SwayNotificationCenter
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=dbus
BusName=org.freedesktop.Notifications
ExecStart=/usr/bin/swaync
ExecReload=/usr/bin/swaync-client --reload-config
Restart=on-failure
RestartSec=1

[Install]
WantedBy=graphical-session.target"
    
    if echo "$service_content" > "$service_file"; then
        log_success "Created SwayNC systemd service"
        
        # Reload systemd user daemon
        if systemctl --user daemon-reload; then
            log_debug "Reloaded systemd user daemon"
        else
            log_warn "Failed to reload systemd user daemon"
        fi
    else
        log_warn "Failed to create SwayNC systemd service"
    fi
}

enable_start_swaync_service() {
    systemctl --user enable --now swaync.service && log_success "SwayNC service enabled and started"
}

# Test SwayNC functionality
test_swaync_functionality() {
    command -v swaync-client >/dev/null || { log_warn "Cannot test, swaync-client missing"; return 1; }
    swaync-client --notification --text "SwayNC Test" --summary "Installation Complete" --timeout 3000
    log_success "SwayNC test notification sent"
}

# Validate SwayNC installation
validate_swaync_installation() {
    log_info "Validating SwayNC installation..."
    
    command -v swaync >/dev/null || { log_error "swaync not in PATH"; return 1; }
    command -v swaync-client >/dev/null || log_warn "swaync-client missing"

    [[ -f "$SWAYNC_CONFIG_TARGET/config.json" ]] || log_warn "Missing config.json"
    [[ -f "$SWAYNC_CONFIG_TARGET/style.css" ]] || log_warn "Missing style.css"
    [[ -f "$SWAYNC_SERVICE_FILE" ]] || log_warn "Systemd service missing"
    
    log_success "SwayNC installation validation passed"
}

#######################################
# Main Installation Function
#######################################

# Main SwayNC installation function
install_swaync() {
    log_section "Installing SwayNC Notification Daemon"
    
    local distro
    distro=$(get_distro)
    
    install_swaync_packages || return 1
    configure_swaync || return 1
    setup_swaync_service
    
    ask_yes_no "Enable and start SwayNC service?" "y" && enable_start_swaync_service
    ask_yes_no "Send test notification?" "y" && test_swaync_functionality
    
    validate_swaync_installation
    
    log_success "SwayNC installation complete"
}

# Uninstall SwayNC (for testing/cleanup)
uninstall_swaync() {
    log_info "Uninstalling SwayNC..."
    
    # Stop and disable service first
    systemctl --user stop swaync.service 2>/dev/null || true
    systemctl --user disable swaync.service 2>/dev/null || true
    
    local distro
    distro=$(get_distro)
    
    # Remove packages
    case "$distro" in
        "arch")
            sudo pacman -Rns --noconfirm swaync 2>/dev/null || true
            ;;
        "ubuntu")
            # Remove built binaries
            sudo rm -f /usr/local/bin/swaync /usr/bin/swaync
            sudo rm -f /usr/local/bin/swaync-client /usr/bin/swaync-client
            ;;
    esac
    
    # Remove configuration
    if [[ -d "$SWAYNC_CONFIG_TARGET" ]]; then
        rm -rf "$SWAYNC_CONFIG_TARGET"
        log_info "SwayNC configuration removed"
    fi
    
    # Remove systemd service
    if [[ -f "$HOME/.config/systemd/user/swaync.service" ]]; then
        rm -f "$HOME/.config/systemd/user/swaync.service"
        systemctl --user daemon-reload 2>/dev/null || true
    fi
    
    log_success "SwayNC uninstalled"
}

# Export essential functions
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && export -f install_swaync