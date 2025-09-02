#!/usr/bin/env bash

# core/service-manager.sh - Universal service management system
# Provides cross-distribution service management with no-auto-start policy
# Requirements: 3.1, 3.2, 3.3, 3.4 - Service management without auto-enabling

# Prevent multiple sourcing
if [[ -n "${SERVICE_MANAGER_SOURCED:-}" ]]; then
    return 0
fi
readonly SERVICE_MANAGER_SOURCED=1

# Source core utilities
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"

# Global service registry
SERVICE_REGISTRY_FILE="/tmp/modular_install_services_registry.txt"
SYSTEM_INTEGRATION_FILE="/tmp/modular_install_system_integration.txt"

#######################################
# Service Registry Management
#######################################

# Initialize service registry
# Creates the service registry file with headers
init_service_registry() {
    log_debug "Initializing service registry: $SERVICE_REGISTRY_FILE"
    
    cat > "$SERVICE_REGISTRY_FILE" << 'EOF'
# Modular Install Framework - Service Registry
# Format: service_name|description|priority|component|distro|status|auto_start_policy
# Priority: required, recommended, optional
# Status: available, enabled, disabled, not-available
# Auto Start Policy: never, manual, conditional
EOF
    
    cat > "$SYSTEM_INTEGRATION_FILE" << 'EOF'
# Modular Install Framework - System Integration Registry
# Format: integration_type|name|description|status|component
# Integration Types: desktop_session, display_manager, environment_var, user_group
EOF
}

# Register a service in the global registry
# Arguments: $1=service_name, $2=description, $3=priority, $4=component, $5=auto_start_policy
# Requirements: 3.1 - Service management functions that respect no-auto-start requirement
register_service() {
    local service_name="$1"
    local description="$2"
    local priority="${3:-optional}"
    local component="${4:-unknown}"
    local auto_start_policy="${5:-never}"
    local distro
    
    if [[ -z "$service_name" || -z "$description" ]]; then
        log_error "Service name and description are required for registration"
        return 1
    fi
    
    distro=$(get_distro)
    
    # Initialize registry if it doesn't exist
    if [[ ! -f "$SERVICE_REGISTRY_FILE" ]]; then
        init_service_registry
    fi
    
    # Check if service is available on the system
    local status="not-available"
    if is_service_available "$service_name"; then
        if is_service_enabled "$service_name"; then
            status="enabled"
        else
            status="disabled"
        fi
    fi
    
    # Remove existing entry if present
    if [[ -f "$SERVICE_REGISTRY_FILE" ]]; then
        grep -v "^$service_name|" "$SERVICE_REGISTRY_FILE" > "${SERVICE_REGISTRY_FILE}.tmp" || true
        mv "${SERVICE_REGISTRY_FILE}.tmp" "$SERVICE_REGISTRY_FILE"
    fi
    
    # Add new entry
    echo "$service_name|$description|$priority|$component|$distro|$status|$auto_start_policy" >> "$SERVICE_REGISTRY_FILE"
    
    log_debug "Registered service: $service_name ($priority, $auto_start_policy)"
}

# Register system integration
# Arguments: $1=type, $2=name, $3=description, $4=component
register_system_integration() {
    local integration_type="$1"
    local name="$2"
    local description="$3"
    local component="${4:-unknown}"
    local status="configured"
    
    if [[ -z "$integration_type" || -z "$name" || -z "$description" ]]; then
        log_error "Integration type, name, and description are required"
        return 1
    fi
    
    # Initialize registry if it doesn't exist
    if [[ ! -f "$SYSTEM_INTEGRATION_FILE" ]]; then
        init_service_registry
    fi
    
    # Remove existing entry if present
    if [[ -f "$SYSTEM_INTEGRATION_FILE" ]]; then
        grep -v "^$integration_type|$name|" "$SYSTEM_INTEGRATION_FILE" > "${SYSTEM_INTEGRATION_FILE}.tmp" || true
        mv "${SYSTEM_INTEGRATION_FILE}.tmp" "$SYSTEM_INTEGRATION_FILE"
    fi
    
    # Add new entry
    echo "$integration_type|$name|$description|$status|$component" >> "$SYSTEM_INTEGRATION_FILE"
    
    log_debug "Registered system integration: $integration_type/$name for $component"
}

#######################################
# Universal Service Management Functions
#######################################

# Check if a service is available on the system
# Arguments: $1=service_name
# Returns: 0 if available, 1 if not available
is_service_available() {
    local service_name="$1"
    local distro
    
    if [[ -z "$service_name" ]]; then
        return 1
    fi
    
    distro=$(get_distro)
    
    case "$distro" in
        "arch"|"ubuntu")
            systemctl list-unit-files "${service_name}.service" >/dev/null 2>&1
            ;;
        *)
            # Fallback: check if service file exists
            [[ -f "/etc/systemd/system/${service_name}.service" ]] || \
            [[ -f "/usr/lib/systemd/system/${service_name}.service" ]] || \
            [[ -f "/lib/systemd/system/${service_name}.service" ]]
            ;;
    esac
}

