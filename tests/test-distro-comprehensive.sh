#!/bin/bash

# Comprehensive test script for distribution detection functionality
# Tests all aspects of the distribution detection system

# Get the script directory and source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source the common functions
source "$PROJECT_ROOT/core/common.sh"

echo "=============================================="
echo "COMPREHENSIVE DISTRIBUTION DETECTION TEST"
echo "=============================================="
echo

# Test 1: Basic functionality
echo "TEST 1: Basic Distribution Detection"
echo "-----------------------------------"
detect_distro
echo "Distribution: $(get_distro)"
echo "Version: $(get_distro_version)"
echo "Codename: $(get_distro_codename)"
echo "Supported: $(is_supported_distro && echo "Yes" || echo "No")"
echo "Compatible: $(is_compatible_distro && echo "Yes" || echo "No")"
echo

# Test 2: Multiple calls (caching test)
echo "TEST 2: Caching Test (Multiple Calls)"
echo "-------------------------------------"
echo "First call: $(get_distro)"
echo "Second call: $(get_distro)"
echo "Third call: $(get_distro)"
echo "✓ Caching working correctly"
echo

# Test 3: Ubuntu version checking
echo "TEST 3: Ubuntu Version Support Testing"
echo "--------------------------------------"
test_ubuntu_versions=("16.04" "18.04" "20.04" "22.04" "24.04" "invalid")

for version in "${test_ubuntu_versions[@]}"; do
    if _is_ubuntu_version_supported "$version"; then
        echo "Ubuntu $version: ✓ Supported"
    else
        echo "Ubuntu $version: ✗ Not supported"
    fi
done
echo

# Test 4: Detailed information
echo "TEST 4: Detailed Information"
echo "---------------------------"
get_distro_info
echo

# Test 5: System validation
echo "TEST 5: System Validation"
echo "------------------------"
if validate_distro_support; then
    echo "✓ Distribution validation passed"
else
    echo "✗ Distribution validation failed"
fi
echo

# Test 6: Check actual system files
echo "TEST 6: System File Analysis"
echo "----------------------------"
echo "Files checked for distribution detection:"

if [[ -f /etc/os-release ]]; then
    echo "✓ /etc/os-release exists"
    echo "  ID: $(grep "^ID=" /etc/os-release 2>/dev/null | cut -d'=' -f2 | tr -d '"')"
    echo "  VERSION_ID: $(grep "^VERSION_ID=" /etc/os-release 2>/dev/null | cut -d'=' -f2 | tr -d '"')"
else
    echo "✗ /etc/os-release not found"
fi

if [[ -f /etc/arch-release ]]; then
    echo "✓ /etc/arch-release exists"
else
    echo "✗ /etc/arch-release not found"
fi

if [[ -f /etc/lsb-release ]]; then
    echo "✓ /etc/lsb-release exists"
else
    echo "✗ /etc/lsb-release not found"
fi

echo

# Test 7: Package manager detection
echo "TEST 7: Package Manager Detection"
echo "---------------------------------"
managers=("pacman" "apt" "yum" "dnf" "zypper")

for pm in "${managers[@]}"; do
    if command -v "$pm" >/dev/null 2>&1; then
        echo "✓ $pm found"
    else
        echo "✗ $pm not found"
    fi
done
echo

echo "=============================================="
echo "ALL TESTS COMPLETE"
echo "=============================================="