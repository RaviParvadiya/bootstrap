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
    
    # Initialize service registry
    init_service_registry
    
    # Configure services for each component
    for component in "${components[@]}"; do
        ubuntu_configure_component_services "$component"
    done
    
    # Configure system-wide services that might be needed
    ubuntu_configure_system_services
    
    # Show available services summary
    ubuntu_show_service_summary "${components[@]}"
    
    log_success "Ubuntu service configuration completed"
}

# Configure services for a specific component
# Arguments: $1=component_name
ubuntu_configure_component_services() {
    local component="$1"
    
    log_info "Configuring Ubuntu services for component: $component"
    
    case "$component" in
        "hyprland"|"wm")
            ubuntu_configure_wayland_services "$component"
            ;;
        "docker")
            ubuntu_configure_docker_service "$component"
            ;;
        "bluetooth")
            ubuntu_configure_bluetooth_service "$component"
            ;;
        "networkmanager")
            ubuntu_configure_networkmanager_service "$component"
            ;;
        "ssh"|"sshd")
            ubuntu_configure_ssh_service "$component"
            ;;
        "cups"|"printing")
            ubuntu_configure_printing_service "$component"
            ;;
        "firewall")
            ubuntu_configure_firewall_service "$component"
            ;;
        "audio"|"pipewire"|"pulseaudio")
            ubuntu_configure_audio_services "$component"
            ;;
        "display")
            ubuntu_configure_display_manager_services "$component"
            ;;
        *)
            log_debug "No specific service configuration for Ubuntu component: $component"
            ;;
    esac
}

# Configure system-wide services
ubuntu_configure_system_services() {
    log_info "Configuring Ubuntu system services..."
    
    # Time synchronization
    if is_service_available "systemd-timesyncd"; then
        register_service "systemd-timesyncd" "Network time synchronization" "recommended" "system" "conditional"
    fi
    
    # Network management
    if is_service_available "NetworkManager"; then
        register_service "NetworkManager" "Network connection management" "recommended" "system" "conditional"
    fi
    
    # System logging
    if is_service_available "rsyslog"; then
        register_service "rsyslog" "System logging service" "recommended" "system" "conditional"
    fi
    
    # Automatic updates (usually disabled by default, which is good)
    if is_service_available "unattended-upgrades"; then
        register_service "unattended-upgrades" "Automatic security updates" "optional" "system" "never"
    fi
}

#######################################
# Component-Specific Service Configuration
#######################################

# Configure Wayland/Hyprland services
ubuntu_configure_wayland_services() {
    local component="$1"
    
    log_info "Configuring Wayland services for Ubuntu..."
    
    # XDG Desktop Portal
    if is_service_available "xdg-desktop-portal"; then
        register_service "xdg-desktop-portal" "Desktop integration portal" "recommended" "$component" "conditional"
    fi
    
    if is_service_available "xdg-desktop-portal-hyprland"; then
        register_service "xdg-desktop-portal-hyprland" "Hyprland desktop portal" "recommended" "$component" "conditional"
    fi
    
    if is_service_available "xdg-desktop-portal-gtk"; then
        register_service "xdg-desktop-portal-gtk" "GTK desktop portal" "recommended" "$component" "conditional"
    fi
    
    # Wayland compositor session
    configure_desktop_integration "hyprland" "$component"
    
    # Configure user groups for Wayland
    local wayland_groups=("video" "input" "render")
    add_user_to_groups "${wayland_groups[@]}"
}

# Configure Docker service
ubuntu_configure_docker_service() {
    local component="$1"
    
    log_info "Configuring Docker service for Ubuntu..."
    
    if is_service_available "docker"; then
        register_service "docker" "Docker container runtime" "optional" "$component" "never"
        
        # Add user to docker group
        add_user_to_groups "docker"
        
        log_info "Docker service registered but not enabled"
        log_info "To use Docker, enable and start the service manually:"
        log_info "  sudo systemctl enable docker"
        log_info "  sudo systemctl start docker"
    fi
    
    if is_service_available "containerd"; then
        register_service "containerd" "Container runtime" "optional" "$component" "never"
    fi
}

