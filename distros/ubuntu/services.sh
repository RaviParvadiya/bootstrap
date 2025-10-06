#!/usr/bin/env bash

# Ubuntu Service Management
# Handles systemd service configuration for Ubuntu without auto-enabling

# Initialize all project paths
source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"

# Source core utilities
source "$CORE_DIR/common.sh"
source "$CORE_DIR/logger.sh"
source "$CORE_DIR/service-manager.sh"

#######################################
# Ubuntu Service Configuration
#######################################

# Configure services for installed components (but don't enable them)
# Arguments: Array of installed components
ubuntu_configure_services() {
    local components=("$@")
    
    log_info "Configuring Ubuntu services for installed components..."
    
    # Configure services for each component
    for component in "${components[@]}"; do
        ubuntu_configure_component_services "$component"
    done
    
    # Configure system-wide services that might be needed
    ubuntu_configure_system_services
    
    log_success "Ubuntu service configuration completed"
}

# Configure services for a specific component
# Arguments: $1=component_name
ubuntu_configure_component_services() {
    local component="$1"
    
    log_info "Configuring Ubuntu services for component: $component"
    
    case "$component" in
        "hyprland"|"wm")
            ubuntu_configure_wayland_services
            ;;
        "docker")
            ubuntu_configure_docker_service
            ;;
        "bluetooth")
            ubuntu_configure_bluetooth_service
            ;;
        "networkmanager")
            ubuntu_configure_networkmanager_service
            ;;
        "ssh"|"sshd")
            ubuntu_configure_ssh_service
            ;;
        "firewall")
            ubuntu_configure_firewall_service
            ;;
        "audio"|"pipewire"|"pulseaudio")
            ubuntu_configure_audio_services
            ;;
        "display")
            ubuntu_configure_display_manager_services
            ;;
        *)
            log_debug "No specific service configuration for Ubuntu component: $component"
            ;;
    esac
}

# Configure system-wide services
ubuntu_configure_system_services() {
    # Time synchronization
    enable_service "systemd-timesyncd" true
    
    # Network management
    enable_service "NetworkManager" true
    
    # System logging
    enable_service "rsyslog" true
    
    # Automatic updates (usually disabled by default, which is good)
    enable_service "unattended-upgrades" true
}

# Configure Wayland/Hyprland services
ubuntu_configure_wayland_services() {
    enable_service "xdg-desktop-portal" true
    enable_service "xdg-desktop-portal-hyprland" true
    enable_service "xdg-desktop-portal-gtk" true
    
    # Wayland compositor session
    configure_desktop_integration "hyprland"
    
    # Configure user groups for Wayland
    local wayland_groups=("video" "input" "render")
    add_user_to_groups "${wayland_groups[@]}"
}

# Configure Docker service
ubuntu_configure_docker_service() {
    enable_service "docker" true
    add_user_to_groups docker
    enable_service "containerd" true
}

# Configure Bluetooth service
ubuntu_configure_bluetooth_service() {
    enable_service "bluetooth" true
        
    # Add user to bluetooth group if it exists
    if getent group bluetooth >/dev/null 2>&1; then
        add_user_to_groups "bluetooth"
    fi
}

# Configure NetworkManager service
ubuntu_configure_networkmanager_service() {
    enable_service "NetworkManager" true
}

# Configure SSH service
ubuntu_configure_ssh_service() {
    enable_service "ssh" true
}

# Configure firewall service
ubuntu_configure_firewall_service() {
    if is_service_available "ufw"; then
        enable_service "ufw" true
    elif is_service_available "firewalld"; then
        enable_service "firewalld" true
    fi
}

# Configure audio services
ubuntu_configure_audio_services() {
    # PipeWire (modern audio system)
    enable_service "pipewire" true
    enable_service "pipewire-pulse" true
    enable_service "wireplumber" true
    
    # ALSA state management
    enable_service "alsa-state" true
    
    # Add user to audio group
    add_user_to_groups "audio"
}

# Configure display manager services
ubuntu_configure_display_manager_services() {
    log_info "Enabling GDM display manager for Hyprland"

    if ! enable_service "gdm3" true; then
        log_info "GDM not installed. You can start Hyprland directly from TTY."
    fi
}

# Export Ubuntu service function
export -f ubuntu_configure_services