#!/usr/bin/env bash

# components/wm/swaync.sh - SwayNC notification daemon installation and configuration
# This module handles the installation and configuration of SwayNC notification daemon
# with proper dotfiles integration, theme support, and cross-distribution compatibility.

source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"
source "$CORE_DIR/logger.sh"
source "$CORE_DIR/common.sh"

# Component metadata
readonly SWAYNC_COMPONENT_NAME="swaync"
readonly SWAYNC_CONFIG_SOURCE="$DOTFILES_DIR/swaync/.config/swaync"
readonly SWAYNC_CONFIG_TARGET="$HOME/.config/swaync"

# Manual installation packages (not available in all repos or need source build)
declare -A SWAYNC_MANUAL_PACKAGES=(
    ["arch"]=""  # Available in Arch repos, handled by main system
    ["ubuntu"]="swaync"  # Ubuntu builds from source
)

# Dependencies for Ubuntu source build
declare -A SWAYNC_UBUNTU_DEPS=(
    ["ubuntu"]="libnotify-bin libgtk-3-0 libgtk-layer-shell0"
)

# Build dependencies for Ubuntu source build
declare -A SWAYNC_BUILD_DEPS=(
    ["ubuntu"]="build-essential meson ninja-build pkg-config libgtk-3-dev libglib2.0-dev libjson-glib-dev libgtk-layer-shell-dev libpulse-dev"
)

#######################################
# SwayNC Installation Functions
#######################################

# Check if SwayNC is already installed
is_swaync_installed() {
    command -v swaync >/dev/null 2>&1
}



# Build and install SwayNC from source for Ubuntu
install_swaync_ubuntu() {
    log_info "Building SwayNC from source for Ubuntu..."
    
    # Install runtime dependencies first
    log_info "Installing SwayNC runtime dependencies..."
    local deps
    read -ra deps <<< "${SWAYNC_UBUNTU_DEPS[ubuntu]}"
    
    for dep in "${deps[@]}"; do
        if ! install_package "$dep"; then
            log_warn "Failed to install dependency: $dep (continuing anyway)"
        fi
    done
    
    # Install build dependencies
    log_info "Installing build dependencies..."
    local build_deps
    read -ra build_deps <<< "${SWAYNC_BUILD_DEPS[ubuntu]}"
    
    for build_dep in "${build_deps[@]}"; do
        if ! install_package "$build_dep"; then
            log_error "Failed to install build dependency: $build_dep"
            return 1
        fi
    done
    
    # Create build directory
    local build_dir="$HOME/.local/src/swaync-build"
    mkdir -p "$build_dir"
    
    # Clone SwayNC repository
    log_info "Cloning SwayNC repository..."
    if [[ -d "$build_dir/SwayNotificationCenter" ]]; then
        log_info "SwayNC repository already exists, updating..."
        if ! git -C "$build_dir/SwayNotificationCenter" pull --quiet; then
            log_warn "Failed to update SwayNC repository, using existing version"
        fi
    else
        if ! git clone https://github.com/ErikReider/SwayNotificationCenter.git "$build_dir/SwayNotificationCenter"; then
            log_error "Failed to clone SwayNC repository"
            return 1
        fi
    fi
    
    # Build SwayNC
    log_info "Building SwayNC (this may take several minutes)..."
    cd "$build_dir/SwayNotificationCenter" || return 1
    
    # Setup build directory
    if ! meson setup build; then
        log_error "Failed to setup SwayNC build"
        return 1
    fi
    
    # Compile
    if ! ninja -C build; then
        log_error "Failed to build SwayNC"
        return 1
    fi
    
    # Install SwayNC
    log_info "Installing SwayNC..."
    if ! sudo ninja -C build install; then
        log_error "Failed to install SwayNC"
        return 1
    fi
    
    log_success "SwayNC built and installed successfully for Ubuntu"
    return 0
}

