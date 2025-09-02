#!/usr/bin/env bash

# Test script for package management system
# Tests parsing, filtering, and validation of package lists

set -euo pipefail

# Script directory and paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$SCRIPT_DIR/tests"

# Source required modules
source "$SCRIPT_DIR/core/logger.sh"
source "$SCRIPT_DIR/core/common.sh"
source "$SCRIPT_DIR/core/package-manager.sh"

# Test configuration
DRY_RUN=true
VM_MODE=false
VERBOSE=true

# Initialize test environment
init_test_environment() {
    log_info "Initializing test environment..."
    
    # Initialize logger
    init_logger
    
    # Initialize package manager
    init_package_manager || {
        log_error "Failed to initialize package manager"
        exit 1
    }
    
    log_success "Test environment initialized"
}

# Test package list parsing
test_package_parsing() {
    log_info "Testing package list parsing..."
    
    local -i tests_passed=0
    local -i tests_failed=0
    
    # Test Arch packages parsing
    log_debug "Testing Arch packages parsing..."
    if parse_package_list "$SCRIPT_DIR/data/arch-packages.lst" >/dev/null; then
        log_success "Arch packages parsed successfully"
        ((tests_passed++))
    else
        log_error "Failed to parse Arch packages"
        ((tests_failed++))
    fi
    
    # Test Ubuntu packages parsing
    log_debug "Testing Ubuntu packages parsing..."
    if parse_package_list "$SCRIPT_DIR/data/ubuntu-packages.lst" >/dev/null; then
        log_success "Ubuntu packages parsed successfully"
        ((tests_passed++))
    else
        log_error "Failed to parse Ubuntu packages"
        ((tests_failed++))
    fi
    
    # Test AUR packages parsing
    log_debug "Testing AUR packages parsing..."
    if parse_package_list "$SCRIPT_DIR/data/aur-packages.lst" >/dev/null; then
        log_success "AUR packages parsed successfully"
        ((tests_passed++))
    else
        log_error "Failed to parse AUR packages"
        ((tests_failed++))
    fi
    
    log_info "Package parsing tests: $tests_passed passed, $tests_failed failed"
    return $tests_failed
}

# Test condition checking
test_condition_checking() {
    log_info "Testing condition checking..."
    
    local -i tests_passed=0
    local -i tests_failed=0
    
    # Test VM condition (should be false in normal environment)
    if ! check_package_condition "vm"; then
        log_success "VM condition correctly evaluated as false"
        ((tests_passed++))
    else
        log_error "VM condition incorrectly evaluated as true"
        ((tests_failed++))
    fi
    
    # Test laptop condition
    if check_package_condition "laptop"; then
        log_success "Laptop condition evaluated (result may vary by system)"
        ((tests_passed++))
    else
        log_success "Laptop condition evaluated as false (not a laptop)"
        ((tests_passed++))
    fi
    
    # Test unknown condition
    if ! check_package_condition "unknown_condition"; then
        log_success "Unknown condition correctly evaluated as false"
        ((tests_passed++))
    else
        log_error "Unknown condition incorrectly evaluated as true"
        ((tests_failed++))
    fi
    
    log_info "Condition checking tests: $tests_passed passed, $tests_failed failed"
    return $tests_failed
}

# Test package filtering
test_package_filtering() {
    log_info "Testing package filtering..."
    
    local -i tests_passed=0
    local -i tests_failed=0
    
    # Test getting packages by source for Arch
    log_debug "Testing Arch package filtering by source..."
    local arch_regular_count
    arch_regular_count=$(get_packages_by_source "arch" "apt" | wc -l)
    
    local arch_aur_count
    arch_aur_count=$(get_packages_by_source "arch" "aur" | wc -l)
    
    if [[ $arch_regular_count -gt 0 ]]; then
        log_success "Found $arch_regular_count regular Arch packages"
        ((tests_passed++))
    else
        log_error "No regular Arch packages found"
        ((tests_failed++))
    fi
    
    if [[ $arch_aur_count -gt 0 ]]; then
        log_success "Found $arch_aur_count AUR packages"
        ((tests_passed++))
    else
        log_error "No AUR packages found"
        ((tests_failed++))
    fi
    
    # Test getting packages by source for Ubuntu
    log_debug "Testing Ubuntu package filtering by source..."
    local ubuntu_apt_count
    ubuntu_apt_count=$(get_packages_by_source "ubuntu" "apt" | wc -l)
    
    local ubuntu_snap_count
    ubuntu_snap_count=$(get_packages_by_source "ubuntu" "snap" | wc -l)
    
    if [[ $ubuntu_apt_count -gt 0 ]]; then
        log_success "Found $ubuntu_apt_count Ubuntu APT packages"
        ((tests_passed++))
    else
        log_error "No Ubuntu APT packages found"
        ((tests_failed++))
    fi
    
    if [[ $ubuntu_snap_count -gt 0 ]]; then
        log_success "Found $ubuntu_snap_count Ubuntu Snap packages"
        ((tests_passed++))
    else
        log_warn "No Ubuntu Snap packages found (this may be expected)"
        ((tests_passed++))
    fi
    
    log_info "Package filtering tests: $tests_passed passed, $tests_failed failed"
    return $tests_failed
}

# Test package validation
test_package_validation() {
    log_info "Testing package validation..."
    
    if validate_package_lists; then
        log_success "Package lists validation passed"
        return 0
    else
        log_error "Package lists validation failed"
        return 1
    fi
}

# Test package listing
test_package_listing() {
    log_info "Testing package listing functionality..."
    
    # Test listing all packages for Arch
    log_debug "Testing Arch package listing..."
    local arch_output
    arch_output=$(list_packages "arch" 2>/dev/null)
    
    if [[ -n "$arch_output" ]]; then
        log_success "Arch package listing generated output"
    else
        log_error "Arch package listing generated no output"
        return 1
    fi
    
    # Test listing all packages for Ubuntu
    log_debug "Testing Ubuntu package listing..."
    local ubuntu_output
    ubuntu_output=$(list_packages "ubuntu" 2>/dev/null)
    
    if [[ -n "$ubuntu_output" ]]; then
        log_success "Ubuntu package listing generated output"
    else
        log_error "Ubuntu package listing generated no output"
        return 1
    fi
    
    return 0
}

# Run all tests
run_all_tests() {
    log_info "Starting package management system tests..."
    
    local -i total_failures=0
    
    # Initialize test environment
    init_test_environment
    
    # Run individual test suites
    test_package_parsing || ((total_failures++))
    echo
    
    test_condition_checking || ((total_failures++))
    echo
    
    test_package_filtering || ((total_failures++))
    echo
    
    test_package_validation || ((total_failures++))
    echo
    
    test_package_listing || ((total_failures++))
    echo
    
    # Summary
    if [[ $total_failures -eq 0 ]]; then
        log_success "All package management tests passed!"
        return 0
    else
        log_error "$total_failures test suite(s) failed"
        return 1
    fi
}

# Main execution
main() {
    case "${1:-all}" in
        "parsing")
            init_test_environment
            test_package_parsing
            ;;
        "conditions")
            init_test_environment
            test_condition_checking
            ;;
        "filtering")
            init_test_environment
            test_package_filtering
            ;;
        "validation")
            init_test_environment
            test_package_validation
            ;;
        "listing")
            init_test_environment
            test_package_listing
            ;;
        "all"|*)
            run_all_tests
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi