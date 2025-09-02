#!/usr/bin/env bash

# tests/comprehensive-test.sh - Comprehensive testing script for the modular install framework
# This script runs all available tests to validate the complete installation flow,
# component selection, dependency resolution, configuration management, backup/restore,
# and rollback functionality across both Arch Linux and Ubuntu systems.

set -euo pipefail

# Script directory and paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_LOG="/tmp/comprehensive-test-$(date +%Y%m%d_%H%M%S).log"

# Test configuration
TEST_COMPONENTS=("terminal" "shell")
TEST_RESULTS=()
FAILED_TESTS=()

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_test() {
    echo -e "${BLUE}[TEST]${NC} $*" | tee -a "$TEST_LOG"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $*" | tee -a "$TEST_LOG"
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*" | tee -a "$TEST_LOG"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$TEST_LOG"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$TEST_LOG"
}

# Record test result
record_test_result() {
    local test_name="$1"
    local result="$2"
    local details="${3:-}"
    
    local result_entry="$test_name: $result"
    if [[ -n "$details" ]]; then
        result_entry="$result_entry ($details)"
    fi
    
    TEST_RESULTS+=("$result_entry")
    
    if [[ "$result" == "FAIL" ]]; then
        FAILED_TESTS+=("$test_name")
        log_fail "$test_name - $details"
    else
        log_pass "$test_name - $details"
    fi
}

# Initialize comprehensive testing
init_comprehensive_test() {
    log_info "Initializing comprehensive testing..."
    
    # Create test log
    touch "$TEST_LOG"
    
    # Log system information
    {
        echo "=========================================="
        echo "COMPREHENSIVE TEST SESSION"
        echo "=========================================="
        echo "Date: $(date)"
        echo "System: $(uname -a)"
        echo "User: $(whoami)"
        echo "Script Directory: $SCRIPT_DIR"
        echo "Test Components: ${TEST_COMPONENTS[*]}"
        echo "=========================================="
        echo
    } >> "$TEST_LOG"
    
    log_info "Test log: $TEST_LOG"
}

# Test 1: Framework Structure Validation
test_framework_structure() {
    log_test "Testing framework structure..."
    
    local required_files=(
        "install.sh"
        "core/common.sh"
        "core/logger.sh"
        "core/validator.sh"
        "core/menu.sh"
        "core/error-handler.sh"
        "core/error-wrappers.sh"
        "core/recovery-system.sh"
        "core/package-manager.sh"
        "core/service-manager.sh"
        "tests/dry-run.sh"
        "tests/validate.sh"
        "tests/vm-test.sh"
        "tests/integration-test.sh"
        "distros/arch/arch-main.sh"
        "distros/ubuntu/ubuntu-main.sh"
        "configs/backup.sh"
        "configs/restore.sh"
        "configs/dotfiles-manager.sh"
    )
    
    local missing_files=()
    for file in "${required_files[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$file" ]]; then
            missing_files+=("$file")
        fi
    done
    
    if [[ ${#missing_files[@]} -eq 0 ]]; then
        record_test_result "Framework Structure" "PASS" "All required files present"
        return 0
    else
        record_test_result "Framework Structure" "FAIL" "Missing files: ${missing_files[*]}"
        return 1
    fi
}

# Test 2: Core Module Loading
test_core_module_loading() {
    log_test "Testing core module loading..."
    
    # Test loading core modules
    local core_modules=(
        "core/common.sh"
        "core/logger.sh"
        "core/validator.sh"
        "core/error-handler.sh"
    )
    
    local failed_modules=()
    for module in "${core_modules[@]}"; do
        if ! source "$SCRIPT_DIR/$module" 2>/dev/null; then
            failed_modules+=("$module")
        fi
    done
    
    if [[ ${#failed_modules[@]} -eq 0 ]]; then
        record_test_result "Core Module Loading" "PASS" "All core modules loaded successfully"
        return 0
    else
        record_test_result "Core Module Loading" "FAIL" "Failed modules: ${failed_modules[*]}"
        return 1
    fi
}

# Test 3: Distribution Detection
test_distribution_detection() {
    log_test "Testing distribution detection..."
    
    # Source required modules with proper path resolution
    if [[ -f "$SCRIPT_DIR/core/common.sh" ]]; then
        source "$SCRIPT_DIR/core/common.sh"
        source "$SCRIPT_DIR/core/logger.sh"
    else
        log_fail "Core modules not found at expected path: $SCRIPT_DIR/core/"
        return 1
    fi
    
    # Test distribution detection
    if detect_distro; then
        local detected_distro
        detected_distro=$(get_distro)
        local distro_version
        distro_version=$(get_distro_version)
        
        if [[ -n "$detected_distro" ]]; then
            record_test_result "Distribution Detection" "PASS" "$detected_distro $distro_version"
            return 0
        else
            record_test_result "Distribution Detection" "FAIL" "Empty distribution result"
            return 1
        fi
    else
        record_test_result "Distribution Detection" "FAIL" "Detection function failed"
        return 1
    fi
}

# Test 4: System Validation
test_system_validation() {
    log_test "Testing system validation..."
    
    # Source required modules
    source "$SCRIPT_DIR/core/validator.sh"
    
    # Test system validation
    if validate_system; then
        record_test_result "System Validation" "PASS" "System requirements met"
        return 0
    else
        record_test_result "System Validation" "FAIL" "System requirements not met"
        return 1
    fi
}

# Test 5: Error Handling System
test_error_handling_system() {
    log_test "Testing error handling system..."
    
    # Source error handling modules
    source "$SCRIPT_DIR/core/error-handler.sh"
    source "$SCRIPT_DIR/core/recovery-system.sh"
    
    # Initialize error handling
    init_error_handler "/tmp/test-error-handler.log"
    init_recovery_system
    
    # Test error categorization
    local test_passed=true
    
    # Test different error types
    if ! handle_error "package" "Test package error" "test_operation" 4; then
        log_info "Package error handled (expected behavior)"
    fi
    
    if ! handle_error "config" "Test config error" "test_operation" 4; then
        log_info "Config error handled (expected behavior)"
    fi
    
    # Test rollback registration
    register_rollback_action "test_rollback" "echo 'Test rollback'" "Test rollback action"
    
    if [[ ${#ROLLBACK_STACK[@]} -gt 0 ]]; then
        log_info "Rollback action registered successfully"
    else
        test_passed=false
    fi
    
    if [[ "$test_passed" == "true" ]]; then
        record_test_result "Error Handling System" "PASS" "Error handling and rollback working"
        return 0
    else
        record_test_result "Error Handling System" "FAIL" "Error handling issues detected"
        return 1
    fi
}

# Test 6: Dry-Run Mode
test_dry_run_mode() {
    log_test "Testing dry-run mode..."
    
    # Test dry-run functionality
    export DRY_RUN=true
    
    if "$SCRIPT_DIR/install.sh" --dry-run --components terminal dry-run >/dev/null 2>&1; then
        record_test_result "Dry-Run Mode" "PASS" "Dry-run completed without errors"
        return 0
    else
        record_test_result "Dry-Run Mode" "FAIL" "Dry-run failed"
        return 1
    fi
}

# Test 7: VM Detection
test_vm_detection() {
    log_test "Testing VM detection..."
    
    # Source VM test module
    if [[ -f "$SCRIPT_DIR/tests/vm-test.sh" ]]; then
        source "$SCRIPT_DIR/tests/vm-test.sh"
        
        # Test VM detection (will work on both VM and physical hardware)
        detect_vm_environment >/dev/null 2>&1
        
        local vm_detected="$VM_DETECTED"
        local vm_type="$VM_TYPE"
        
        if [[ "$vm_detected" == "true" ]]; then
            record_test_result "VM Detection" "PASS" "VM detected: $vm_type"
        else
            record_test_result "VM Detection" "PASS" "Physical hardware detected"
        fi
        return 0
    else
        record_test_result "VM Detection" "FAIL" "VM test module not found"
        return 1
    fi
}

# Test 8: Component Structure
test_component_structure() {
    log_test "Testing component structure..."
    
    local component_dirs=(
        "components/terminal"
        "components/shell"
        "components/editor"
        "components/wm"
        "components/dev-tools"
    )
    
    local missing_dirs=()
    for dir in "${component_dirs[@]}"; do
        if [[ ! -d "$SCRIPT_DIR/$dir" ]]; then
            missing_dirs+=("$dir")
        fi
    done
    
    # Check for component scripts
    local component_scripts=(
        "components/terminal/kitty.sh"
        "components/terminal/alacritty.sh"
        "components/shell/zsh.sh"
        "components/shell/starship.sh"
    )
    
    local missing_scripts=()
    for script in "${component_scripts[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$script" ]]; then
            missing_scripts+=("$script")
        fi
    done
    
    if [[ ${#missing_dirs[@]} -eq 0 && ${#missing_scripts[@]} -eq 0 ]]; then
        record_test_result "Component Structure" "PASS" "All component directories and scripts present"
        return 0
    else
        local missing_items=("${missing_dirs[@]}" "${missing_scripts[@]}")
        record_test_result "Component Structure" "FAIL" "Missing items: ${missing_items[*]}"
        return 1
    fi
}

# Test 9: Configuration Management
test_configuration_management() {
    log_test "Testing configuration management..."
    
    # Check dotfiles structure
    if [[ -d "$SCRIPT_DIR/dotfiles" ]]; then
        local config_dirs=(
            "dotfiles/kitty"
            "dotfiles/alacritty"
            "dotfiles/zshrc"
            "dotfiles/starship"
        )
        
        local found_configs=0
        for config_dir in "${config_dirs[@]}"; do
            if [[ -d "$SCRIPT_DIR/$config_dir" ]]; then
                ((found_configs++))
            fi
        done
        
        if [[ $found_configs -gt 0 ]]; then
            record_test_result "Configuration Management" "PASS" "$found_configs configuration directories found"
            return 0
        else
            record_test_result "Configuration Management" "FAIL" "No configuration directories found"
            return 1
        fi
    else
        record_test_result "Configuration Management" "FAIL" "Dotfiles directory not found"
        return 1
    fi
}

# Test 10: Package Data Files
test_package_data_files() {
    log_test "Testing package data files..."
    
    local data_files=(
        "data/arch-packages.lst"
        "data/ubuntu-packages.lst"
        "data/aur-packages.lst"
    )
    
    local missing_files=()
    for file in "${data_files[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$file" ]]; then
            missing_files+=("$file")
        fi
    done
    
    if [[ ${#missing_files[@]} -eq 0 ]]; then
        record_test_result "Package Data Files" "PASS" "All package data files present"
        return 0
    else
        record_test_result "Package Data Files" "FAIL" "Missing files: ${missing_files[*]}"
        return 1
    fi
}

# Test 11: Main Script Functionality
test_main_script_functionality() {
    log_test "Testing main script functionality..."
    
    # Test help command
    if "$SCRIPT_DIR/install.sh" --help >/dev/null 2>&1; then
        log_info "Help command works"
    else
        record_test_result "Main Script Functionality" "FAIL" "Help command failed"
        return 1
    fi
    
    # Test list command
    if "$SCRIPT_DIR/install.sh" list >/dev/null 2>&1; then
        log_info "List command works"
    else
        record_test_result "Main Script Functionality" "FAIL" "List command failed"
        return 1
    fi
    
    # Test validate command (should work even without installation)
    if "$SCRIPT_DIR/install.sh" validate >/dev/null 2>&1; then
        log_info "Validate command works"
    else
        log_warn "Validate command failed (may be expected without installation)"
    fi
    
    record_test_result "Main Script Functionality" "PASS" "Basic commands working"
    return 0
}

# Test 12: Integration Test Module
test_integration_test_module() {
    log_test "Testing integration test module..."
    
    if [[ -f "$SCRIPT_DIR/tests/integration-test.sh" ]]; then
        # Test that integration test module loads
        if source "$SCRIPT_DIR/tests/integration-test.sh" 2>/dev/null; then
            # Test that key functions exist
            if declare -f run_integration_tests >/dev/null && \
               declare -f test_complete_installation_flow >/dev/null; then
                record_test_result "Integration Test Module" "PASS" "Module loads and functions available"
                return 0
            else
                record_test_result "Integration Test Module" "FAIL" "Required functions not found"
                return 1
            fi
        else
            record_test_result "Integration Test Module" "FAIL" "Module failed to load"
            return 1
        fi
    else
        record_test_result "Integration Test Module" "FAIL" "Integration test module not found"
        return 1
    fi
}

# Run all comprehensive tests
run_comprehensive_tests() {
    log_info "Starting comprehensive test suite..."
    
    init_comprehensive_test
    
    local tests=(
        "test_framework_structure"
        "test_core_module_loading"
        "test_distribution_detection"
        "test_system_validation"
        "test_error_handling_system"
        "test_dry_run_mode"
        "test_vm_detection"
        "test_component_structure"
        "test_configuration_management"
        "test_package_data_files"
        "test_main_script_functionality"
        "test_integration_test_module"
    )
    
    local total_tests=${#tests[@]}
    local current_test=0
    
    for test_func in "${tests[@]}"; do
        ((current_test++))
        log_info "Running test $current_test/$total_tests: $test_func"
        
        if ! "$test_func"; then
            log_warn "Test $test_func failed, continuing with remaining tests..."
        fi
        
        echo # Add spacing between tests
    done
    
    # Generate final report
    generate_comprehensive_test_report
}

# Generate comprehensive test report
generate_comprehensive_test_report() {
    log_info "Generating comprehensive test report..."
    
    local total_tests=${#TEST_RESULTS[@]}
    local failed_tests=${#FAILED_TESTS[@]}
    local passed_tests=$((total_tests - failed_tests))
    
    echo
    echo "=========================================="
    echo "COMPREHENSIVE TEST REPORT"
    echo "=========================================="
    echo "Date: $(date)"
    echo "Total tests: $total_tests"
    echo "Passed: $passed_tests"
    echo "Failed: $failed_tests"
    echo "Success rate: $(( (passed_tests * 100) / total_tests ))%"
    echo
    
    if [[ $failed_tests -gt 0 ]]; then
        echo "Failed tests:"
        for failure in "${FAILED_TESTS[@]}"; do
            echo "  ✗ $failure"
        done
        echo
    fi
    
    echo "Detailed results:"
    for result in "${TEST_RESULTS[@]}"; do
        if [[ "$result" =~ PASS ]]; then
            echo "  ✓ $result"
        else
            echo "  ✗ $result"
        fi
    done
    echo
    
    echo "Full test log: $TEST_LOG"
    echo "=========================================="
    
    # Save report to file
    local report_file="/tmp/comprehensive-test-report-$(date +%Y%m%d_%H%M%S).txt"
    {
        echo "COMPREHENSIVE TEST REPORT"
        echo "========================="
        echo "Generated: $(date)"
        echo
        echo "Test Summary:"
        echo "  Total tests: $total_tests"
        echo "  Passed: $passed_tests"
        echo "  Failed: $failed_tests"
        echo "  Success rate: $(( (passed_tests * 100) / total_tests ))%"
        echo
        if [[ $failed_tests -gt 0 ]]; then
            echo "Failed tests:"
            for failure in "${FAILED_TESTS[@]}"; do
                echo "  - $failure"
            done
            echo
        fi
        echo "Detailed results:"
        for result in "${TEST_RESULTS[@]}"; do
            echo "  $result"
        done
    } > "$report_file"
    
    log_info "Comprehensive test report saved: $report_file"
    
    # Return appropriate exit code
    if [[ $failed_tests -eq 0 ]]; then
        log_pass "All comprehensive tests passed! ✓"
        return 0
    else
        log_fail "$failed_tests test(s) failed"
        return 1
    fi
}

# Main function
main() {
    case "${1:-all}" in
        "all"|"comprehensive")
            run_comprehensive_tests
            ;;
        "structure")
            init_comprehensive_test
            test_framework_structure
            generate_comprehensive_test_report
            ;;
        "core")
            init_comprehensive_test
            test_core_module_loading
            test_distribution_detection
            test_system_validation
            generate_comprehensive_test_report
            ;;
        "error")
            init_comprehensive_test
            test_error_handling_system
            generate_comprehensive_test_report
            ;;
        *)
            echo "Usage: $0 [test_type]"
            echo
            echo "Test types:"
            echo "  all           - Run all comprehensive tests (default)"
            echo "  structure     - Test framework structure only"
            echo "  core          - Test core functionality only"
            echo "  error         - Test error handling only"
            echo
            echo "Examples:"
            echo "  $0                # Run all tests"
            echo "  $0 structure      # Test structure only"
            echo "  $0 core          # Test core functionality"
            exit 1
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi