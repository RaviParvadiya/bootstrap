#!/bin/bash

# components/wm/swaync.sh - SwayNC notification daemon installation and configuration
# This module handles the installation and configuration of SwayNC notification daemon
# with proper dotfiles integration, theme support, and cross-distribution compatibility.

# Source required modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Source core modules if not already loaded
if [[ -z "${LOGGER_SOURCED:-}" ]]; then
    source "$PROJECT_ROOT/core/logger.sh"
fi
if ! declare -f detect_distro >/dev/null 2>&1; then
    source "$PROJECT_ROOT/core/common.sh"
fi

# Component metadata
readonly SWAYNC_COMPONENT_NAME="swaync"
readonly SWAYNC_CONFIG_SOURCE="$PROJECT_ROOT/dotfiles/swaync/.config/swaync"
readonly SWAYNC_CONFIG_TARGET="$HOME/.config/swaync"

# Package definitions per distribution
declare -A SWAYNC_PACKAGES=(
    ["arch"]="swaync"
    ["ubuntu"]=""  # May need to build from source or use PPA
)

# Dependencies for SwayNC functionality
declare -A SWAYNC_DEPS=(
    ["arch"]="libnotify gtk3 gtk-layer-shell"
    ["ubuntu"]="libnotify-bin libgtk-3-0 libgtk-layer-shell0"
)

# Build dependencies for Ubuntu (if building from source)
declare -A SWAYNC_BUILD_DEPS=(
    ["ubuntu"]="build-essential meson ninja-build pkg-config libgtk-3-dev libglib2.0-dev libjson-glib-dev libgtk-layer-shell-dev libpulse-dev"
)

#######################################
# SwayNC Installation Functions
#######################################

# Check if SwayNC is already installed
# Returns: 0 if installed, 1 if not installed
# Requirements: 7.1 - Component installation detection
is_swaync_installed() {
    if command -v swaync >/dev/null 2>&1; then
        return 0
    fi
    
    # Also check if package is installed via package manager
    local distro
    distro=$(get_distro)
    
    case "$distro" in
        "arch")
            pacman -Qi swaync >/dev/null 2>&1
            ;;
        "ubuntu")
            # For Ubuntu, check if binary exists (might be built from source)
            [[ -f "/usr/local/bin/swaync" ]] || [[ -f "/usr/bin/swaync" ]]
            ;;
        *)
            return 1
            ;;
    esac
}

# Install SwayNC packages for Arch Linux
# Returns: 0 if successful, 1 if failed
install_swaync_arch() {
    log_info "Installing SwayNC packages for Arch Linux..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install packages: ${SWAYNC_PACKAGES[arch]}"
        log_info "[DRY-RUN] Would install dependencies: ${SWAYNC_DEPS[arch]}"
        return 0
    fi
    
    # Install dependencies first
    local deps
    read -ra deps <<< "${SWAYNC_DEPS[arch]}"
    
    for dep in "${deps[@]}"; do
        if ! install_package "$dep"; then
            log_warn "Failed to install dependency: $dep (continuing anyway)"
        fi
    done
    
    # Install main SwayNC package
    local packages
    read -ra packages <<< "${SWAYNC_PACKAGES[arch]}"
    
    for package in "${packages[@]}"; do
        if ! install_package "$package"; then
            log_error "Failed to install SwayNC package: $package"
            return 1
        fi
    done
    
    log_success "SwayNC packages installed successfully for Arch Linux"
    return 0
}

# Build and install SwayNC from source for Ubuntu
# Returns: 0 if successful, 1 if failed
install_swaync_ubuntu() {
    log_info "Building SwayNC from source for Ubuntu..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install build dependencies: ${SWAYNC_BUILD_DEPS[ubuntu]}"
        log_info "[DRY-RUN] Would clone and build SwayNC from source"
        return 0
    fi
    
    # Install runtime dependencies first
    log_info "Installing SwayNC runtime dependencies..."
    local deps
    read -ra deps <<< "${SWAYNC_DEPS[ubuntu]}"
    
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

# Install SwayNC packages based on distribution
# Returns: 0 if successful, 1 if failed
# Requirements: 7.1 - Package installation with distribution detection
install_swaync_packages() {
    local distro
    distro=$(get_distro)
    
    case "$distro" in
        "arch")
            install_swaync_arch
            ;;
        "ubuntu")
            install_swaync_ubuntu
            ;;
        *)
            log_error "SwayNC installation not supported on: $distro"
            return 1
            ;;
    esac
}

