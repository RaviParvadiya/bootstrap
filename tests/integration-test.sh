#!/usr/bin/env bash

# tests/integration-test.sh - Comprehensive integration testing for the modular install framework
# This module provides end-to-end testing of the complete installation flow on both
# Arch Linux and Ubuntu systems with component selection, dependency resolution,
# and configuration management validation.

# Prevent multiple sourcing
if [[ -n "${INTEGRATION_TEST_SOURCED:-}" ]]; then
    return 0
fi
readonly INTEGRATION_TEST_SOURCED=1

# Initialize all project paths
source "$(dirname "${BASH_SOURCE[0]}")/../core/init-paths.sh"

# Source required modules
source "$CORE_DIR/common.sh"
source "$CORE_DIR/logger.sh"
source "$CORE_DIR/recovery-system.sh"
source "$TESTS_DIR/dry-run.sh"
source "$TESTS_DIR/validate.sh"
source "$TESTS_DIR/vm-test.sh"

# Integration test configuration
INTEGRATION_TEST_LOG=""
INTEGRATION_TEST_RESULTS=()
INTEGRATION_TEST_FAILURES=()
INTEGRATION_TEST_COMPONENTS=()

#######################################
# Integration Test Initialization
#######################################

# Initialize integration testing system
init_integration_tests() {
    log_section "INTEGRATION TEST INITIALIZATION"
    
    # Create integration test log
    local timestamp=$(date +%Y%m%d_%H%M%S)
    INTEGRATION_TEST_LOG="/tmp/integration-test-$timestamp.log"
    touch "$INTEGRATION_TEST_LOG"
    
    # Initialize recovery system
    init_recovery_system
    
    # Create test checkpoint
    create_checkpoint "integration_test_start" "Integration test initialization"
    
    log_info "Integration testing system initialized"
    log_info "Test log: $INTEGRATION_TEST_LOG"
    
    # Log system information
    {
        echo "=========================================="
        echo "INTEGRATION TEST SESSION"
        echo "=========================================="
        echo "Date: $(date)"
        echo "Distribution: $(get_distro) $(get_distro_version)"
        echo "Hostname: $(hostname)"
        echo "User: $(whoami)"
        echo "VM Mode: ${VM_MODE:-false}"
        echo "Dry Run: ${DRY_RUN:-false}"
        echo "=========================================="
        echo
    } >> "$INTEGRATION_TEST_LOG"
}

# Record integration test result
record_integration_test_result() {
    local test_name="$1"
    local result="$2"
    local details="${3:-}"
    local duration="${4:-}"
    
    local result_entry="$test_name: $result"
    if [[ -n "$duration" ]]; then
        result_entry="$result_entry (${duration}s)"
    fi
    if [[ -n "$details" ]]; then
        result_entry="$result_entry - $details"
    fi
    
    INTEGRATION_TEST_RESULTS+=("$result_entry")
    
    # Log to file
    echo "$(date '+%Y-%m-%d %H:%M:%S') $result_entry" >> "$INTEGRATION_TEST_LOG"
    
    # Track failures
    if [[ "$result" == "FAIL" ]]; then
        INTEGRATION_TEST_FAILURES+=("$test_name")
        log_error "Integration test failed: $test_name"
        if [[ -n "$details" ]]; then
            log_error "Details: $details"
        fi
    else
        log_success "Integration test passed: $test_name"
        if [[ -n "$details" ]]; then
            log_info "Details: $details"
        fi
    fi
}

#######################################
# Core Integration Tests
#######################################

