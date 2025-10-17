#!/usr/bin/env bash
#
# components/wm/waybar.sh - Waybar status bar installer
# Handles installation, dotfiles, optional packages, systemd service, and validation.

source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"
source "$CORE_DIR/logger.sh"
source "$CORE_DIR/common.sh"

# Component metadata
readonly WAYBAR_COMPONENT_NAME="waybar"
readonly WAYBAR_CONFIG_SOURCE="$DOTFILES_DIR/waybar/.config/waybar"
readonly WAYBAR_CONFIG_TARGET="$HOME/.config/waybar"
readonly WAYBAR_SERVICE_FILE="$HOME/.config/systemd/user/waybar.service"

# Package definitions per distribution
declare -A WAYBAR_PACKAGES=(
    ["arch"]="waybar"
    ["ubuntu"]="waybar"
)

# Dependencies for Waybar functionality
declare -A WAYBAR_DEPS=(
    ["arch"]="ttf-font-awesome"
    ["ubuntu"]="fonts-font-awesome"
)

# Optional packages for enhanced Waybar functionality
declare -A WAYBAR_OPTIONAL=(
    ["arch"]="playerctl pavucontrol"
    ["ubuntu"]="playerctl pavucontrol"
)

#######################################
# Waybar Installation Functions
#######################################

# Install Waybar packages
install_waybar_packages() {
    local distro
    distro=$(get_distro)
    
    log_info "Installing Waybar packages for $distro..."
    
    install_packages ${WAYBAR_DEPS[$distro]} ${WAYBAR_PACKAGES[$distro]} ${WAYBAR_OPTIONAL[$distro]}
    
    log_success "Waybar packages installed"
}

# Configure Waybar with dotfiles
configure_waybar() {
    log_info "Configuring Waybar..."

    [[ ! -d "$WAYBAR_CONFIG_SOURCE" ]] && { log_error "Missing config: $WAYBAR_CONFIG_SOURCE"; return 1; }
    
    mkdir -p "$WAYBAR_CONFIG_TARGET"
    
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
}

# Validate Waybar configuration files
validate_waybar_config() {
    [[ ! -f "$WAYBAR_CONFIG_TARGET/config.jsonc" ]] && log_warn "Missing config.jsonc"
    [[ ! -f "$WAYBAR_CONFIG_TARGET/style.css" ]] && log_warn "Missing style.css"
    [[ -f "$WAYBAR_CONFIG_TARGET/mocha.css" ]] && log_debug "Found Catppuccin Mocha theme"
    command -v waybar >/dev/null && waybar --config "$WAYBAR_CONFIG_TARGET/config.jsonc" --style "$WAYBAR_CONFIG_TARGET/style.css" --log-level error --test &>/dev/null \
        && log_debug "Waybar config syntax OK" || log_warn "Waybar config may have syntax issues"
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
}

enable_start_waybar_service() {
    systemctl --user enable --now waybar.service && log_success "Waybar service enabled and started"
}

validate_waybar_installation() {
    command -v waybar >/dev/null || { log_error "waybar not in PATH"; return 1; }
    [[ -f "$WAYBAR_CONFIG_TARGET/config.jsonc" ]] || log_warn "Missing config.jsonc"
    [[ -f "$WAYBAR_CONFIG_TARGET/style.css" ]] || log_warn "Missing style.css"
    [[ -f "$WAYBAR_SERVICE_FILE" ]] || log_warn "Systemd service missing"
    log_success "Waybar validation passed"
}

#######################################
# Main Installation Function
#######################################

# Main Waybar installation function
install_waybar() {
    log_section "Installing Waybar Status Bar"

    install_waybar_packages || return 1
    configure_waybar || return 1

    ask_yes_no "Setup Waybar systemd service?" "y" && setup_waybar_service
    ask_yes_no "Enable and start Waybar service?" "y" && enable_start_waybar_service

    validate_waybar_installation
    
    log_success "Waybar configuration completed"
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
    
    # Remove configuration
    if [[ -d "$WAYBAR_CONFIG_TARGET" ]]; then
        rm -rf "$WAYBAR_CONFIG_TARGET"
        log_info "Waybar configuration removed"
    fi
    
    # Remove systemd service
    if [[ -f "$HOME/.config/systemd/user/waybar.service" ]]; then
        rm -f "$HOME/.config/systemd/user/waybar.service"
        systemctl --user daemon-reload 2>/dev/null || true
    fi
    
    log_success "Waybar uninstalled"
}

# Export essential functions
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && export -f install_waybar