# Configure Bluetooth service
ubuntu_configure_bluetooth_service() {
    local component="$1"
    
    log_info "Configuring Bluetooth service for Ubuntu..."
    
    if is_service_available "bluetooth"; then
        register_service "bluetooth" "Bluetooth connectivity" "optional" "$component" "never"
        
        # Add user to bluetooth group if it exists
        if getent group bluetooth >/dev/null 2>&1; then
            add_user_to_groups "bluetooth"
        fi
        
        log_info "Bluetooth service registered but not enabled"
        log_info "To use Bluetooth, enable the service manually:"
        log_info "  sudo systemctl enable bluetooth"
    fi
}

# Configure NetworkManager service
ubuntu_configure_networkmanager_service() {
    local component="$1"
    
    log_info "Configuring NetworkManager service for Ubuntu..."
    
    if is_service_available "NetworkManager"; then
        # NetworkManager is usually enabled by default on Ubuntu, but we register it
        register_service "NetworkManager" "Network connection management" "recommended" "$component" "conditional"
        
        log_info "NetworkManager service registered"
        log_info "Note: NetworkManager is typically enabled by default on Ubuntu"
    fi
    
    # Network-related services
    if is_service_available "systemd-networkd"; then
        register_service "systemd-networkd" "Systemd network management" "optional" "$component" "never"
    fi
    
    if is_service_available "systemd-resolved"; then
        register_service "systemd-resolved" "DNS resolution service" "recommended" "$component" "conditional"
    fi
}

# Configure SSH service
ubuntu_configure_ssh_service() {
    local component="$1"
    
    log_info "Configuring SSH service for Ubuntu..."
    
    if is_service_available "ssh"; then
        register_service "ssh" "SSH server for remote access" "optional" "$component" "never"
        
        # Configure SSH security settings
        ubuntu_configure_ssh_security
        
        log_info "SSH service registered but not enabled"
        log_info "To enable SSH access, start the service manually:"
        log_info "  sudo systemctl enable ssh"
        log_info "  sudo systemctl start ssh"
    fi
}

# Configure SSH security settings
ubuntu_configure_ssh_security() {
    local sshd_config="/etc/ssh/sshd_config"
    
    if [[ ! -f "$sshd_config" ]]; then
        log_warn "SSH configuration file not found: $sshd_config"
        return 1
    fi
    
    log_info "Configuring SSH security settings..."
    
    # Create backup of SSH config
    local backup_file="$sshd_config.backup.$(date +%Y%m%d_%H%M%S)"
    sudo cp "$sshd_config" "$backup_file"
    log_info "Created SSH config backup: $backup_file"
    
    # Apply security settings (only if not already configured)
    local changes_made=false
    
    # Disable root login
    if ! grep -q "^PermitRootLogin no" "$sshd_config"; then
        sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' "$sshd_config"
        changes_made=true
    fi
    
    # Configure password authentication (keep enabled for Ubuntu)
    if ! grep -q "^PasswordAuthentication yes" "$sshd_config"; then
        sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$sshd_config"
        changes_made=true
    fi
    
    # Disable empty passwords
    if ! grep -q "^PermitEmptyPasswords no" "$sshd_config"; then
        sudo sed -i 's/^#*PermitEmptyPasswords.*/PermitEmptyPasswords no/' "$sshd_config"
        changes_made=true
    fi
    
    if [[ "$changes_made" == "true" ]]; then
        log_success "SSH security settings configured"
        register_system_integration "security_config" "ssh_security" "SSH security configuration applied" "ssh"
    else
        log_info "SSH security settings already configured"
    fi
}

