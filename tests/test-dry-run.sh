#!/usr/bin/env bash

# Test script for dry-run functionality
# This script tests the dry-run mode to ensure it works correctly

set -euo pipefail

# Initialize all project paths
source "$(dirname "${BASH_SOURCE[0]}")/../core/init-paths.sh"

# Source required modules
source "$CORE_DIR/common.sh"
source "$CORE_DIR/logger.sh"

# Test dry-run functionality
test_dry_run_basic() {
    echo "=== Testing Basic Dry-Run Functionality ==="
    
    # Enable dry-run mode
    export DRY_RUN=true
    
    # Initialize logger
    init_logger
    
    # Test dry-run logging
    log_info "Testing dry-run logging"
    log_dry_run "Test operation" "with details"
    log_would_execute "test command" "test description"
    
    # Test package installation in dry-run mode
    log_info "Testing package installation dry-run"
    install_package "test-package" "pacman"
    install_package "another-package" "apt"
    
    # Test symlink creation in dry-run mode
    log_info "Testing symlink creation dry-run"
    # Create a temporary source file for testing
    touch "/tmp/test-source"
    create_symlink "/tmp/test-source" "/tmp/test-target"
    # Clean up
    rm -f "/tmp/test-source"
    
    echo "✓ Basic dry-run functionality test completed"
}

# Test dry-run script functionality
test_dry_run_script() {
    echo "=== Testing Dry-Run Script ==="
    
    # Source dry-run script
    source "$TESTS_DIR/dry-run.sh"
    
    # Test initialization
    init_dry_run
    
    # Test tracking functions
    track_package_install "test-pkg" "pacman" "official"
    track_config_operation "/home/user/.config/test" "symlink" "test -> source"
    track_service_operation "test-service" "enable"
    track_command_execution "echo test" "test echo command"
    
    # Test display functions
    show_dry_run_packages
    show_dry_run_configs
    show_dry_run_services
    show_dry_run_commands
    
    # Finalize
    finalize_dry_run
    
    echo "✓ Dry-run script test completed"
}

# Test component dry-run
test_component_dry_run_functionality() {
    echo "=== Testing Component Dry-Run ==="
    
    # Create a test component script
    local test_component_dir="/tmp/test-components/terminal"
    mkdir -p "$test_component_dir"
    
    cat > "$test_component_dir/test-terminal.sh" << 'EOF'
#!/bin/bash

install_test_terminal() {
    local dry_run="${1:-false}"
    
    if [[ "$dry_run" == "true" || "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Install test terminal package"
        echo "[DRY-RUN] Configure test terminal"
        return 0
    fi
    
    # Real installation would happen here
    echo "Installing test-terminal package..."
    echo "Configuring test-terminal..."
}
EOF
    
    # Test the component by sourcing and calling it
    source "$test_component_dir/test-terminal.sh"
    
    # Test in dry-run mode
    export DRY_RUN=true
    install_test_terminal "true"
    
    # Cleanup
    rm -rf "/tmp/test-components"
    
    echo "✓ Component dry-run test completed"
}

# Main test function
main() {
    echo "Starting dry-run functionality tests..."
    echo
    
    test_dry_run_basic
    echo
    
    test_dry_run_script
    echo
    
    test_component_dry_run_functionality
    echo
    
    echo "All dry-run tests completed successfully!"
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi