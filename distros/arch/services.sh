#!/bin/bash

# Arch Linux Service Management
# Handles systemd service configuration without auto-enabling

# Source core utilities
source "$(dirname "${BASH_SOURCE[0]}")/../../core/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../core/logger.sh"

# Configure services for installed components (but don't enable them)
arch_configure_services() {
    local components=("$@")
    
    log_info "Configuring services for installed components..."
    
    for component in "${components[@]}"; do
        arch_configure_component_services "$component"
    done
    
    # Show available services that can be manually enabled
    arch_show_available_services "${components[@]}"
    
    log_success "Service configuration completed"
}

# Configure services for a specific component
arch_configure_component_services() {
    local component="$1"
    
    log_info "Configuring services for component: $component"
    
    case "$component" in
        "docker")
            arch_configure_docker_service
            ;;
        "bluetooth")
            arch_configure_bluetooth_service
            ;;
        "networkmanager")
            arch_configure_networkmanager_service
            ;;
        "sshd")
            arch_configure_ssh_service
            ;;
        "cups")
            arch_configure_printing_service
            ;;
        "firewall")
            arch_configure_firewall_service
            ;;
        "timesyncd")
            arch_configure_time_service
            ;;
        *)
            log_info "No specific service configuration for: $component"
            ;;
    esac
}

# Configure Docker service
arch_configure_docker_service() {
    log_info "Configuring Docker service..."
    
    # Add user to docker group if docker is installed
    if arch_is_service_available "docker"; then
        local current_user
        current_user=$(whoami)
        
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            log_info "[DRY RUN] Would add user $current_user to docker group"
        else
            if ! sudo usermod -aG docker "$current_user"; then
                log_warn "Failed to add user to docker group"
            else
                log_info "User $current_user added to docker group"
                log_info "Note: You may need to log out and back in for group changes to take effect"
            fi
        fi
        
        arch_register_service "docker" "Docker container runtime" "optional"
    fi
}

# Configure Bluetooth service
arch_configure_bluetooth_service() {
    log_info "Configuring Bluetooth service..."
    
    if arch_is_service_available "bluetooth"; then
        arch_register_service "bluetooth" "Bluetooth connectivity" "optional"
    fi
}

# Configure NetworkManager service
arch_configure_networkmanager_service() {
    log_info "Configuring NetworkManager service..."
    
    if arch_is_service_available "NetworkManager"; then
        arch_register_service "NetworkManager" "Network connection management" "recommended"
    fi
}

# Configure SSH service
arch_configure_ssh_service() {
    log_info "Configuring SSH service..."
    
    if arch_is_service_available "sshd"; then
        # Configure SSH for security
        local sshd_config="/etc/ssh/sshd_config"
        
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            log_info "[DRY RUN] Would configure SSH security settings"
        else
            # Create backup of SSH config
            if [[ -f "$sshd_config" ]]; then
                sudo cp "$sshd_config" "$sshd_config.backup.$(date +%Y%m%d_%H%M%S)"
                
                # Apply basic security settings
                sudo sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' "$sshd_config"
                sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' "$sshd_config"
                
                log_info "SSH security settings configured"
            fi
        fi
        
        arch_register_service "sshd" "SSH server for remote access" "optional"
    fi
}

# Configure printing service
arch_configure_printing_service() {
    log_info "Configuring printing service..."
    
    if arch_is_service_available "cups"; then
        arch_register_service "cups" "Printing system" "optional"
    fi
}

# Configure firewall service
arch_configure_firewall_service() {
    log_info "Configuring firewall service..."
    
    if arch_is_service_available "ufw"; then
        arch_register_service "ufw" "Uncomplicated Firewall" "recommended"
    elif arch_is_service_available "firewalld"; then
        arch_register_service "firewalld" "Dynamic firewall management" "recommended"
    fi
}

# Configure time synchronization service
arch_configure_time_service() {
    log_info "Configuring time synchronization service..."
    
    if arch_is_service_available "systemd-timesyncd"; then
        arch_register_service "systemd-timesyncd" "Network time synchronization" "recommended"
    fi
}

# Check if a service is available
arch_is_service_available() {
    local service_name="$1"
    systemctl list-unit-files "$service_name.service" >/dev/null 2>&1
}

# Check if a service is enabled
arch_is_service_enabled() {
    local service_name="$1"
    systemctl is-enabled "$service_name.service" >/dev/null 2>&1
}

# Check if a service is running
arch_is_service_running() {
    local service_name="$1"
    systemctl is-active "$service_name.service" >/dev/null 2>&1
}

# Register a service for later manual management
arch_register_service() {
    local service_name="$1"
    local description="$2"
    local priority="${3:-optional}"  # optional, recommended, required
    
    # Create services registry file if it doesn't exist
    local services_file="/tmp/arch_services_registry.txt"
    
    if [[ ! -f "$services_file" ]]; then
        echo "# Arch Linux Services Registry" > "$services_file"
        echo "# Format: service_name|description|priority|status" >> "$services_file"
    fi
    
    local status="disabled"
    if arch_is_service_enabled "$service_name"; then
        status="enabled"
    fi
    
    # Add or update service entry
    if grep -q "^$service_name|" "$services_file"; then
        # Update existing entry
        sed -i "s|^$service_name|.*|$service_name|$description|$priority|$status|" "$services_file"
    else
        # Add new entry
        echo "$service_name|$description|$priority|$status" >> "$services_file"
    fi
}