# Configure SwayNC with dotfiles
# Returns: 0 if successful, 1 if failed
# Requirements: 7.1, 7.2 - Configuration management with dotfiles integration
configure_swaync() {
    log_info "Configuring SwayNC notification daemon..."
    
    if [[ ! -d "$SWAYNC_CONFIG_SOURCE" ]]; then
        log_error "SwayNC configuration source not found: $SWAYNC_CONFIG_SOURCE"
        return 1
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create configuration directory: $SWAYNC_CONFIG_TARGET"
        log_info "[DRY-RUN] Would copy configurations from: $SWAYNC_CONFIG_SOURCE"
        return 0
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
# Returns: 0 if valid, 1 if invalid
validate_swaync_config() {
    log_info "Validating SwayNC configuration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would validate SwayNC configuration files"
        return 0
    fi
    
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
# Returns: 0 if successful, 1 if failed
setup_swaync_service() {
    log_info "Setting up SwayNC systemd user service..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create SwayNC systemd user service"
        return 0
    fi
    
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
# Returns: 0 if successful, 1 if failed
enable_swaync_service() {
    log_info "Enabling SwayNC systemd service..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would enable SwayNC systemd service"
        return 0
    fi
    
    if systemctl --user enable swaync.service; then
        log_success "SwayNC service enabled"
    else
        log_warn "Failed to enable SwayNC service"
        return 1
    fi
    
    return 0
}

# Start SwayNC service
# Returns: 0 if successful, 1 if failed
start_swaync_service() {
    log_info "Starting SwayNC service..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would start SwayNC service"
        return 0
    fi
    
    if systemctl --user start swaync.service; then
        log_success "SwayNC service started"
    else
        log_warn "Failed to start SwayNC service"
        return 1
    fi
    
    return 0
}

# Test SwayNC functionality
# Returns: 0 if successful, 1 if failed
test_swaync_functionality() {
    log_info "Testing SwayNC functionality..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would test SwayNC functionality"
        return 0
    fi
    
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
# Returns: 0 if valid, 1 if invalid
# Requirements: 10.1 - Post-installation validation
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
# Returns: 0 if successful, 1 if failed
# Requirements: 7.1, 7.2 - Complete component installation
install_swaync() {
    log_section "Installing SwayNC Notification Daemon"
    
    # Check if already installed
    if is_swaync_installed; then
        log_info "SwayNC is already installed"
        if ! ask_yes_no "Do you want to reconfigure SwayNC?" "n"; then
            log_info "Skipping SwayNC installation"
            return 0
        fi
    fi
    
    # Validate distribution support
    local distro
    distro=$(get_distro)
    if [[ "$distro" != "arch" && "$distro" != "ubuntu" ]]; then
        log_error "SwayNC installation not supported on: $distro"
        return 1
    fi
    
    # Install packages
    if ! install_swaync_packages; then
        log_error "Failed to install SwayNC packages"
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
    
    log_success "SwayNC installation completed successfully"
    log_info "Note: SwayNC will handle notifications in Hyprland. Use 'swaync-client' for control."
    return 0
}

# Uninstall SwayNC (for testing/cleanup)
# Returns: 0 if successful, 1 if failed
uninstall_swaync() {
    log_info "Uninstalling SwayNC..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would uninstall SwayNC packages and remove configurations"
        return 0
    fi
    
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

# Export functions for use by other modules
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Being sourced, export functions
    export -f install_swaync
    export -f configure_swaync
    export -f is_swaync_installed
    export -f validate_swaync_installation
    export -f uninstall_swaync
fi