# Configure printing service
ubuntu_configure_printing_service() {
    local component="$1"
    
    log_info "Configuring printing service for Ubuntu..."
    
    if is_service_available "cups"; then
        register_service "cups" "Common Unix Printing System" "optional" "$component" "never"
        
        # Add user to lpadmin group for printer management
        add_user_to_groups "lpadmin"
        
        log_info "CUPS printing service registered but not enabled"
        log_info "To enable printing, start CUPS manually:"
        log_info "  sudo systemctl enable cups"
        log_info "  sudo systemctl start cups"
    fi
    
    if is_service_available "cups-browsed"; then
        register_service "cups-browsed" "CUPS printer discovery" "optional" "$component" "never"
    fi
}

# Configure firewall service
ubuntu_configure_firewall_service() {
    local component="$1"
    
    log_info "Configuring firewall service for Ubuntu..."
    
    # UFW (Uncomplicated Firewall) - Ubuntu's default
    if is_service_available "ufw"; then
        register_service "ufw" "Uncomplicated Firewall" "recommended" "$component" "never"
        
        log_info "UFW firewall service registered but not enabled"
        log_info "To enable firewall protection:"
        log_info "  sudo ufw enable"
        log_info "  sudo systemctl enable ufw"
    fi
    
    # Alternative: firewalld
    if is_service_available "firewalld"; then
        register_service "firewalld" "Dynamic firewall management" "optional" "$component" "never"
    fi
    
    # iptables-persistent for custom rules
    if is_service_available "netfilter-persistent"; then
        register_service "netfilter-persistent" "Persistent iptables rules" "optional" "$component" "never"
    fi
}

# Configure audio services
ubuntu_configure_audio_services() {
    local component="$1"
    
    log_info "Configuring audio services for Ubuntu..."
    
    # PipeWire (modern audio system)
    if is_service_available "pipewire"; then
        register_service "pipewire" "PipeWire multimedia server" "recommended" "$component" "conditional"
    fi
    
    if is_service_available "pipewire-pulse"; then
        register_service "pipewire-pulse" "PipeWire PulseAudio compatibility" "recommended" "$component" "conditional"
    fi
    
    if is_service_available "wireplumber"; then
        register_service "wireplumber" "PipeWire session manager" "recommended" "$component" "conditional"
    fi
    
    # PulseAudio (traditional audio system)
    if is_service_available "pulseaudio"; then
        register_service "pulseaudio" "PulseAudio sound server" "optional" "$component" "conditional"
    fi
    
    # ALSA state management
    if is_service_available "alsa-state"; then
        register_service "alsa-state" "ALSA sound card state management" "recommended" "$component" "conditional"
    fi
    
    # Add user to audio group
    add_user_to_groups "audio"
}

# Configure display manager services
ubuntu_configure_display_manager_services() {
    local component="$1"
    
    log_info "Configuring display manager services for Ubuntu..."
    
    # GDM (GNOME Display Manager)
    if is_service_available "gdm3"; then
        register_service "gdm3" "GNOME Display Manager" "optional" "$component" "never"
    fi
    
    # LightDM (lightweight display manager)
    if is_service_available "lightdm"; then
        register_service "lightdm" "Light Display Manager" "optional" "$component" "never"
    fi
    
    # SDDM (Simple Desktop Display Manager)
    if is_service_available "sddm"; then
        register_service "sddm" "Simple Desktop Display Manager" "optional" "$component" "never"
    fi
    
    log_info "Display manager services registered but not enabled"
    log_info "Note: Only enable one display manager at a time"
    log_info "For Hyprland, you can start it directly from TTY without a display manager"
}

#######################################
# Ubuntu Service Management Utilities
#######################################

# Show Ubuntu service summary
ubuntu_show_service_summary() {
    local components=("$@")
    
    log_info "=== Ubuntu Service Configuration Summary ==="
    log_info ""
    log_info "Configured components: ${components[*]}"
    log_info ""
    
    # Show service status
    show_service_status
    
    log_info "Ubuntu Service Management Notes:"
    log_info "• Services are configured but NOT automatically enabled"
    log_info "• This follows the principle of manual service control"
    log_info "• Enable only the services you actually need"
    log_info "• Some services (like NetworkManager) may already be enabled by Ubuntu"
    log_info ""
    log_info "Common Ubuntu service commands:"
    log_info "  sudo systemctl enable <service>   # Enable service to start at boot"
    log_info "  sudo systemctl start <service>    # Start service now"
    log_info "  sudo systemctl status <service>   # Check service status"
    log_info "  sudo systemctl disable <service>  # Disable service from starting at boot"
    log_info "  sudo systemctl stop <service>     # Stop running service"
    log_info ""
}