# Show available services that can be manually enabled
arch_show_available_services() {
    local components=("$@")
    
    log_info "=== Available Services ==="
    log_info "The following services are available but NOT automatically enabled:"
    log_info ""
    
    local services_file="/tmp/arch_services_registry.txt"
    
    if [[ -f "$services_file" ]]; then
        while IFS='|' read -r service_name description priority status; do
            # Skip comments
            [[ "$service_name" =~ ^# ]] && continue
            
            local status_color=""
            local priority_text=""
            
            case "$priority" in
                "required")
                    priority_text="[REQUIRED]"
                    ;;
                "recommended")
                    priority_text="[RECOMMENDED]"
                    ;;
                "optional")
                    priority_text="[OPTIONAL]"
                    ;;
            esac
            
            if [[ "$status" == "enabled" ]]; then
                status_color="$(tput setaf 2)"  # Green
            else
                status_color="$(tput setaf 3)"  # Yellow
            fi
            
            printf "  %s%-20s%s %s - %s (%s)\n" \
                "$status_color" "$service_name" "$(tput sgr0)" \
                "$priority_text" "$description" "$status"
                
        done < "$services_file"
    fi
    
    log_info ""
    log_info "To enable a service manually:"
    log_info "  sudo systemctl enable <service_name>"
    log_info "  sudo systemctl start <service_name>"
    log_info ""
    log_info "To check service status:"
    log_info "  systemctl status <service_name>"
}

# Enable a service manually (with user confirmation)
arch_enable_service() {
    local service_name="$1"
    local auto_start="${2:-false}"
    
    if [[ -z "$service_name" ]]; then
        log_error "Service name is required"
        return 1
    fi
    
    if ! arch_is_service_available "$service_name"; then
        log_error "Service not available: $service_name"
        return 1
    fi
    
    if arch_is_service_enabled "$service_name"; then
        log_info "Service $service_name is already enabled"
        return 0
    fi
    
    log_info "Enabling service: $service_name"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would enable service: $service_name"
        if [[ "$auto_start" == "true" ]]; then
            log_info "[DRY RUN] Would start service: $service_name"
        fi
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
        if ! sudo systemctl start "$service_name"; then
            log_warn "Failed to start service: $service_name"
            return 1
        fi
        log_success "Service $service_name started"
    fi
    
    return 0
}

# Disable a service
arch_disable_service() {
    local service_name="$1"
    local auto_stop="${2:-false}"
    
    if [[ -z "$service_name" ]]; then
        log_error "Service name is required"
        return 1
    fi
    
    if ! arch_is_service_enabled "$service_name"; then
        log_info "Service $service_name is already disabled"
        return 0
    fi
    
    log_info "Disabling service: $service_name"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would disable service: $service_name"
        if [[ "$auto_stop" == "true" ]]; then
            log_info "[DRY RUN] Would stop service: $service_name"
        fi
        return 0
    fi
    
    # Stop the service if requested
    if [[ "$auto_stop" == "true" ]] && arch_is_service_running "$service_name"; then
        if ! sudo systemctl stop "$service_name"; then
            log_warn "Failed to stop service: $service_name"
        else
            log_info "Service $service_name stopped"
        fi
    fi
    
    # Disable the service
    if ! sudo systemctl disable "$service_name"; then
        log_error "Failed to disable service: $service_name"
        return 1
    fi
    
    log_success "Service $service_name disabled"
    return 0
}

# Get service status
arch_get_service_status() {
    local service_name="$1"
    
    if [[ -z "$service_name" ]]; then
        log_error "Service name is required"
        return 1
    fi
    
    if ! arch_is_service_available "$service_name"; then
        echo "not-available"
        return 1
    fi
    
    local enabled_status="disabled"
    local running_status="stopped"
    
    if arch_is_service_enabled "$service_name"; then
        enabled_status="enabled"
    fi
    
    if arch_is_service_running "$service_name"; then
        running_status="running"
    fi
    
    echo "$enabled_status,$running_status"
    return 0
}

# List all services with their status
arch_list_all_services() {
    log_info "=== System Services Status ==="
    
    # Get all available services
    systemctl list-unit-files --type=service --no-pager --no-legend | while read -r service_file state; do
        local service_name="${service_file%.service}"
        local status
        status=$(arch_get_service_status "$service_name")
        
        if [[ $? -eq 0 ]]; then
            local enabled_status="${status%,*}"
            local running_status="${status#*,}"
            
            printf "  %-30s %s/%s\n" "$service_name" "$enabled_status" "$running_status"
        fi
    done
}

# Export functions for external use
export -f arch_configure_services
export -f arch_configure_component_services
export -f arch_is_service_available
export -f arch_is_service_enabled
export -f arch_is_service_running
export -f arch_register_service
export -f arch_show_available_services
export -f arch_enable_service
export -f arch_disable_service
export -f arch_get_service_status
export -f arch_list_all_services