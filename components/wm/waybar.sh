#!/usr/bin/env bash

# components/wm/waybar.sh - Waybar status bar installation and configuration
# This module handles the installation and configuration of Waybar status bar
# with proper dotfiles integration, theme support, and cross-distribution compatibility.

source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"
source "$CORE_DIR/logger.sh"
source "$CORE_DIR/common.sh"

# Component metadata
readonly WAYBAR_COMPONENT_NAME="waybar"
readonly WAYBAR_CONFIG_SOURCE="$DOTFILES_DIR/waybar/.config/waybar"
readonly WAYBAR_CONFIG_TARGET="$HOME/.config/waybar"

#######################################
# Waybar Installation Functions
#######################################

# Check if Waybar is already installed
is_waybar_installed() {
    command -v waybar >/dev/null 2>&1
}

# Configure Waybar with dotfiles
configure_waybar() {
    log_info "Configuring Waybar status bar..."
    
    if [[ ! -d "$WAYBAR_CONFIG_SOURCE" ]]; then
        log_error "Waybar configuration source not found: $WAYBAR_CONFIG_SOURCE"
        return 1
    fi
    
    # Create configuration directory
    if ! mkdir -p "$WAYBAR_CONFIG_TARGET"; then
        log_error "Failed to create Waybar config directory: $WAYBAR_CONFIG_TARGET"
        return 1
    fi
    
    # Copy configuration files using symlinks for easy updates
    log_info "Creating symlinks for Waybar configuration files..."
    
    # Find all configuration files in the source directory
    while IFS= read -r -d '' config_file; do
        local relative_path="${config_file#$WAYBAR_CONFIG_SOURCE/}"
        local target_file="$WAYBAR_CONFIG_TARGET/$relative_path"
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
    done < <(find "$WAYBAR_CONFIG_SOURCE" -type f -print0)
    
    # Validate configuration files
    validate_waybar_config
    
    log_success "Waybar configuration completed"
    return 0
}

# Validate Waybar configuration files
validate_waybar_config() {
    log_info "Validating Waybar configuration..."
    
    # Check if main config file exists
    if [[ ! -f "$WAYBAR_CONFIG_TARGET/config.jsonc" ]]; then
        log_warn "Waybar main config file not found: config.jsonc"
        return 1
    fi
    
    # Check if style file exists
    if [[ ! -f "$WAYBAR_CONFIG_TARGET/style.css" ]]; then
        log_warn "Waybar style file not found: style.css"
    fi
    
    # Check if theme files exist
    if [[ -f "$WAYBAR_CONFIG_TARGET/mocha.css" ]]; then
        log_debug "Found Waybar Catppuccin Mocha theme"
    fi
    
    # Test configuration syntax (if waybar supports it)
    if command -v waybar >/dev/null 2>&1; then
        log_info "Testing Waybar configuration syntax..."
        if waybar --config "$WAYBAR_CONFIG_TARGET/config.jsonc" --style "$WAYBAR_CONFIG_TARGET/style.css" --log-level error --test 2>/dev/null; then
            log_success "Waybar configuration syntax is valid"
        else
            log_warn "Waybar configuration may have syntax issues"
        fi
    fi
    
    return 0
}

# Setup Waybar systemd service (optional)
setup_waybar_service() {
    log_info "Setting up Waybar systemd user service..."
    
    local service_dir="$HOME/.config/systemd/user"
    local service_file="$service_dir/waybar.service"
    
    # Create systemd user directory
    mkdir -p "$service_dir"
    
    # Create Waybar service file
    local service_content="[Unit]
Description=Highly customizable Wayland bar for Sway and Wlroots based compositors
Documentation=https://github.com/Alexays/Waybar/wiki
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/waybar
Restart=on-failure
RestartSec=1

[Install]
WantedBy=graphical-session.target"
    
    if echo "$service_content" > "$service_file"; then
        log_success "Created Waybar systemd service"
        
        # Reload systemd user daemon
        if systemctl --user daemon-reload; then
            log_debug "Reloaded systemd user daemon"
        else
            log_warn "Failed to reload systemd user daemon"
        fi
    else
        log_warn "Failed to create Waybar systemd service"
    fi
    
    return 0
}

