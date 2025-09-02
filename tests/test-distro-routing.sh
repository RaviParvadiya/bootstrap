#!/usr/bin/env bash

# Test script for distribution routing logic
# Simulates how the main install script would route to distribution-specific handlers

# Get the script directory and source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source the common functions
source "$PROJECT_ROOT/core/common.sh"

echo "=============================================="
echo "DISTRIBUTION ROUTING TEST"
echo "=============================================="
echo

# Test distribution detection and routing
echo "Testing distribution routing logic..."
echo

# Detect the distribution
if ! validate_distro_support; then
    echo "✗ Distribution validation failed - would exit here"
    exit 1
fi

distro=$(get_distro)
version=$(get_distro_version)

echo "Detected: $distro $version"
echo

# Simulate routing logic
case "$distro" in
    "arch")
        echo "✓ Would route to: distros/arch/arch-main.sh"
        echo "  - Full Arch Linux installation from scratch"
        echo "  - Package management via pacman/AUR"
        echo "  - Complete desktop environment setup"
        
        # Check if the arch handler exists
        if [[ -f "$PROJECT_ROOT/distros/arch/arch-main.sh" ]]; then
            echo "  ✓ Arch handler script exists"
        else
            echo "  ✗ Arch handler script missing"
        fi
        ;;
    "ubuntu")
        echo "✓ Would route to: distros/ubuntu/ubuntu-main.sh"
        echo "  - Hyprland environment installation"
        echo "  - User-space configuration only"
        echo "  - Component selection interface"
        
        # Check if the ubuntu handler exists
        if [[ -f "$PROJECT_ROOT/distros/ubuntu/ubuntu-main.sh" ]]; then
            echo "  ✓ Ubuntu handler script exists"
        else
            echo "  ✗ Ubuntu handler script missing"
        fi
        ;;
    *)
        echo "✗ Unsupported distribution: $distro"
        echo "  Would display error and exit"
        ;;
esac

echo
echo "=============================================="
echo "ROUTING TEST COMPLETE"
echo "=============================================="