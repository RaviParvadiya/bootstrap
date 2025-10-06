#!/usr/bin/env bash

# core/service-manager.sh - Service management system
# Provides cross-distribution service management

# Prevent multiple sourcing
if [[ -n "${SERVICE_MANAGER_SOURCED:-}" ]]; then
    return 0
fi
readonly SERVICE_MANAGER_SOURCED=1

# Initialize paths if needed
if [[ -z "${PATHS_SOURCED:-}" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/init-paths.sh"
fi

# Source dependencies
if [[ -z "${COMMON_SOURCED:-}" ]]; then
    source "$CORE_DIR/common.sh"
fi
if [[ -z "${LOGGER_SOURCED:-}" ]]; then
    source "$CORE_DIR/logger.sh"
fi

# Check if a service is available on the system
is_service_available() {
    local service_name="$1"
    
    if [[ -z "$service_name" ]]; then
        return 1
    fi
    
    systemctl list-unit-files "${service_name}.service" >/dev/null 2>&1
}

# Check if a service is enabled
is_service_enabled() {
    local service_name="$1"
    
    if [[ -z "$service_name" ]]; then
        return 1
    fi
    
    systemctl is-enabled "${service_name}.service" >/dev/null 2>&1
}

# Check if a service is running
is_service_running() {
    local service_name="$1"
    
    if [[ -z "$service_name" ]]; then
        return 1
    fi
    
    systemctl is-active "${service_name}.service" >/dev/null 2>&1
}

# Enable a service
enable_service() {
    local service_name="$1"
    local auto_start="${2:-false}"
    
    if [[ -z "$service_name" ]]; then
        log_error "Service name is required"
        return 1
    fi
    
    if ! is_service_available "$service_name"; then
        log_error "Service not available: $service_name"
        return 1
    fi
    
    if is_service_enabled "$service_name"; then
        log_info "Service $service_name is already enabled"
        return 0
    fi
    
    # Enable the service
    if ! sudo systemctl enable "$service_name"; then
        log_error "Failed to enable service: $service_name"
        return 1
    fi

    log_success "Service $service_name enabled"
    
    # Start the service if requested
    if [[ "$auto_start" == "true" ]]; then
        sudo systemctl start "$service_name"
    fi
    
    return 0
}

# Disable a service
disable_service() {
    local service_name="$1"
    local auto_stop="${2:-false}"
    
    if [[ -z "$service_name" ]]; then
        return 1
    fi
    
    if ! is_service_enabled "$service_name"; then
        return 0
    fi
    
    # Stop the service if requested and running
    if [[ "$auto_stop" == "true" ]] && is_service_running "$service_name"; then
        sudo systemctl stop "$service_name"
    fi
    
    # Disable the service
    sudo systemctl disable "$service_name"
}

# Configure desktop environment integration
configure_desktop_integration() {
    local desktop_env="${1:-hyprland}"
    
    case "$desktop_env" in
        "hyprland")
            configure_hyprland_integration
            ;;
        *)
            return 1
            ;;
    esac
}

# Configure Hyprland desktop integration
configure_hyprland_integration() {
    log_info "Setting up Hyprland desktop integration..."
    
    # Create Wayland session file
    local session_file="/usr/share/wayland-sessions/hyprland.desktop"
    if [[ ! -f "$session_file" ]]; then
            sudo tee "$session_file" > /dev/null << 'EOF'
[Desktop Entry]
Name=Hyprland
Comment=An intelligent dynamic tiling Wayland compositor
Exec=Hyprland
Type=Application
EOF
            log_success "Created Hyprland session file"
        else
            log_info "Hyprland session file already exists"
        fi
    
    # Set up environment variables for Wayland
    configure_wayland_environment
}

# Configure Wayland environment variables
configure_wayland_environment() {
    local env_file="$HOME/.config/environment.d/wayland.conf"

    log_info "Configuring Wayland environment variables..."
    
    # Create environment.d directory
    mkdir -p "$(dirname "$env_file")"
    
    # Create Wayland environment configuration
    cat > "$env_file" << 'EOF'
# Wayland environment variables
XDG_SESSION_TYPE=wayland
XDG_CURRENT_DESKTOP=Hyprland
XDG_SESSION_DESKTOP=Hyprland

# Qt Wayland support
QT_QPA_PLATFORM=wayland
QT_WAYLAND_DISABLE_WINDOWDECORATION=1

# GTK Wayland support
GDK_BACKEND=wayland

# Firefox Wayland support
MOZ_ENABLE_WAYLAND=1

# Java applications Wayland support
_JAVA_AWT_WM_NONREPARENTING=1
EOF

    log_success "Created Wayland environment configuration"
}

# Add user to system groups
add_user_to_groups() {
    local groups=("$@")
    local current_user
    current_user=$(whoami)
    
    if [[ ${#groups[@]} -eq 0 ]]; then
        return 0
    fi

    log_info "Adding user $current_user to groups: ${groups[*]}"
    
    for group in "${groups[@]}"; do
        # Check if group exists
        if ! getent group "$group" >/dev/null 2>&1; then
            continue
        fi
        
        # Check if user is already in group
        if groups "$current_user" | grep -q "\b$group\b"; then
            continue
        fi
        
        sudo usermod -aG "$group" "$current_user"
    done

    log_info "Note: Group changes will take effect after logging out and back in"
}

# Export functions
export -f is_service_available
export -f is_service_enabled
export -f is_service_running
export -f enable_service
export -f disable_service
export -f configure_desktop_integration
export -f configure_hyprland_integration
export -f configure_wayland_environment
export -f add_user_to_groups