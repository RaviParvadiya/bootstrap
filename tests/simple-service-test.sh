#!/usr/bin/env bash

# Simple service management test
export DRY_RUN=true

# Source the service manager directly
source core/service-manager.sh

echo "=== Simple Service Management Test ==="
echo ""

# Test service registry initialization
echo "Initializing service registry..."
init_service_registry
echo "Registry file: $SERVICE_REGISTRY_FILE"

# Test service registration
echo "Registering test service..."
register_service "test-service" "Test service" "optional" "test" "never"

# Test system integration registration
echo "Registering test integration..."
register_system_integration "test_type" "test-integration" "Test integration" "test"

# Show results
echo ""
echo "=== Registry Contents ==="
echo "Services:"
cat "$SERVICE_REGISTRY_FILE" 2>/dev/null || echo "No services file"
echo ""
echo "Integrations:"
cat "$SYSTEM_INTEGRATION_FILE" 2>/dev/null || echo "No integrations file"

echo ""
echo "=== Service Status Test ==="
# Test some common services
for service in "systemd-journald" "systemd-timesyncd" "NetworkManager"; do
    if command -v systemctl >/dev/null 2>&1; then
        status=$(get_service_status "$service" 2>/dev/null || echo "error")
        echo "Service $service: $status"
    fi
done

echo ""
echo "Test completed successfully!"