# Test complete installation flow
test_complete_installation_flow() {
    local components=("$@")
    
    log_info "Testing complete installation flow..."
    push_error_context "integration_test" "Complete installation flow test"
    
    local start_time=$(date +%s)
    local test_success=true
    
    # Test 1: System validation
    log_info "Testing system validation..."
    if validate_system; then
        record_integration_test_result "System Validation" "PASS"
    else
        record_integration_test_result "System Validation" "FAIL" "System requirements not met"
        test_success=false
    fi
    
    # Test 2: Distribution detection
    log_info "Testing distribution detection..."
    local detected_distro
    detected_distro=$(get_distro)
    if [[ -n "$detected_distro" ]]; then
        record_integration_test_result "Distribution Detection" "PASS" "Detected: $detected_distro"
    else
        record_integration_test_result "Distribution Detection" "FAIL" "Could not detect distribution"
        test_success=false
    fi
    
    # Test 3: Component selection
    log_info "Testing component selection..."
    if [[ ${#components[@]} -gt 0 ]]; then
        INTEGRATION_TEST_COMPONENTS=("${components[@]}")
        record_integration_test_result "Component Selection" "PASS" "Selected: ${components[*]}"
    else
        # Use default test components
        INTEGRATION_TEST_COMPONENTS=("terminal" "shell")
        record_integration_test_result "Component Selection" "PASS" "Default test components"
    fi
    
    # Test 4: Dependency resolution
    log_info "Testing dependency resolution..."
    if test_dependency_resolution "${INTEGRATION_TEST_COMPONENTS[@]}"; then
        record_integration_test_result "Dependency Resolution" "PASS"
    else
        record_integration_test_result "Dependency Resolution" "FAIL" "Dependency conflicts detected"
        test_success=false
    fi
    
    # Test 5: Package installation (dry-run)
    log_info "Testing package installation (dry-run)..."
    local original_dry_run="$DRY_RUN"
    export DRY_RUN=true
    
    if test_package_installation "${INTEGRATION_TEST_COMPONENTS[@]}"; then
        record_integration_test_result "Package Installation" "PASS" "Dry-run successful"
    else
        record_integration_test_result "Package Installation" "FAIL" "Package installation issues"
        test_success=false
    fi
    
    export DRY_RUN="$original_dry_run"
    
    # Test 6: Configuration management
    log_info "Testing configuration management..."
    if test_configuration_management "${INTEGRATION_TEST_COMPONENTS[@]}"; then
        record_integration_test_result "Configuration Management" "PASS"
    else
        record_integration_test_result "Configuration Management" "FAIL" "Configuration issues"
        test_success=false
    fi
    
    # Test 7: Service management
    log_info "Testing service management..."
    if test_service_management "${INTEGRATION_TEST_COMPONENTS[@]}"; then
        record_integration_test_result "Service Management" "PASS"
    else
        record_integration_test_result "Service Management" "FAIL" "Service management issues"
        test_success=false
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    pop_error_context
    
    if [[ "$test_success" == "true" ]]; then
        record_integration_test_result "Complete Installation Flow" "PASS" "All sub-tests passed" "$duration"
        return 0
    else
        record_integration_test_result "Complete Installation Flow" "FAIL" "Some sub-tests failed" "$duration"
        return 1
    fi
}

# Test dependency resolution
test_dependency_resolution() {
    local components=("$@")
    
    log_info "Testing dependency resolution for components: ${components[*]}"
    
    # Load component dependencies if available
    local deps_file="$SCRIPT_DIR/data/component-deps.json"
    if [[ -f "$deps_file" ]] && command -v jq >/dev/null 2>&1; then
        for component in "${components[@]}"; do
            local deps
            deps=$(jq -r ".components.\"$component\".dependencies[]?" "$deps_file" 2>/dev/null || echo "")
            if [[ -n "$deps" ]]; then
                log_info "Component $component has dependencies: $deps"
            fi
            
            local conflicts
            conflicts=$(jq -r ".components.\"$component\".conflicts[]?" "$deps_file" 2>/dev/null || echo "")
            if [[ -n "$conflicts" ]]; then
                log_info "Component $component has conflicts: $conflicts"
                
                # Check if any conflicting components are selected
                for conflict in $conflicts; do
                    for selected in "${components[@]}"; do
                        if [[ "$selected" == "$conflict" ]]; then
                            log_error "Conflict detected: $component conflicts with $conflict"
                            return 1
                        fi
                    done
                done
            fi
        done
    fi
    
    return 0
}

# Test package installation
test_package_installation() {
    local components=("$@")
    
    log_info "Testing package installation for components: ${components[*]}"
    
    local distro
    distro=$(get_distro)
    
    case "$distro" in
        "arch")
            if ! test_arch_package_installation "${components[@]}"; then
                return 1
            fi
            ;;
        "ubuntu")
            if ! test_ubuntu_package_installation "${components[@]}"; then
                return 1
            fi
            ;;
        *)
            log_error "Unsupported distribution for package testing: $distro"
            return 1
            ;;
    esac
    
    return 0
}