# Install manual SwayNC packages (Ubuntu source build)
install_swaync_manual_packages() {
    local distro
    distro=$(get_distro)
    
    if [[ -z "${SWAYNC_MANUAL_PACKAGES[$distro]}" ]]; then
        log_info "No manual packages needed for $distro"
        return 0
    fi
    
    case "$distro" in
        "ubuntu")
            install_swaync_ubuntu
            ;;
        *)
            log_warn "Manual package installation not implemented for: $distro"
            ;;
    esac
}

# Configure SwayNC with dotfiles
configure_swaync() {
    log_info "Configuring SwayNC notification daemon..."
    
    if [[ ! -d "$SWAYNC_CONFIG_SOURCE" ]]; then
        log_error "SwayNC configuration source not found: $SWAYNC_CONFIG_SOURCE"
        return 1
    fi
    
    # Create configuration directory
    if ! mkdir -p "$SWAYNC_CONFIG_TARGET"; then
        log_error "Failed to create SwayNC config directory: $SWAYNC_CONFIG_TARGET"
        return 1
    fi
    
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
    
    # Validate configuration files
    validate_swaync_config
    
    log_success "SwayNC configuration completed"
    return 0
}

# Validate SwayNC configuration files
validate_swaync_config() {
    log_info "Validating SwayNC configuration..."
    
    # Check if main config file exists
    if [[ ! -f "$SWAYNC_CONFIG_TARGET/config.json" ]]; then
        log_warn "SwayNC main config file not found: config.json"
    else
        log_debug "Found SwayNC config file"
        
        # Validate JSON syntax if jq is available
        if command -v jq >/dev/null 2>&1; then
            if jq empty "$SWAYNC_CONFIG_TARGET/config.json" 2>/dev/null; then
                log_debug "SwayNC config JSON syntax is valid"
            else
                log_warn "SwayNC config JSON syntax may be invalid"
            fi
        fi
    fi
    
    # Check if style file exists
    if [[ -f "$SWAYNC_CONFIG_TARGET/style.css" ]]; then
        log_debug "Found SwayNC style file"
    else
        log_warn "SwayNC style file not found: style.css"
    fi
    
    # Check for theme files
    if [[ -f "$SWAYNC_CONFIG_TARGET/mocha.css" ]]; then
        log_debug "Found SwayNC Catppuccin Mocha theme"
    fi
    
    # Check for icons directory
    if [[ -d "$SWAYNC_CONFIG_TARGET/icons" ]]; then
        log_debug "Found SwayNC icons directory"
    fi
    
    return 0
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
    
    return 0
}

# Enable SwayNC service
enable_swaync_service() {
    log_info "Enabling SwayNC systemd service..."
    
    if systemctl --user enable swaync.service; then
        log_success "SwayNC service enabled"
    else
        log_warn "Failed to enable SwayNC service"
        return 1
    fi
    
    return 0
}

# Start SwayNC service
start_swaync_service() {
    log_info "Starting SwayNC service..."
    
    if systemctl --user start swaync.service; then
        log_success "SwayNC service started"
    else
        log_warn "Failed to start SwayNC service"
        return 1
    fi
    
    return 0
}

# Test SwayNC functionality
test_swaync_functionality() {
    log_info "Testing SwayNC functionality..."
    
    # Test if swaync-client is available
    if ! command -v swaync-client >/dev/null 2>&1; then
        log_warn "swaync-client not found, cannot test functionality"
        return 1
    fi
    
    # Send a test notification
    log_info "Sending test notification..."
    if swaync-client --notification --text "SwayNC Test" --summary "Installation Complete" --timeout 3000 2>/dev/null; then
        log_success "SwayNC test notification sent successfully"
    else
        log_warn "Failed to send test notification"
    fi
    
    return 0
}

