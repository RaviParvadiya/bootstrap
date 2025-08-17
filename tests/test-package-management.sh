#!/bin/bash

# Test script for package management functionality
# Tests the modular package management system

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source required modules
source "$PROJECT_ROOT/core/common.sh"
source "$PROJECT_ROOT/core/logger.sh"
source "$PROJECT_ROOT/distros/arch/packages.sh"

# Initialize logging
init_logger

# Test functions
test_package_list_parsing() {
    log_info "Testing package list parsing..."
    
    # Create a temporary test package list
    local test_file
    test_file=$(mktemp)
    
    cat > "$test_file" << 'EOF'
# Test package list
# Comments should be ignored

# --- Base packages ---
git
curl
wget

# --- Conditional packages ---
nvidia-dkms|nvidia
steam|gaming
batsignal|laptop

# Empty lines should be ignored

vim
nano
EOF
    
    # Test parsing with different conditions
    log_info "Testing with nvidia condition..."
    DRY_RUN=true arch_install_from_package_list "$test_file" "pacman" "nvidia"
    
    log_info "Testing with gaming condition..."
    DRY_RUN=true arch_install_from_package_list "$test_file" "pacman" "gaming"
    
    log_info "Testing with laptop condition..."
    DRY_RUN=true arch_install_from_package_list "$test_file" "pacman" "laptop"
    
    # Clean up
    rm -f "$test_file"
    
    log_success "Package list parsing test completed"
}

test_hardware_detection() {
    log_info "Testing hardware detection..."
    
    # Test GPU detection
    if arch_has_nvidia_gpu; then
        log_info "NVIDIA GPU detected"
    else
        log_info "No NVIDIA GPU detected"
    fi
    
    if arch_has_amd_gpu; then
        log_info "AMD GPU detected"
    else
        log_info "No AMD GPU detected"
    fi
    
    if arch_has_intel_gpu; then
        log_info "Intel GPU detected"
    else
        log_info "No Intel GPU detected"
    fi
    
    # Test system type detection
    if arch_is_laptop; then
        log_info "Laptop system detected"
    else
        log_info "Desktop system detected"
    fi
    
    if arch_is_vm; then
        log_info "Virtual machine detected"
    else
        log_info "Physical hardware detected"
    fi
    
    if arch_is_asus_hardware; then
        log_info "ASUS hardware detected"
    else
        log_info "Non-ASUS hardware detected"
    fi
    
    log_success "Hardware detection test completed"
}

test_condition_evaluation() {
    log_info "Testing condition evaluation..."
    
    # Test various condition combinations
    local test_conditions="nvidia,gaming,laptop"
    
    if arch_should_include_condition "nvidia" "$test_conditions"; then
        log_info "NVIDIA condition correctly included"
    fi
    
    if arch_should_include_condition "gaming" "$test_conditions"; then
        log_info "Gaming condition correctly included"
    fi
    
    if ! arch_should_include_condition "amd" "$test_conditions"; then
        log_info "AMD condition correctly excluded"
    fi
    
    log_success "Condition evaluation test completed"
}

test_package_categories() {
    log_info "Testing package category installation (dry run)..."
    
    # Test different package categories in dry run mode
    DRY_RUN=true
    
    log_info "Testing base package installation..."
    arch_install_packages_by_category "base" "nvidia,gaming"
    
    log_info "Testing AUR package installation..."
    arch_install_packages_by_category "aur" "nvidia,gaming"
    
    log_success "Package category test completed"
}

test_auto_package_installation() {
    log_info "Testing automatic package installation with condition detection..."
    
    # Test auto-detection and installation (dry run)
    DRY_RUN=true
    arch_install_packages_auto "all" "gaming"
    
    log_success "Auto package installation test completed"
}

# Main test execution
main() {
    log_info "Starting package management tests..."
    
    # Set dry run mode for all tests
    export DRY_RUN=true
    
    test_package_list_parsing
    test_hardware_detection
    test_condition_evaluation
    test_package_categories
    test_auto_package_installation
    
    log_success "All package management tests completed successfully!"
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi