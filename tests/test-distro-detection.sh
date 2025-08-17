#!/bin/bash

# Test script for distribution detection functionality
# This script tests the enhanced distribution detection logic

# Get the script directory and source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source the common functions
source "$PROJECT_ROOT/core/common.sh"

echo "=============================================="
echo "DISTRIBUTION DETECTION TEST"
echo "=============================================="
echo

# Enable verbose mode for detailed output
enable_verbose

echo "Testing distribution detection..."
echo

# Test basic detection
echo "1. Basic Distribution Detection:"
echo "   Distribution: $(get_distro)"
echo "   Version: $(get_distro_version)"
echo "   Codename: $(get_distro_codename)"
echo

# Test support checking
echo "2. Support Status:"
if is_supported_distro; then
    echo "   ✓ Fully supported distribution"
elif is_compatible_distro; then
    echo "   ⚠ Compatible but not fully tested"
else
    echo "   ✗ Unsupported distribution"
fi
echo

# Test detailed info
echo "3. Detailed Information:"
get_distro_info
echo

# Test validation
echo "4. Validation Test:"
if validate_distro_support; then
    echo "   ✓ Distribution validation passed"
else
    echo "   ✗ Distribution validation failed"
fi
echo

echo "=============================================="
echo "TEST COMPLETE"
echo "=============================================="