# Check if a service is enabled
# Arguments: $1=service_name
# Returns: 0 if enabled, 1 if disabled or not available
is_service_enabled() {
    local service_name="$1"
    
    if [[ -z "$service_name" ]]; then
        return 1
    fi
    
    systemctl is-enabled "${service_name}.service" >/dev/null 2>&1
}

# Check if a service is running
# Arguments: $1=service_name
# Returns: 0 if running, 1 if stopped or not available
is_service_running() {
    local service_name="$1"
    
    if [[ -z "$service_name" ]]; then
        return 1
    fi
    
    systemctl is-active "${service_name}.service" >/dev/null 2>&1
}

# Get comprehensive service status
# Arguments: $1=service_name
# Returns: Echoes status in format "available,enabled,running" or "not-available,disabled,stopped"
get_service_status() {
    local service_name="$1"
    local available="not-available"
    local enabled="disabled"
    local running="stopped"
    
    if [[ -z "$service_name" ]]; then
        echo "error,error,error"
        return 1
    fi
    
    if is_service_available "$service_name"; then
        available="available"
        
        if is_service_enabled "$service_name"; then
            enabled="enabled"
        fi
        
        if is_service_running "$service_name"; then
            running="running"
        fi
    fi
    
    echo "$available,$enabled,$running"
}

#######################################
# Service Control Functions (Manual Only)
#######################################

# Enable a service manually with user confirmation
# Arguments: $1=service_name, $2=auto_start (optional, default=false)
# Requirements: 3.2 - Selective service enabling/disabling with user control
enable_service_manual() {
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
    
    # Get service description from registry
    local description="Unknown service"
    if [[ -f "$SERVICE_REGISTRY_FILE" ]]; then
        local registry_line
        registry_line=$(grep "^$service_name|" "$SERVICE_REGISTRY_FILE" 2>/dev/null || true)
        if [[ -n "$registry_line" ]]; then
            description=$(echo "$registry_line" | cut -d'|' -f2)
        fi
    fi
    
    log_info "Enabling service: $service_name"
    log_info "Description: $description"
    
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
            log_info "Service is enabled but not running. Start manually with: sudo systemctl start $service_name"
            return 1
        fi
        log_success "Service $service_name started"
    else
        log_info "Service enabled but not started. Start manually with: sudo systemctl start $service_name"
    fi
    
    # Update registry status
    update_service_registry_status "$service_name"
    
    return 0
}

# Disable a service with user confirmation
# Arguments: $1=service_name, $2=auto_stop (optional, default=false)
disable_service_manual() {
    local service_name="$1"
    local auto_stop="${2:-false}"
    
    if [[ -z "$service_name" ]]; then
        log_error "Service name is required"
        return 1
    fi
    
    if ! is_service_enabled "$service_name"; then
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
    
    # Stop the service if requested and running
    if [[ "$auto_stop" == "true" ]] && is_service_running "$service_name"; then
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
    
    # Update registry status
    update_service_registry_status "$service_name"
    
    return 0
}

# Update service status in registry
update_service_registry_status() {
    local service_name="$1"
    
    if [[ ! -f "$SERVICE_REGISTRY_FILE" ]]; then
        return 0
    fi
    
    local status="disabled"
    if is_service_enabled "$service_name"; then
        status="enabled"
    elif ! is_service_available "$service_name"; then
        status="not-available"
    fi
    
    # Update the status field (6th field) in the registry
    if grep -q "^$service_name|" "$SERVICE_REGISTRY_FILE"; then
        local temp_file="${SERVICE_REGISTRY_FILE}.tmp"
        while IFS='|' read -r name desc priority component distro old_status policy; do
            if [[ "$name" == "$service_name" ]]; then
                echo "$name|$desc|$priority|$component|$distro|$status|$policy"
            else
                echo "$name|$desc|$priority|$component|$distro|$old_status|$policy"
            fi
        done < "$SERVICE_REGISTRY_FILE" > "$temp_file"
        mv "$temp_file" "$SERVICE_REGISTRY_FILE"
    fi
}

#######################################
# Service Reporting Functions
#######################################

