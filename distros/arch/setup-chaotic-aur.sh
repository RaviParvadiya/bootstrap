#!/usr/bin/env bash

# Manual Chaotic-AUR Setup Script
# Use this if the automatic setup failed during installation

set -euo pipefail

echo "=== Manual Chaotic-AUR Setup ==="
echo "This script will set up the chaotic-aur repository manually"
echo

# Check if already configured
if grep -q "\[chaotic-aur\]" /etc/pacman.conf; then
    echo "✓ Chaotic-AUR repository is already configured"
    exit 0
fi

echo "Step 1: Retrieving and signing the chaotic-aur key..."
sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
sudo pacman-key --lsign-key 3056513887B78AEB

echo "Step 2: Installing chaotic-aur packages..."
sudo pacman -U '/chaotic-aur/chaotic-keyring.pkg.tar.zst'
sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

echo "Step 3: Adding repository to pacman.conf..."
echo -e '\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist' | sudo tee -a /etc/pacman.conf

echo "Step 4: Updating package database..."
sudo pacman -Sy

echo "✓ Chaotic-AUR repository setup completed successfully!"
echo "You can now install AUR packages faster using: sudo pacman -S <package-name>"