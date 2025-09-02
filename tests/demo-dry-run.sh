#!/usr/bin/env bash

# Demo script to show dry-run functionality working
# This demonstrates the core dry-run features without dependencies

set -euo pipefail

# Initialize all project paths
source "$(dirname "${BASH_SOURCE[0]}")/../core/init-paths.sh"

# Source required modules
source "$CORE_DIR/common.sh"
source "$CORE_DIR/logger.sh"
source "$TESTS_DIR/dry-run.sh"

# Demo function
demo_dry_run() {
    echo "=== DRY-RUN FUNCTIONALITY DEMONSTRATION ==="
    echo
    
    # Initialize dry-run mode
    init_dry_run
    
    echo "1. Testing package installation tracking:"
    track_package_install "neovim" "pacman" "official"
    track_package_install "kitty" "pacman" "official"
    track_package_install "yay" "yay" "AUR"
    
    echo
    echo "2. Testing configuration operations:"
    track_config_operation "/home/user/.config/nvim/init.lua" "symlink" "/dotfiles/nvim/init.lua -> /home/user/.config/nvim/init.lua"
    track_config_operation "/home/user/.config/kitty/kitty.conf" "backup" "existing config backed up"
    track_config_operation "/home/user/.zshrc" "create" "new configuration file"
    
    echo
    echo "3. Testing service operations:"
    track_service_operation "docker" "enable" "container runtime"
    track_service_operation "bluetooth" "disable" "power saving"
    
    echo
    echo "4. Testing command execution:"
    track_command_execution "git clone https://github.com/user/dotfiles" "Clone dotfiles repository"
    track_command_execution "chmod +x ~/.local/bin/scripts/*" "Make scripts executable"
    
    echo
    echo "5. Testing dry-run overrides:"
    enable_dry_run_overrides
    
    # These should be intercepted by dry-run overrides
    install_package "test-package" "pacman"
    create_symlink "/tmp/test-source" "/tmp/test-target" 2>/dev/null || true
    
    disable_dry_run_overrides
    
    echo
    echo "6. Final summary:"
    finalize_dry_run
}

# Run demo
demo_dry_run