# Show all registered services with their status
# Requirements: 3.3 - Service status reporting and management utilities
show_service_status() {
    local filter_component="${1:-}"
    local filter_priority="${2:-}"
    
    if [[ ! -f "$SERVICE_REGISTRY_FILE" ]]; then
        log_warn "No services registered yet"
        return 0
    fi
    
    log_info "=== Service Status Report ==="
    log_info ""
    
    # Update all service statuses first
    while IFS='|' read -r service_name desc priority component distro status policy; do
        # Skip comments
        [[ "$service_name" =~ ^# ]] && continue
        [[ -z "$service_name" ]] && continue
        
        # Apply filters
        if [[ -n "$filter_component" && "$component" != "$filter_component" ]]; then
            continue
        fi
        if [[ -n "$filter_priority" && "$priority" != "$filter_priority" ]]; then
            continue
        fi
        
        update_service_registry_status "$service_name"
    done < "$SERVICE_REGISTRY_FILE"
    
    # Display services grouped by priority
    for priority_level in "required" "recommended" "optional"; do
        # Skip if filtering for specific priority and this isn't it
        if [[ -n "$filter_priority" && "$priority_level" != "$filter_priority" ]]; then
            continue
        fi
        
        local has_services=false
        
        # Check if we have services for this priority level
        while IFS='|' read -r service_name desc priority component distro status policy; do
            [[ "$service_name" =~ ^# ]] && continue
            [[ -z "$service_name" ]] && continue
            [[ -n "$filter_component" && "$component" != "$filter_component" ]] && continue
            
            if [[ "$priority" == "$priority_level" ]]; then
                if [[ "$has_services" == "false" ]]; then
                    log_info "$(echo "$priority_level" | tr '[:lower:]' '[:upper:]') SERVICES:"
                    has_services=true
                fi
                
                # Get current status
                local current_status
                current_status=$(get_service_status "$service_name")
                local available="${current_status%%,*}"
                local enabled="${current_status#*,}"
                enabled="${enabled%%,*}"
                local running="${current_status##*,}"
                
                # Format status with colors
                local status_display=""
                case "$enabled" in
                    "enabled")
                        if [[ "$running" == "running" ]]; then
                            status_display="${GREEN}enabled/running${NC}"
                        else
                            status_display="${YELLOW}enabled/stopped${NC}"
                        fi
                        ;;
                    "disabled")
                        if [[ "$available" == "available" ]]; then
                            status_display="${CYAN}disabled${NC}"
                        else
                            status_display="${RED}not-available${NC}"
                        fi
                        ;;
                esac
                
                printf "  %-25s %s - %s (%s)\n" \
                    "$service_name" \
                    "$status_display" \
                    "$desc" \
                    "$component"
            fi
        done < "$SERVICE_REGISTRY_FILE"
        
        if [[ "$has_services" == "true" ]]; then
            log_info ""
        fi
    done
    
    log_info "Service Management Commands:"
    log_info "  Enable service:  sudo systemctl enable <service_name>"
    log_info "  Start service:   sudo systemctl start <service_name>"
    log_info "  Stop service:    sudo systemctl stop <service_name>"
    log_info "  Disable service: sudo systemctl disable <service_name>"
    log_info "  Check status:    systemctl status <service_name>"
    log_info ""
}

# Show services by component
show_services_by_component() {
    local component="$1"
    
    if [[ -z "$component" ]]; then
        log_error "Component name is required"
        return 1
    fi
    
    log_info "Services for component: $component"
    show_service_status "$component"
}

# Show services by priority
show_services_by_priority() {
    local priority="$1"
    
    if [[ -z "$priority" ]]; then
        log_error "Priority level is required (required, recommended, optional)"
        return 1
    fi
    
    log_info "Services with priority: $priority"
    show_service_status "" "$priority"
}

# List all available services on the system (not just registered ones)
list_all_system_services() {
    log_info "=== All System Services ==="
    
    systemctl list-unit-files --type=service --no-pager --no-legend | \
    while read -r service_file state; do
        local service_name="${service_file%.service}"
        local status
        status=$(get_service_status "$service_name")
        local available="${status%%,*}"
        local enabled="${status#*,}"
        enabled="${enabled%%,*}"
        local running="${status##*,}"
        
        printf "  %-30s %s/%s\n" "$service_name" "$enabled" "$running"
    done | sort
}

#######################################
# System Integration Functions
#######################################

# Configure desktop environment integration
# Requirements: 3.4 - System integration functions for desktop environment setup
configure_desktop_integration() {
    local desktop_env="${1:-hyprland}"
    local component="${2:-wm}"
    
    log_info "Configuring desktop environment integration: $desktop_env"
    
    case "$desktop_env" in
        "hyprland")
            configure_hyprland_integration "$component"
            ;;
        "gnome")
            configure_gnome_integration "$component"
            ;;
        "kde")
            configure_kde_integration "$component"
            ;;
        *)
            log_warn "Unknown desktop environment: $desktop_env"
            return 1
            ;;
    esac
}

# Configure Hyprland desktop integration
configure_hyprland_integration() {
    local component="$1"
    
    log_info "Setting up Hyprland desktop integration..."
    
    # Create Wayland session file
    local session_file="/usr/share/wayland-sessions/hyprland.desktop"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would create Hyprland session file: $session_file"
    else
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
    fi
    
    # Register desktop session integration
    register_system_integration "desktop_session" "hyprland" "Hyprland Wayland session" "$component"
    
    # Set up environment variables for Wayland
    configure_wayland_environment "$component"
    
    # Configure XDG desktop portal
    configure_xdg_portal "$component"
}

# Configure Wayland environment variables
configure_wayland_environment() {
    local component="$1"
    local env_file="$HOME/.config/environment.d/wayland.conf"
    
    log_info "Configuring Wayland environment variables..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would create Wayland environment file: $env_file"
        return 0
    fi
    
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
    
    # Register environment variable integration
    register_system_integration "environment_var" "wayland" "Wayland environment variables" "$component"
}

# Configure XDG desktop portal
configure_xdg_portal() {
    local component="$1"
    local portal_config="$HOME/.config/xdg-desktop-portal/portals.conf"
    
    log_info "Configuring XDG desktop portal..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would configure XDG desktop portal"
        return 0
    fi
    
    # Create portal configuration directory
    mkdir -p "$(dirname "$portal_config")"
    
    # Create portal configuration
    cat > "$portal_config" << 'EOF'
[preferred]
default=hyprland;gtk
org.freedesktop.impl.portal.Screenshot=hyprland
org.freedesktop.impl.portal.ScreenCast=hyprland
EOF
    
    log_success "Configured XDG desktop portal"
    
    # Register portal integration
    register_system_integration "desktop_portal" "xdg-desktop-portal" "XDG desktop portal configuration" "$component"
}

# Add user to system groups
add_user_to_groups() {
    local groups=("$@")
    local current_user
    current_user=$(whoami)
    
    if [[ ${#groups[@]} -eq 0 ]]; then
        log_warn "No groups specified for user addition"
        return 0
    fi
    
    log_info "Adding user $current_user to groups: ${groups[*]}"
    
    for group in "${groups[@]}"; do
        # Check if group exists
        if ! getent group "$group" >/dev/null 2>&1; then
            log_warn "Group does not exist: $group"
            continue
        fi
        
        # Check if user is already in group
        if groups "$current_user" | grep -q "\b$group\b"; then
            log_info "User $current_user is already in group: $group"
            continue
        fi
        
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            log_info "[DRY RUN] Would add user $current_user to group: $group"
        else
            if sudo usermod -aG "$group" "$current_user"; then
                log_success "Added user $current_user to group: $group"
                register_system_integration "user_group" "$group" "User added to $group group" "system"
            else
                log_error "Failed to add user $current_user to group: $group"
            fi
        fi
    done
    
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
        log_info "Note: Group changes will take effect after logging out and back in"
    fi
}

# Show system integration status
show_system_integration_status() {
    if [[ ! -f "$SYSTEM_INTEGRATION_FILE" ]]; then
        log_warn "No system integrations configured yet"
        return 0
    fi
    
    log_info "=== System Integration Status ==="
    log_info ""
    
    # Group by integration type
    for integration_type in "desktop_session" "display_manager" "environment_var" "user_group" "desktop_portal"; do
        local has_integrations=false
        
        while IFS='|' read -r type name desc status component; do
            [[ "$type" =~ ^# ]] && continue
            [[ -z "$type" ]] && continue
            
            if [[ "$type" == "$integration_type" ]]; then
                if [[ "$has_integrations" == "false" ]]; then
                    log_info "$(echo "$integration_type" | tr '_' ' ' | tr '[:lower:]' '[:upper:]'):"
                    has_integrations=true
                fi
                
                printf "  %-25s %s (%s)\n" "$name" "$desc" "$component"
            fi
        done < "$SYSTEM_INTEGRATION_FILE"
        
        if [[ "$has_integrations" == "true" ]]; then
            log_info ""
        fi
    done
}

# Export functions for external use
export -f init_service_registry
export -f register_service
export -f register_system_integration
export -f is_service_available
export -f is_service_enabled
export -f is_service_running
export -f get_service_status
export -f enable_service_manual
export -f disable_service_manual
export -f show_service_status
export -f show_services_by_component
export -f show_services_by_priority
export -f list_all_system_services
export -f configure_desktop_integration
export -f configure_hyprland_integration
export -f configure_wayland_environment
export -f configure_xdg_portal
export -f add_user_to_groups
export -f show_system_integration_status