# Enable Waybar service
enable_waybar_service() {
    log_info "Enabling Waybar systemd service..."
    
    if systemctl --user enable waybar.service; then
        log_success "Waybar service enabled"
    else
        log_warn "Failed to enable Waybar service"
        return 1
    fi
    
    return 0
}

# Start Waybar service
start_waybar_service() {
    log_info "Starting Waybar service..."
    
    if systemctl --user start waybar.service; then
        log_success "Waybar service started"
    else
        log_warn "Failed to start Waybar service"
        return 1
    fi
    
    return 0
}

# Validate Waybar installation
validate_waybar_installation() {
    log_info "Validating Waybar installation..."
    
    # Check if binary is available
    if ! command -v waybar >/dev/null 2>&1; then
        log_error "Waybar binary not found in PATH"
        return 1
    fi
    
    # Check if configuration exists
    if [[ ! -f "$WAYBAR_CONFIG_TARGET/config.jsonc" ]]; then
        log_error "Waybar configuration file not found: $WAYBAR_CONFIG_TARGET/config.jsonc"
        return 1
    fi
    
    # Check if style file exists
    if [[ ! -f "$WAYBAR_CONFIG_TARGET/style.css" ]]; then
        log_warn "Waybar style file not found: $WAYBAR_CONFIG_TARGET/style.css"
    fi
    
    # Test Waybar version (basic functionality test)
    if ! waybar --version >/dev/null 2>&1; then
        log_error "Waybar version check failed"
        return 1
    fi
    
    # Check if systemd service exists
    if [[ -f "$HOME/.config/systemd/user/waybar.service" ]]; then
        log_debug "Waybar systemd service found"
    else
        log_warn "Waybar systemd service not found"
    fi
    
    log_success "Waybar installation validation passed"
    return 0
}

#######################################
# Main Installation Function
#######################################

# Main Waybar installation function
install_waybar() {
    log_section "Configuring Waybar Status Bar"
    
    # Check if already installed (packages should be installed by main system)
    if ! is_waybar_installed; then
        log_error "Waybar not found. Ensure packages are installed by the main system first."
        return 1
    fi
    
    # Configure Waybar
    if ! configure_waybar; then
        log_error "Failed to configure Waybar"
        return 1
    fi
    
    # Setup systemd service
    if ask_yes_no "Setup Waybar systemd service?" "y"; then
        setup_waybar_service
        
        if ask_yes_no "Enable Waybar service to start automatically?" "n"; then
            enable_waybar_service
        fi
        
        if ask_yes_no "Start Waybar service now?" "n"; then
            start_waybar_service
        fi
    fi
    
    # Validate installation
    if ! validate_waybar_installation; then
        log_error "Waybar installation validation failed"
        return 1
    fi
    
    log_success "Waybar configuration completed successfully"
    log_info "Note: Waybar will start automatically with Hyprland if configured in hyprland.conf"
    return 0
}

# Uninstall Waybar (for testing/cleanup)
uninstall_waybar() {
    log_info "Uninstalling Waybar..."
    
    # Stop and disable service first
    systemctl --user stop waybar.service 2>/dev/null || true
    systemctl --user disable waybar.service 2>/dev/null || true
    
    local distro
    distro=$(get_distro)
    
    # Remove packages
    case "$distro" in
        "arch")
            sudo pacman -Rns --noconfirm waybar 2>/dev/null || true
            ;;
        "ubuntu")
            sudo apt-get remove --purge -y waybar 2>/dev/null || true
            ;;
    esac
    
    # Remove configuration (with backup)
    if [[ -d "$WAYBAR_CONFIG_TARGET" ]]; then
        local backup_dir="$HOME/.config/install-backups/waybar-$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$(dirname "$backup_dir")"
        mv "$WAYBAR_CONFIG_TARGET" "$backup_dir"
        log_info "Waybar configuration backed up to: $backup_dir"
    fi
    
    # Remove systemd service
    if [[ -f "$HOME/.config/systemd/user/waybar.service" ]]; then
        rm -f "$HOME/.config/systemd/user/waybar.service"
        systemctl --user daemon-reload 2>/dev/null || true
    fi
    
    log_success "Waybar uninstalled successfully"
    return 0
}

# Export essential functions
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && export -f install_waybar configure_waybar is_waybar_installed