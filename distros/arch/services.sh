#!/bin/bash

# Arch Linux service management
# Handles systemd service configuration without auto-starting

# Configure Arch Linux services
configure_arch_services() {
    log_info "Configuring system services..."
    
    # List of services that can be optionally enabled
    local available_services=(
        "NetworkManager:Network management"
        "bluetooth:Bluetooth support"
        "cups:Printing support"
        "docker:Docker container service"
        "sshd:SSH daemon"
    )
    
    log_info "Available services (not auto-enabled):"
    for service_info in "${available_services[@]}"; do
        local service="${service_info%:*}"
        local description="${service_info#*:}"
        echo "  - $service: $description"
    done
    
    echo
    log_info "Services are not automatically enabled. You can enable them manually with:"
    log_info "  sudo systemctl enable <service-name>"
    log_info "  sudo systemctl start <service-name>"
}

# Check service status
check_service_status() {
    local service="$1"
    
    if systemctl is-active --quiet "$service"; then
        echo "active"
    elif systemctl is-enabled --quiet "$service"; then
        echo "enabled"
    else
        echo "inactive"
    fi
}

# List all available services
list_available_services() {
    log_section "Available System Services"
    
    local services=(
        "NetworkManager"
        "bluetooth"
        "cups"
        "docker"
        "sshd"
        "lightdm"
        "gdm"
        "sddm"
    )
    
    echo "Service status:"
    echo
    
    for service in "${services[@]}"; do
        local status=$(check_service_status "$service")
        case "$status" in
            "active")
                echo -e "  ${GREEN}●${NC} $service (active)"
                ;;
            "enabled")
                echo -e "  ${YELLOW}●${NC} $service (enabled, not running)"
                ;;
            *)
                echo -e "  ${RED}●${NC} $service (inactive)"
                ;;
        esac
    done
}

# Enable service (with user confirmation)
enable_service() {
    local service="$1"
    local description="${2:-$service}"
    
    if ask_yes_no "Enable $description service ($service)?"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY-RUN] Would enable service: $service"
            return 0
        fi
        
        sudo systemctl enable "$service"
        log_success "Service $service enabled"
        
        if ask_yes_no "Start $service now?"; then
            sudo systemctl start "$service"
            log_success "Service $service started"
        fi
    fi
}

# Disable service
disable_service() {
    local service="$1"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would disable service: $service"
        return 0
    fi
    
    sudo systemctl disable "$service"
    sudo systemctl stop "$service" 2>/dev/null || true
    log_info "Service $service disabled and stopped"
}

# Configure user services
configure_user_services() {
    log_info "Configuring user services..."
    
    # User services that might be useful
    local user_services=(
        "pipewire:Audio server"
        "pipewire-pulse:PulseAudio compatibility"
        "wireplumber:Session manager for PipeWire"
    )
    
    for service_info in "${user_services[@]}"; do
        local service="${service_info%:*}"
        local description="${service_info#*:}"
        
        if systemctl --user list-unit-files "$service.service" >/dev/null 2>&1; then
            if ask_yes_no "Enable user service: $description ($service)?"; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    log_info "[DRY-RUN] Would enable user service: $service"
                else
                    systemctl --user enable "$service"
                    log_success "User service $service enabled"
                fi
            fi
        fi
    done
}

# Create service management script
create_service_manager() {
    local script_path="$HOME/.local/bin/manage-services"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create service management script"
        return 0
    fi
    
    mkdir -p "$(dirname "$script_path")"
    
    cat > "$script_path" << 'EOF'
#!/bin/bash
# Service management helper script

show_usage() {
    echo "Usage: $0 [list|enable|disable|status] [service-name]"
    echo
    echo "Commands:"
    echo "  list     - List all services and their status"
    echo "  enable   - Enable and optionally start a service"
    echo "  disable  - Disable and stop a service"
    echo "  status   - Show status of a specific service"
}

case "$1" in
    list)
        systemctl list-unit-files --type=service
        ;;
    enable)
        if [[ -z "$2" ]]; then
            echo "Error: Service name required"
            exit 1
        fi
        sudo systemctl enable "$2"
        read -p "Start service now? [y/N]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo systemctl start "$2"
        fi
        ;;
    disable)
        if [[ -z "$2" ]]; then
            echo "Error: Service name required"
            exit 1
        fi
        sudo systemctl disable "$2"
        sudo systemctl stop "$2"
        ;;
    status)
        if [[ -z "$2" ]]; then
            echo "Error: Service name required"
            exit 1
        fi
        systemctl status "$2"
        ;;
    *)
        show_usage
        ;;
esac
EOF
    
    chmod +x "$script_path"
    log_success "Service management script created at $script_path"
}