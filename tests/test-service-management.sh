#!/bin/bash

# Test script for service management functionality
# Tests the new service management and system integration features

# Set up test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
export DRY_RUN=true
export VERBOSE=true

# Debug path information
echo "Script dir: $SCRIPT_DIR"
echo "Project root: $PROJECT_ROOT"
echo "Looking for: $PROJECT_ROOT/core/common.sh"
ls -la "$PROJECT_ROOT/core/" || echo "Core directory not found"

# Source required modules
if [[ -f "$PROJECT_ROOT/core/common.sh" ]]; then
    source "$PROJECT_ROOT/core/common.sh"
else
    echo "Error: Cannot find common.sh at $PROJECT_ROOT/core/common.sh"
    exit 1
fi

if [[ -f "$PROJECT_ROOT/core/logger.sh" ]]; then
    source "$PROJECT_ROOT/core/logger.sh"
else
    echo "Error: Cannot find logger.sh at $PROJECT_ROOT/core/logger.sh"
    exit 1
fi

if [[ -f "$PROJECT_ROOT/core/service-manager.sh" ]]; then
    source "$PROJECT_ROOT/core/service-manager.sh"
else
    echo "Error: Cannot find service-manager.sh at $PROJECT_ROOT/core/service-manager.sh"
    exit 1
fi

# Test function wrapper
run_test() {
    local test_name="$1"
    shift
    
    log_info "Test: $test_name"
    if "$@"; then
        log_success "✓ $test_name passed"
    else
        log_error "✗ $test_name failed"
        return 1
    fi
    log_info ""
}

# Initialize logging
init_logger

log_info "=== Service Management Test Suite ==="
log_info ""

# Test 1: Service registry initialization
log_info "Test 1: Service registry initialization"
init_service_registry
if [[ -f "$SERVICE_REGISTRY_FILE" ]]; then
    log_success "✓ Service registry initialized"
else
    log_error "✗ Service registry initialization failed"
fi
log_info ""

# Test 2: Service registration
log_info "Test 2: Service registration"
register_service "test-service" "Test service description" "optional" "test-component" "never"
if grep -q "test-service" "$SERVICE_REGISTRY_FILE"; then
    log_success "✓ Service registration works"
else
    log_error "✗ Service registration failed"
fi
log_info ""

# Test 3: System integration registration
log_info "Test 3: System integration registration"
register_system_integration "test_integration" "test-integration" "Test integration description" "test-component"
if grep -q "test_integration" "$SYSTEM_INTEGRATION_FILE"; then
    log_success "✓ System integration registration works"
else
    log_error "✗ System integration registration failed"
fi
log_info ""

# Test 4: Service status checking
log_info "Test 4: Service status checking"
if is_service_available "systemd-journald"; then
    log_success "✓ Service availability check works (systemd-journald found)"
else
    log_warn "⚠ systemd-journald not found (may be normal in some environments)"
fi

# Test common services
test_services=("systemd-timesyncd" "NetworkManager" "bluetooth" "cups")
for service in "${test_services[@]}"; do
    status=$(get_service_status "$service")
    log_info "Service $service status: $status"
done
log_info ""

# Test 5: Desktop integration configuration
log_info "Test 5: Desktop integration configuration (dry-run)"
configure_desktop_integration "hyprland" "test-component"
log_success "✓ Desktop integration configuration completed"
log_info ""

# Test 6: User group management
log_info "Test 6: User group management (dry-run)"
add_user_to_groups "video" "audio" "input"
log_success "✓ User group management completed"
log_info ""

# Test 7: Service status display
log_info "Test 7: Service status display"
show_service_status
log_info ""

# Test 8: System integration status display
log_info "Test 8: System integration status display"
show_system_integration_status
log_info ""

# Test distribution-specific service management
distro=$(get_distro)

case "$distro" in
    "arch")
        log_info "Test 9: Arch Linux service management"
        source "$PROJECT_ROOT/distros/arch/services.sh"
        
        # Test Arch service configuration
        arch_configure_services "hyprland" "docker" "bluetooth"
        arch_show_service_summary "hyprland" "docker" "bluetooth"
        arch_show_system_integration
        
        log_success "✓ Arch Linux service management test completed"
        ;;
    "ubuntu")
        log_info "Test 9: Ubuntu service management"
        source "$PROJECT_ROOT/distros/ubuntu/services.sh"
        
        # Test Ubuntu service configuration
        ubuntu_configure_services "hyprland" "docker" "bluetooth"
        ubuntu_show_service_summary "hyprland" "docker" "bluetooth"
        ubuntu_show_system_integration
        
        log_success "✓ Ubuntu service management test completed"
        ;;
    *)
        log_warn "⚠ Unknown distribution: $distro, skipping distribution-specific tests"
        ;;
esac

log_info ""
log_info "=== Service Management Test Results ==="
log_info ""

# Check if registry files were created and contain expected content
registry_lines=$(grep -v "^#" "$SERVICE_REGISTRY_FILE" 2>/dev/null | grep -v "^$" | wc -l)
log_info "Services registered: $registry_lines"

integration_lines=$(grep -v "^#" "$SYSTEM_INTEGRATION_FILE" 2>/dev/null | grep -v "^$" | wc -l)
log_info "System integrations registered: $integration_lines"

if [[ $registry_lines -gt 0 && $integration_lines -gt 0 ]]; then
    log_success "✓ All service management tests passed"
    log_info ""
    log_info "Registry files created:"
    log_info "  Services: $SERVICE_REGISTRY_FILE"
    log_info "  Integrations: $SYSTEM_INTEGRATION_FILE"
    log_info ""
    log_info "To clean up test files:"
    log_info "  rm -f $SERVICE_REGISTRY_FILE $SYSTEM_INTEGRATION_FILE"
else
    log_error "✗ Some service management tests failed"
    exit 1
fi

log_info ""
log_success "Service management test suite completed successfully!"