# Validate SwayNC installation
validate_swaync_installation() {
    log_info "Validating SwayNC installation..."
    
    # Check if binary is available
    if ! command -v swaync >/dev/null 2>&1; then
        log_error "SwayNC binary not found in PATH"
        return 1
    fi
    
    # Check if client binary is available
    if ! command -v swaync-client >/dev/null 2>&1; then
        log_warn "swaync-client binary not found in PATH"
    fi
    
    # Check if configuration exists
    if [[ ! -f "$SWAYNC_CONFIG_TARGET/config.json" ]]; then
        log_warn "SwayNC configuration file not found: $SWAYNC_CONFIG_TARGET/config.json"
    fi
    
    # Check if style file exists
    if [[ ! -f "$SWAYNC_CONFIG_TARGET/style.css" ]]; then
        log_warn "SwayNC style file not found: $SWAYNC_CONFIG_TARGET/style.css"
    fi
    
    # Test SwayNC version (basic functionality test)
    if ! swaync --version >/dev/null 2>&1; then
        log_error "SwayNC version check failed"
        return 1
    fi
    
    # Check if systemd service exists
    if [[ -f "$HOME/.config/systemd/user/swaync.service" ]]; then
        log_debug "SwayNC systemd service found"
    else
        log_warn "SwayNC systemd service not found"
    fi
    
    log_success "SwayNC installation validation passed"
    return 0
}

#######################################
# Main Installation Function
#######################################

# Main SwayNC installation function
install_swaync() {
    log_section "Configuring SwayNC Notification Daemon"
    
    local distro
    distro=$(get_distro)
    
    # For Arch, check if already installed (packages should be installed by main system)
    # For Ubuntu, we need to build from source
    if [[ "$distro" == "arch" ]]; then
        if ! is_swaync_installed; then
            log_error "SwayNC not found. Ensure packages are installed by the main system first."
            return 1
        fi
    fi
    
    # Validate distribution support
    if [[ "$distro" != "arch" && "$distro" != "ubuntu" ]]; then
        log_error "SwayNC installation not supported on: $distro"
        return 1
    fi
    
    # Install manual packages if needed (Ubuntu source build)
    if ! install_swaync_manual_packages; then
        log_error "Failed to install manual SwayNC packages"
        return 1
    fi
    
    # Configure SwayNC
    if ! configure_swaync; then
        log_error "Failed to configure SwayNC"
        return 1
    fi
    
    # Setup systemd service
    if ask_yes_no "Setup SwayNC systemd service?" "y"; then
        setup_swaync_service
        
        if ask_yes_no "Enable SwayNC service to start automatically?" "y"; then
            enable_swaync_service
        fi
        
        if ask_yes_no "Start SwayNC service now?" "y"; then
            start_swaync_service
            
            # Test functionality if service started
            if ask_yes_no "Test SwayNC with a notification?" "y"; then
                sleep 2  # Give service time to start
                test_swaync_functionality
            fi
        fi
    fi
    
    # Validate installation
    if ! validate_swaync_installation; then
        log_error "SwayNC installation validation failed"
        return 1
    fi
    
    log_success "SwayNC configuration completed successfully"
    log_info "Note: SwayNC will handle notifications in Hyprland. Use 'swaync-client' for control."
    return 0
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
    
    # Remove configuration (with backup)
    if [[ -d "$SWAYNC_CONFIG_TARGET" ]]; then
        local backup_dir="$HOME/.config/install-backups/swaync-$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$(dirname "$backup_dir")"
        mv "$SWAYNC_CONFIG_TARGET" "$backup_dir"
        log_info "SwayNC configuration backed up to: $backup_dir"
    fi
    
    # Remove systemd service
    if [[ -f "$HOME/.config/systemd/user/swaync.service" ]]; then
        rm -f "$HOME/.config/systemd/user/swaync.service"
        systemctl --user daemon-reload 2>/dev/null || true
    fi
    
    log_success "SwayNC uninstalled successfully"
    return 0
}

# Export essential functions
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && export -f install_swaync configure_swaync is_swaync_installed