# Check Ubuntu-specific service dependencies
ubuntu_check_service_dependencies() {
    local service_name="$1"
    
    case "$service_name" in
        "hyprland")
            # Check for Wayland dependencies
            local wayland_deps=("xdg-desktop-portal" "xdg-desktop-portal-hyprland")
            for dep in "${wayland_deps[@]}"; do
                if ! is_service_available "$dep"; then
                    log_warn "Recommended service not available: $dep"
                fi
            done
            ;;
        "docker")
            # Check for container runtime dependencies
            if ! is_service_available "containerd"; then
                log_warn "Container runtime not available: containerd"
            fi
            ;;
        "bluetooth")
            # Check for Bluetooth stack
            if ! command -v bluetoothctl >/dev/null 2>&1; then
                log_warn "Bluetooth utilities not installed"
            fi
            ;;
    esac
}

# Enable Ubuntu service with dependency checking
ubuntu_enable_service_with_deps() {
    local service_name="$1"
    local auto_start="${2:-false}"
    
    log_info "Enabling Ubuntu service with dependency checking: $service_name"
    
    # Check dependencies first
    ubuntu_check_service_dependencies "$service_name"
    
    # Enable the service
    enable_service_manual "$service_name" "$auto_start"
}

# Show Ubuntu system integration status
ubuntu_show_system_integration() {
    log_info "=== Ubuntu System Integration Status ==="
    log_info ""
    
    # Show general system integration
    show_system_integration_status
    
    # Ubuntu-specific integration checks
    log_info "Ubuntu-Specific Integration:"
    
    # Check if running Wayland
    if [[ "$XDG_SESSION_TYPE" == "wayland" ]]; then
        log_info "  ✓ Running in Wayland session"
    else
        log_info "  ⚠ Not running in Wayland session (current: ${XDG_SESSION_TYPE:-unknown})"
    fi
    
    # Check desktop environment
    if [[ -n "$XDG_CURRENT_DESKTOP" ]]; then
        log_info "  ✓ Desktop environment: $XDG_CURRENT_DESKTOP"
    else
        log_info "  ⚠ No desktop environment detected"
    fi
    
    # Check user groups
    local current_user
    current_user=$(whoami)
    local user_groups
    user_groups=$(groups "$current_user")
    
    local important_groups=("video" "audio" "input" "render" "docker" "lpadmin")
    for group in "${important_groups[@]}"; do
        if echo "$user_groups" | grep -q "\b$group\b"; then
            log_info "  ✓ User in group: $group"
        else
            if getent group "$group" >/dev/null 2>&1; then
                log_info "  ⚠ User not in group: $group (group exists)"
            fi
        fi
    done
    
    log_info ""
}

# Export Ubuntu service functions
export -f ubuntu_configure_services
export -f ubuntu_configure_component_services
export -f ubuntu_configure_system_services
export -f ubuntu_configure_wayland_services
export -f ubuntu_configure_docker_service
export -f ubuntu_configure_bluetooth_service
export -f ubuntu_configure_networkmanager_service
export -f ubuntu_configure_ssh_service
export -f ubuntu_configure_ssh_security
export -f ubuntu_configure_printing_service
export -f ubuntu_configure_firewall_service
export -f ubuntu_configure_audio_services
export -f ubuntu_configure_display_manager_services
export -f ubuntu_show_service_summary
export -f ubuntu_check_service_dependencies
export -f ubuntu_enable_service_with_deps
export -f ubuntu_show_system_integration