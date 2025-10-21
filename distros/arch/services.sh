#!/usr/bin/env bash

# Arch Linux Service Management
# Handles systemd service configuration

# Initialize all project paths
source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"

# Source core utilities
source "$CORE_DIR/common.sh"
source "$CORE_DIR/logger.sh"
source "$CORE_DIR/service-manager.sh"

# Configure services for installed components
arch_configure_services() {
    local components=("$@")
    
    log_info "Configuring Arch Linux services..."

    # Configure services for each component
    for component in "${components[@]}"; do
        arch_configure_component_services "$component"
    done
    
    # Configure system-wide services
    arch_configure_system_services
}

# Configure services for a specific component
# Arguments: $1=component_name
arch_configure_component_services() {
    local component="$1"
    
    case "$component" in
        "hyprland"|"wm")
            arch_configure_wayland_services
            ;;
        "docker")
            arch_configure_docker_service
            ;;
        *)
            return 0
            ;;
    esac
}

# Configure system-wide services
arch_configure_system_services() {
    # Time synchronization
    enable_service "systemd-timesyncd" true
    
    # Network management
    enable_service "NetworkManager" true
    
    # Package cache cleanup
    # enable_service "paccache.timer" true
    
    enable_service "bluetooth" true

    enable_service "sshd" true

    # Firewall service
    arch_configure_firewall_service

    # Audio services
    arch_configure_audio_services

    arch_configure_display_manager_services
}

# Configure Wayland/Hyprland services
arch_configure_wayland_services() {
    enable_service "xdg-desktop-portal" true
    enable_service "xdg-desktop-portal-hyprland" true
    enable_service "xdg-desktop-portal-gtk" true
    
    # Wayland compositor session
    # configure_desktop_integration "hyprland"
    
    # Configure user groups for Wayland
    local wayland_groups=("video" "input" "render")
    add_user_to_groups "${wayland_groups[@]}"
}

# Configure Docker service
arch_configure_docker_service() {
    enable_service "docker" true
    add_user_to_groups docker
    enable_service "containerd" true
}

# Configure firewall service
arch_configure_firewall_service() {
    if is_service_available "ufw"; then
        enable_service "ufw" true
    elif is_service_available "firewalld"; then
        enable_service "firewalld" true
    fi
}

# Configure audio services
arch_configure_audio_services() {
    # PipeWire (modern audio system)
    enable_service "pipewire" true
    enable_service "pipewire-pulse" true
    enable_service "wireplumber" true
    
    # PulseAudio (traditional audio system)
    enable_service "pulseaudio" true
    
    # Add user to audio group
    add_user_to_groups "audio"
}

# Configure display manager services
arch_configure_display_manager_services() {
    log_info "Enabling GDM display manager for Hyprland"

    if ! enable_service "gdm" true; then
        log_info "GDM not installed. You can start Hyprland directly from TTY."
    fi
}

# Export Arch service function
export -f arch_configure_services