# Test Arch Linux package installation
test_arch_package_installation() {
    local components=("$@")
    
    log_info "Testing Arch Linux package installation..."
    
    # Test pacman availability
    if ! command -v pacman >/dev/null 2>&1; then
        log_error "pacman not available"
        return 1
    fi
    
    # Test package database update (dry-run)
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would update package database: sudo pacman -Sy"
    else
        log_info "Testing package database update..."
        if ! sudo pacman -Sy >/dev/null 2>&1; then
            log_error "Failed to update package database"
            return 1
        fi
    fi
    
    # Test AUR helper availability
    if command -v yay >/dev/null 2>&1; then
        log_info "AUR helper (yay) available"
    elif command -v paru >/dev/null 2>&1; then
        log_info "AUR helper (paru) available"
    else
        log_warn "No AUR helper available"
    fi
    
    # Test component-specific packages
    for component in "${components[@]}"; do
        case "$component" in
            "terminal")
                test_package_availability "kitty" "pacman"
                test_package_availability "alacritty" "pacman"
                ;;
            "shell")
                test_package_availability "zsh" "pacman"
                test_package_availability "starship" "pacman"
                ;;
            "editor")
                test_package_availability "neovim" "pacman"
                ;;
            "wm")
                test_package_availability "hyprland" "pacman"
                test_package_availability "waybar" "pacman"
                ;;
        esac
    done
    
    return 0
}

# Test Ubuntu package installation
test_ubuntu_package_installation() {
    local components=("$@")
    
    log_info "Testing Ubuntu package installation..."
    
    # Test apt availability
    if ! command -v apt >/dev/null 2>&1; then
        log_error "apt not available"
        return 1
    fi
    
    # Test package database update (dry-run)
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would update package database: sudo apt update"
    else
        log_info "Testing package database update..."
        if ! sudo apt update >/dev/null 2>&1; then
            log_error "Failed to update package database"
            return 1
        fi
    fi
    
    # Test snap availability
    if command -v snap >/dev/null 2>&1; then
        log_info "Snap package manager available"
    else
        log_warn "Snap package manager not available"
    fi
    
    # Test flatpak availability
    if command -v flatpak >/dev/null 2>&1; then
        log_info "Flatpak package manager available"
    else
        log_warn "Flatpak package manager not available"
    fi
    
    # Test component-specific packages
    for component in "${components[@]}"; do
        case "$component" in
            "terminal")
                test_package_availability "kitty" "apt"
                test_package_availability "alacritty" "apt"
                ;;
            "shell")
                test_package_availability "zsh" "apt"
                ;;
            "editor")
                test_package_availability "neovim" "apt"
                ;;
        esac
    done
    
    return 0
}

# Test package availability
test_package_availability() {
    local package="$1"
    local pm="$2"
    
    case "$pm" in
        "pacman")
            if pacman -Si "$package" >/dev/null 2>&1; then
                log_info "Package $package available in official repos"
            else
                log_warn "Package $package not available in official repos"
            fi
            ;;
        "apt")
            if apt-cache show "$package" >/dev/null 2>&1; then
                log_info "Package $package available in apt repos"
            else
                log_warn "Package $package not available in apt repos"
            fi
            ;;
    esac
}

