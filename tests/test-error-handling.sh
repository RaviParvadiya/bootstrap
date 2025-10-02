#!/usr/bin/env bash

# tests/test-error-handling.sh - Test script for error handling and recovery system
# Demonstrates various error scenarios and recovery mechanisms

set -euo pipefail

# Initialize all project paths
source "$(dirname "${BASH_SOURCE[0]}")/../core/init-paths.sh"

# Source required modules
source "$CORE_DIR/common.sh"
source "$CORE_DIR/logger.sh"
source "$CORE_DIR/error-handler.sh"
source "$CORE_DIR/error-wrappers.sh"
source "$CORE_DIR/recovery-system.sh"

# Test configuration
DRY_RUN="${DRY_RUN:-true}"
VERBOSE="${VERBOSE:-true}"
export DRY_RUN VERBOSE

# Test functions
test_package_error() {
    log_info "=== Testing Package Installation Error ==="
    
    push_error_context "test" "Package error test"
    
    # Simulate package installation failure
    if ! safe_install_package "nonexistent-package-12345"; then
        log_info "Package error handled correctly"
    fi
    
    pop_error_context
}

test_config_error() {
    log_info "=== Testing Configuration Error ==="
    
    push_error_context "test" "Config error test"
    
    # Register a rollback action for the test_config operation
    register_rollback_action "test_config" "echo 'Test config rollback executed'" "Test config rollback action"
    
    # Simulate config file error
    if ! safe_copy_file "/nonexistent/source" "/tmp/test-dest"; then
        log_info "Config error handled correctly"
    fi
    
    pop_error_context
}

test_network_error() {
    log_info "=== Testing Network Error ==="
    
    push_error_context "test" "Network error test"
    
    # Simulate network download failure
    if ! safe_download_file "http://nonexistent-domain-12345.com/file" "/tmp/test-download"; then
        log_info "Network error handled correctly"
    fi
    
    pop_error_context
}

test_permission_error() {
    log_info "=== Testing Permission Error ==="
    
    push_error_context "test" "Permission error test"
    
    # Simulate permission error
    handle_permission_error "write" "/root/test-file" "Permission denied"
    
    pop_error_context
}

test_validation_error() {
    log_info "=== Testing Validation Error ==="
    
    push_error_context "test" "Validation error test"
    
    # Create a failing validation function
    failing_validation() {
        return 1
    }
    
    if ! safe_validate "failing_validation" "Test validation that should fail"; then
        log_info "Validation error handled correctly"
    fi
    
    pop_error_context
}

test_rollback_system() {
    log_info "=== Testing Rollback System ==="
    
    push_error_context "test" "Rollback test"
    
    # Register some rollback actions
    register_rollback_action "test_operation_1" "echo 'Rolling back operation 1'" "Test rollback 1"
    register_rollback_action "test_operation_2" "echo 'Rolling back operation 2'" "Test rollback 2"
    
    # Test rollback of specific operation
    if perform_operation_rollback "test_operation_1"; then
        log_info "Rollback test completed successfully"
    fi
    
    pop_error_context
}

test_recovery_system() {
    log_info "=== Testing Recovery System ==="
    
    # Create a checkpoint
    create_checkpoint "test_checkpoint" "Test checkpoint for error handling demo"
    
    # Test auto recovery
    if attempt_auto_recovery "package_install_failed" "test-package" "Installation failed"; then
        log_info "Auto recovery test completed"
    else
        log_info "Auto recovery test failed (expected for demo)"
    fi
    
    # List checkpoints
    list_checkpoints
}

test_batch_operations() {
    log_info "=== Testing Batch Operations with Error Handling ==="
    
    # Create a test function that fails on certain items
    test_operation() {
        local item="$1"
        
        if [[ "$item" == "fail-item" ]]; then
            return 1
        else
            log_info "Processing item: $item"
            return 0
        fi
    }
    
    # Test batch operation with some failures
    local test_items=("item1" "item2" "fail-item" "item3" "item4")
    
    if safe_batch_operation "test_operation" "Test batch operation" "${test_items[@]}"; then
        log_info "Batch operation completed successfully"
    else
        log_info "Batch operation completed with some failures (expected)"
    fi
}

test_error_recovery_modes() {
    log_info "=== Testing Different Error Recovery Modes ==="
    
    # Test graceful mode
    set_error_recovery_mode "graceful"
    log_info "Testing graceful recovery mode"
    handle_error "package" "Test error in graceful mode" "test_operation"
    
    # Test interactive mode (will default to graceful in non-interactive environment)
    set_error_recovery_mode "interactive"
    log_info "Testing interactive recovery mode"
    handle_error "package" "Test error in interactive mode" "test_operation"
    
    # Reset to graceful
    set_error_recovery_mode "graceful"
}

test_context_stack() {
    log_info "=== Testing Error Context Stack ==="
    
    push_error_context "level1" "First level operation"
    push_error_context "level2" "Second level operation"
    push_error_context "level3" "Third level operation"
    
    # Show current context
    log_info "Current context: $(get_current_context)"
    
    # Show full stack
    log_info "Full context stack:"
    get_error_context_stack
    
    # Pop contexts
    pop_error_context
    pop_error_context
    pop_error_context
}

# Main test function
run_error_handling_tests() {
    log_info "Starting Error Handling System Tests"
    log_info "DRY_RUN mode: $DRY_RUN"
    
    # Set error recovery mode to graceful for testing
    set_error_recovery_mode "graceful"
    set_rollback_enabled "true"
    
    # Run individual tests
    test_context_stack
    test_package_error
    test_config_error
    test_network_error
    test_permission_error
    test_validation_error
    test_rollback_system
    test_recovery_system
    test_batch_operations
    test_error_recovery_modes
    
    # Show final error summary
    show_error_summary
    
    # Show recovery system status
    show_recovery_status
    
    log_success "Error handling system tests completed"
}

# Command line interface
show_usage() {
    cat << EOF
Error Handling Test Script

Usage: $0 [OPTIONS] [TEST]

OPTIONS:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    -d, --dry-run       Run in dry-run mode (default: true)
    --real-run          Disable dry-run mode
    -m, --mode MODE     Set error recovery mode (graceful, strict, interactive)

TESTS:
    all                 Run all tests (default)
    package             Test package error handling
    config              Test configuration error handling
    network             Test network error handling
    permission          Test permission error handling
    validation          Test validation error handling
    rollback            Test rollback system
    recovery            Test recovery system
    batch               Test batch operations
    modes               Test error recovery modes
    context             Test error context stack

EXAMPLES:
    $0                          # Run all tests in dry-run mode
    $0 --real-run package       # Test package errors with real operations
    $0 -m strict rollback       # Test rollback in strict mode

EOF
}

# Parse command line arguments
parse_arguments() {
    local test_name="all"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                export VERBOSE
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                export DRY_RUN
                shift
                ;;
            --real-run)
                DRY_RUN=false
                export DRY_RUN
                shift
                ;;
            -m|--mode)
                ERROR_RECOVERY_MODE="$2"
                export ERROR_RECOVERY_MODE
                shift 2
                ;;
            all|package|config|network|permission|validation|rollback|recovery|batch|modes|context)
                test_name="$1"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    echo "$test_name"
}

# Main execution
main() {
    # Initialize systems
    init_logger
    init_error_handler
    init_recovery_system
    
    # Parse arguments
    local test_name
    test_name=$(parse_arguments "$@")
    
    log_info "Running error handling tests: $test_name"
    
    # Run specific test or all tests
    case "$test_name" in
        "all")
            run_error_handling_tests
            ;;
        "package")
            test_package_error
            ;;
        "config")
            test_config_error
            ;;
        "network")
            test_network_error
            ;;
        "permission")
            test_permission_error
            ;;
        "validation")
            test_validation_error
            ;;
        "rollback")
            test_rollback_system
            ;;
        "recovery")
            test_recovery_system
            ;;
        "batch")
            test_batch_operations
            ;;
        "modes")
            test_error_recovery_modes
            ;;
        "context")
            test_context_stack
            ;;
        *)
            log_error "Unknown test: $test_name"
            exit 1
            ;;
    esac
    
    log_success "Test execution completed"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi