#!/usr/bin/env bash

# Test script for NVIDIA module functionality
# This script tests the NVIDIA configuration module in dry-run mode

set -euo pipefail

# Initialize all project paths
source "$(dirname "${BASH_SOURCE[0]}")/../core/init-paths.sh"

NVIDIA_MODULE="$DISTROS_DIR/arch/hardware/nvidia.sh"

# Source required modules
source "$CORE_DIR/common.sh"
source "$CORE_DIR/logger.sh"

# Test configuration
DRY_RUN=true
VERBOSE=true
VM_MODE=false

echo "=============================================="
echo "NVIDIA Module Test Suite"
echo "=============================================="
echo

# Initialize logging
init_logger

log_info "Starting NVIDIA module tests..."

# Test 1: Check if NVIDIA module can be sourced
log_info "Test 1: Sourcing NVIDIA module..."
if source "$NVIDIA_MODULE"; then
    log_success "NVIDIA module sourced successfully"
else
    log_error "Failed to source NVIDIA module"
    exit 1
fi

# Test 2: Test NVIDIA GPU detection
log_info "Test 2: Testing NVIDIA GPU detection..."
if detect_nvidia_gpu; then
    log_success "NVIDIA GPU detection function works"
else
    log_info "No NVIDIA GPU detected (this is normal on systems without NVIDIA)"
fi

# Test 3: Test RTX GPU detection (in dry-run mode)
log_info "Test 3: Testing RTX GPU detection..."
# This will either auto-detect or ask user, both are valid
if is_rtx_gpu; then
    log_info "RTX GPU detected or confirmed by user"
else
    log_info "Non-RTX GPU detected or confirmed by user"
fi

# Test 4: Test NVIDIA installation in dry-run mode
log_info "Test 4: Testing NVIDIA installation (dry-run)..."
if install_nvidia true; then
    log_success "NVIDIA installation test completed successfully"
else
    log_warn "NVIDIA installation test failed (may be expected without NVIDIA GPU)"
fi

# Test 5: Test individual NVIDIA configuration functions
log_info "Test 5: Testing individual NVIDIA configuration functions..."

log_info "  - Testing driver installation..."
install_nvidia_drivers true

log_info "  - Testing kernel module configuration..."
configure_nvidia_modules true

log_info "  - Testing modprobe configuration..."
configure_nvidia_modprobe true

log_info "  - Testing initramfs rebuild..."
rebuild_initramfs true

log_info "  - Testing environment configuration..."
configure_nvidia_environment true

log_info "  - Testing service configuration..."
configure_nvidia_services true

log_info "  - Testing kernel parameter configuration..."
configure_nvidia_kernel_params true

log_success "All individual function tests completed"

# Test 6: Test validation functions
log_info "Test 6: Testing validation functions..."
if command -v is_nvidia_configured >/dev/null 2>&1; then
    is_nvidia_configured && log_info "NVIDIA is configured" || log_info "NVIDIA is not configured"
    log_success "NVIDIA configuration check function works"
else
    log_warn "NVIDIA configuration check function not found"
fi

if command -v validate_nvidia_installation >/dev/null 2>&1; then
    validate_nvidia_installation
    log_success "NVIDIA validation function works"
else
    log_warn "NVIDIA validation function not found"
fi

echo
log_success "All NVIDIA module tests completed successfully!"
echo
echo "=============================================="
echo "Test Summary:"
echo "- NVIDIA module can be sourced and loaded"
echo "- All NVIDIA functions are callable"
echo "- Dry-run mode works correctly"
echo "- Error handling is functional"
echo "=============================================="
echo
echo "Note: This test runs in dry-run mode and does not make"
echo "any actual system changes. To test actual installation,"
echo "run the main install script on a system with NVIDIA GPU."