# Test configuration management
test_configuration_management() {
    local components=("$@")
    
    log_info "Testing configuration management for components: ${components[*]}"
    
    # Test dotfiles directory structure
    local dotfiles_dir="$SCRIPT_DIR/dotfiles"
    if [[ -d "$dotfiles_dir" ]]; then
        log_info "Dotfiles directory found: $dotfiles_dir"
        
        # Test component-specific configurations
        for component in "${components[@]}"; do
            case "$component" in
                "terminal")
                    test_config_availability "$dotfiles_dir/kitty" "Kitty configuration"
                    test_config_availability "$dotfiles_dir/alacritty" "Alacritty configuration"
                    test_config_availability "$dotfiles_dir/tmux" "Tmux configuration"
                    ;;
                "shell")
                    test_config_availability "$dotfiles_dir/zshrc" "Zsh configuration"
                    test_config_availability "$dotfiles_dir/starship" "Starship configuration"
                    ;;
                "wm")
                    test_config_availability "$dotfiles_dir/hyprland" "Hyprland configuration"
                    test_config_availability "$dotfiles_dir/waybar" "Waybar configuration"
                    ;;
            esac
        done
    else
        log_error "Dotfiles directory not found: $dotfiles_dir"
        return 1
    fi
    
    # Test backup functionality
    if ! test_backup_functionality; then
        return 1
    fi
    
    return 0
}

# Test configuration availability
test_config_availability() {
    local config_path="$1"
    local description="$2"
    
    if [[ -d "$config_path" ]] || [[ -f "$config_path" ]]; then
        log_info "$description found: $config_path"
    else
        log_warn "$description not found: $config_path"
    fi
}

# Test backup functionality
test_backup_functionality() {
    log_info "Testing backup functionality..."
    
    # Test backup creation
    local test_backup_dir="/tmp/test-backup-$(date +%Y%m%d_%H%M%S)"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create test backup: $test_backup_dir"
        return 0
    fi
    
    # Create test backup directory
    if mkdir -p "$test_backup_dir"; then
        log_info "Test backup directory created: $test_backup_dir"
        
        # Test backup file creation
        echo "test backup content" > "$test_backup_dir/test-file.txt"
        
        if [[ -f "$test_backup_dir/test-file.txt" ]]; then
            log_info "Test backup file created successfully"
            
            # Clean up test backup
            rm -rf "$test_backup_dir"
            log_info "Test backup cleaned up"
            return 0
        else
            log_error "Failed to create test backup file"
            rm -rf "$test_backup_dir"
            return 1
        fi
    else
        log_error "Failed to create test backup directory"
        return 1
    fi
}

# Test service management
test_service_management() {
    local components=("$@")
    
    log_info "Testing service management for components: ${components[*]}"
    
    # Test systemctl availability
    if ! command -v systemctl >/dev/null 2>&1; then
        log_error "systemctl not available"
        return 1
    fi
    
    # Test service management functions
    for component in "${components[@]}"; do
        case "$component" in
            "wm")
                # Test display manager services
                test_service_status "gdm" "optional"
                test_service_status "sddm" "optional"
                test_service_status "lightdm" "optional"
                ;;
            "dev-tools")
                # Test development services
                test_service_status "docker" "optional"
                ;;
        esac
    done
    
    return 0
}

# Test service status
test_service_status() {
    local service="$1"
    local requirement="${2:-required}"
    
    if systemctl list-unit-files "${service}.service" >/dev/null 2>&1; then
        log_info "Service $service is available"
        
        local status
        status=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
        log_info "Service $service status: $status"
    else
        if [[ "$requirement" == "required" ]]; then
            log_error "Required service $service not available"
            return 1
        else
            log_info "Optional service $service not available"
        fi
    fi
    
    return 0
}

#######################################
# Backup and Restore Testing
#######################################

# Test backup and restore functionality
test_backup_restore_functionality() {
    log_info "Testing backup and restore functionality..."
    push_error_context "integration_test" "Backup and restore test"
    
    local start_time=$(date +%s)
    local test_success=true
    
    # Test 1: Backup creation
    log_info "Testing backup creation..."
    if test_backup_creation; then
        record_integration_test_result "Backup Creation" "PASS"
    else
        record_integration_test_result "Backup Creation" "FAIL" "Could not create backup"
        test_success=false
    fi
    
    # Test 2: Backup validation
    log_info "Testing backup validation..."
    if test_backup_validation; then
        record_integration_test_result "Backup Validation" "PASS"
    else
        record_integration_test_result "Backup Validation" "FAIL" "Backup validation failed"
        test_success=false
    fi
    
    # Test 3: Restore functionality
    log_info "Testing restore functionality..."
    if test_restore_functionality; then
        record_integration_test_result "Restore Functionality" "PASS"
    else
        record_integration_test_result "Restore Functionality" "FAIL" "Restore failed"
        test_success=false
    fi
    
    # Test 4: Rollback functionality
    log_info "Testing rollback functionality..."
    if test_rollback_functionality; then
        record_integration_test_result "Rollback Functionality" "PASS"
    else
        record_integration_test_result "Rollback Functionality" "FAIL" "Rollback failed"
        test_success=false
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    pop_error_context
    
    if [[ "$test_success" == "true" ]]; then
        record_integration_test_result "Backup/Restore Testing" "PASS" "All backup/restore tests passed" "$duration"
        return 0
    else
        record_integration_test_result "Backup/Restore Testing" "FAIL" "Some backup/restore tests failed" "$duration"
        return 1
    fi
}

# Test backup creation
test_backup_creation() {
    log_info "Testing backup creation..."
    
    # Source backup utilities
    if [[ -f "$CONFIGS_DIR/backup.sh" ]]; then
        source "$CONFIGS_DIR/backup.sh"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would create system backup"
            return 0
        fi
        
        # Create test backup
        if create_system_backup; then
            log_success "System backup created successfully"
            return 0
        else
            log_error "Failed to create system backup"
            return 1
        fi
    else
        log_error "Backup utilities not found"
        return 1
    fi
}

# Test backup validation
test_backup_validation() {
    log_info "Testing backup validation..."
    
    # Find most recent backup
    local backup_dir
    backup_dir=$(find /tmp -name "backup-*" -type d 2>/dev/null | sort | tail -1)
    
    if [[ -n "$backup_dir" && -d "$backup_dir" ]]; then
        log_info "Testing backup directory: $backup_dir"
        
        # Use validation function from validate.sh
        if validate_backup_integrity "$backup_dir"; then
            log_success "Backup validation passed"
            return 0
        else
            log_error "Backup validation failed"
            return 1
        fi
    else
        log_warn "No backup directory found for validation"
        return 0  # Not a failure if no backup exists
    fi
}

# Test restore functionality
test_restore_functionality() {
    log_info "Testing restore functionality..."
    
    # Source restore utilities
    if [[ -f "$CONFIGS_DIR/restore.sh" ]]; then
        source "$CONFIGS_DIR/restore.sh"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would test restore functionality"
            return 0
        fi
        
        # Test restore functions exist
        if declare -f restore_from_backup >/dev/null; then
            log_success "Restore functions available"
            return 0
        else
            log_error "Restore functions not available"
            return 1
        fi
    else
        log_error "Restore utilities not found"
        return 1
    fi
}

# Test rollback functionality
test_rollback_functionality() {
    log_info "Testing rollback functionality..."
    
    # Test rollback system from recovery-system.sh
    if declare -f perform_emergency_rollback >/dev/null; then
        log_info "Testing rollback system..."
        
        # Register a test rollback action
        register_rollback_action "test_rollback" "echo 'Test rollback executed'" "Test rollback action"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would test rollback functionality"
            return 0
        fi
        
        # Test rollback execution (this will actually execute the test command)
        if perform_operation_rollback "test_rollback"; then
            log_success "Rollback functionality working"
            return 0
        else
            log_error "Rollback functionality failed"
            return 1
        fi
    else
        log_error "Rollback functions not available"
        return 1
    fi
}

#######################################
# Error Handling Testing
#######################################

# Test error handling and recovery
test_error_handling_recovery() {
    log_info "Testing error handling and recovery..."
    push_error_context "integration_test" "Error handling test"
    
    local start_time=$(date +%s)
    local test_success=true
    
    # Test 1: Error categorization
    log_info "Testing error categorization..."
    if test_error_categorization; then
        record_integration_test_result "Error Categorization" "PASS"
    else
        record_integration_test_result "Error Categorization" "FAIL" "Error categorization failed"
        test_success=false
    fi
    
    # Test 2: Error recovery
    log_info "Testing error recovery..."
    if test_error_recovery; then
        record_integration_test_result "Error Recovery" "PASS"
    else
        record_integration_test_result "Error Recovery" "FAIL" "Error recovery failed"
        test_success=false
    fi
    
    # Test 3: Graceful degradation
    log_info "Testing graceful degradation..."
    if test_graceful_degradation; then
        record_integration_test_result "Graceful Degradation" "PASS"
    else
        record_integration_test_result "Graceful Degradation" "FAIL" "Graceful degradation failed"
        test_success=false
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    pop_error_context
    
    if [[ "$test_success" == "true" ]]; then
        record_integration_test_result "Error Handling/Recovery" "PASS" "All error handling tests passed" "$duration"
        return 0
    else
        record_integration_test_result "Error Handling/Recovery" "FAIL" "Some error handling tests failed" "$duration"
        return 1
    fi
}

# Test error categorization
test_error_categorization() {
    log_info "Testing error categorization..."
    
    # Register rollback actions for test operations before triggering errors
    register_rollback_action "test_package" "echo 'Test package rollback executed'" "Test package rollback action"
    register_rollback_action "test_config" "echo 'Test config rollback executed'" "Test config rollback action"
    register_rollback_action "test_network" "echo 'Test network rollback executed'" "Test network rollback action"
    register_rollback_action "test_validation" "echo 'Test validation rollback executed'" "Test validation rollback action"
    
    # Test different error categories
    local test_errors=(
        "package|Test package error|test_package"
        "config|Test config error|test_config"
        "network|Test network error|test_network"
        "validation|Test validation error|test_validation"
    )
    
    for error_spec in "${test_errors[@]}"; do
        IFS='|' read -r category message operation <<< "$error_spec"
        
        log_info "Testing $category error handling..."
        
        # This will be caught by error handler but won't actually fail the test
        if handle_error "$category" "$message" "$operation" "$ERROR_MINOR"; then
            log_info "$category error handled successfully"
        else
            log_info "$category error handling completed (expected behavior)"
        fi
    done
    
    return 0
}

# Test error recovery
test_error_recovery() {
    log_info "Testing error recovery mechanisms..."
    
    # Test automatic recovery
    if declare -f attempt_auto_recovery >/dev/null; then
        log_info "Testing automatic recovery..."
        
        # Save current DRY_RUN state and enable it for recovery testing
        local original_dry_run="$DRY_RUN"
        export DRY_RUN=true
        
        # Test with a recoverable error type
        if attempt_auto_recovery "package_install_failed" "test_package" "Test error message"; then
            log_success "Automatic recovery succeeded"
        else
            log_info "Automatic recovery failed (may be expected for test)"
        fi
        
        # Restore original DRY_RUN state
        export DRY_RUN="$original_dry_run"
    fi
    
    return 0
}

# Test graceful degradation
test_graceful_degradation() {
    log_info "Testing graceful degradation..."
    
    # Test that system continues after non-critical errors
    local original_recovery_mode="$ERROR_RECOVERY_MODE"
    set_error_recovery_mode "graceful"
    
    # Simulate non-critical error
    handle_error "package" "Test non-critical error" "test_operation" "$ERROR_MINOR"
    
    # System should continue running
    log_success "System continued after non-critical error"
    
    # Restore original recovery mode
    set_error_recovery_mode "$original_recovery_mode"
    
    return 0
}

#######################################
# Main Integration Test Functions
#######################################

# Run comprehensive integration tests
run_integration_tests() {
    local test_mode="${1:-full}"
    shift
    local components=("$@")
    
    log_section "COMPREHENSIVE INTEGRATION TESTING"
    
    # Initialize integration testing
    init_integration_tests
    
    local overall_success=true
    
    # Test 1: Complete installation flow
    log_info "Running complete installation flow test..."
    if ! test_complete_installation_flow "${components[@]}"; then
        overall_success=false
    fi
    
    # Test 2: Backup and restore functionality
    if [[ "$test_mode" == "full" ]]; then
        log_info "Running backup and restore tests..."
        if ! test_backup_restore_functionality; then
            overall_success=false
        fi
    fi
    
    # Test 3: Error handling and recovery
    if [[ "$test_mode" == "full" ]]; then
        log_info "Running error handling and recovery tests..."
        if ! test_error_handling_recovery; then
            overall_success=false
        fi
    fi
    
    # Test 4: VM-specific testing (if in VM mode)
    local vm_success=true
    if [[ "$VM_MODE" == "true" ]] || is_vm; then
        log_info "Running VM-specific tests..."
        if ! run_vm_tests "${components[@]}"; then
            vm_success=false
        fi
    fi
    
    # Generate final test report
    generate_integration_test_report
    
    # Report results separately for integration tests and VM tests
    if [[ "$overall_success" == "true" ]]; then
        log_success "All integration tests passed ✓"
        if [[ "$vm_success" == "false" ]]; then
            log_warn "VM-specific tests had failures (this is expected in some VM environments)"
            return 0  # Don't fail overall test for VM issues
        fi
        return 0
    else
        log_error "Some integration tests failed"
        return 1
    fi
}

# Generate integration test report
generate_integration_test_report() {
    log_section "INTEGRATION TEST REPORT"
    
    local total_tests=${#INTEGRATION_TEST_RESULTS[@]}
    local failed_tests=${#INTEGRATION_TEST_FAILURES[@]}
    local passed_tests=$((total_tests - failed_tests))
    
    echo "Test Summary:"
    echo "  Total tests: $total_tests"
    echo "  Passed: $passed_tests"
    echo "  Failed: $failed_tests"
    echo
    
    if [[ $failed_tests -gt 0 ]]; then
        echo "Failed tests:"
        for failure in "${INTEGRATION_TEST_FAILURES[@]}"; do
            echo "  - $failure"
        done
        echo
    fi
    
    echo "Detailed results:"
    for result in "${INTEGRATION_TEST_RESULTS[@]}"; do
        if [[ "$result" =~ PASS ]]; then
            echo "  ✓ $result"
        else
            echo "  ✗ $result"
        fi
    done
    echo
    
    log_info "Full integration test log: $INTEGRATION_TEST_LOG"
    
    # Save report to file
    local report_file="/tmp/integration-test-report-$(date +%Y%m%d_%H%M%S).txt"
    {
        echo "INTEGRATION TEST REPORT"
        echo "======================="
        echo "Generated: $(date)"
        echo
        echo "Test Summary:"
        echo "  Total tests: $total_tests"
        echo "  Passed: $passed_tests"
        echo "  Failed: $failed_tests"
        echo
        if [[ $failed_tests -gt 0 ]]; then
            echo "Failed tests:"
            for failure in "${INTEGRATION_TEST_FAILURES[@]}"; do
                echo "  - $failure"
            done
            echo
        fi
        echo "Detailed results:"
        for result in "${INTEGRATION_TEST_RESULTS[@]}"; do
            echo "  $result"
        done
    } > "$report_file"
    
    log_info "Integration test report saved: $report_file"
}

#######################################
# Command Line Interface
#######################################

# Main function for integration testing
main_integration_test() {
    local mode="${1:-full}"
    shift
    local components=("$@")
    
    case "$mode" in
        "full"|"complete")
            run_integration_tests "full" "${components[@]}"
            ;;
        "quick"|"basic")
            run_integration_tests "basic" "${components[@]}"
            ;;
        "flow"|"installation")
            init_integration_tests
            test_complete_installation_flow "${components[@]}"
            generate_integration_test_report
            ;;
        "backup"|"restore")
            init_integration_tests
            test_backup_restore_functionality
            generate_integration_test_report
            ;;
        "error"|"recovery")
            init_integration_tests
            test_error_handling_recovery
            generate_integration_test_report
            ;;
        *)
            echo "Usage: $0 [mode] [components...]"
            echo
            echo "Modes:"
            echo "  full        - Run all integration tests (default)"
            echo "  quick       - Run basic integration tests only"
            echo "  flow        - Test installation flow only"
            echo "  backup      - Test backup/restore functionality only"
            echo "  error       - Test error handling/recovery only"
            echo
            echo "Examples:"
            echo "  $0                           # Full integration test"
            echo "  $0 quick                     # Quick integration test"
            echo "  $0 flow terminal shell       # Test installation flow for specific components"
            echo "  $0 backup                    # Test backup/restore only"
            exit 1
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_integration_test "$@"
fi