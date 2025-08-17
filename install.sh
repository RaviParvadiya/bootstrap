#!/bin/bash

# Modular Install Framework
# Main entry point for the installation system
# Supports Arch Linux and Ubuntu distributions

set -euo pipefail

# Script directory and paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$SCRIPT_DIR/core"
DISTROS_DIR="$SCRIPT_DIR/distros"
COMPONENTS_DIR="$SCRIPT_DIR/components"
CONFIGS_DIR="$SCRIPT_DIR/configs"
DATA_DIR="$SCRIPT_DIR/data"
TESTS_DIR="$SCRIPT_DIR/tests"

# Global variables
DRY_RUN=false
VM_MODE=false
VERBOSE=false
SELECTED_COMPONENTS=()
DETECTED_DISTRO=""

# Source core utilities
source "$CORE_DIR/common.sh"
source "$CORE_DIR/logger.sh"
source "$CORE_DIR/validator.sh"
source "$CORE_DIR/menu.sh"

# Display usage information
show_usage() {
    cat << EOF
Modular Install Framework

Usage: $0 [OPTIONS] [COMMAND]

OPTIONS:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    -d, --dry-run       Show what would be done without executing
    -t, --test          Run in test mode (VM-safe)
    -c, --components    Comma-separated list of components to install

COMMANDS:
    install             Run interactive installation (default)
    restore             Restore from backup
    validate            Validate current installation
    backup              Create system backup
    list                List available components

EXAMPLES:
    $0                                  # Interactive installation
    $0 --dry-run install               # Preview installation
    $0 --components terminal,shell      # Install specific components
    $0 validate                        # Validate installation

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -t|--test)
                VM_MODE=true
                shift
                ;;
            -c|--components)
                IFS=',' read -ra SELECTED_COMPONENTS <<< "$2"
                shift 2
                ;;
            install|restore|validate|backup|list)
                COMMAND="$1"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Default command
    COMMAND="${COMMAND:-install}"
}

# Main installation orchestrator
main() {
    # Initialize logging
    init_logger
    
    log_info "Starting Modular Install Framework"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Set global flags
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Running in DRY-RUN mode - no changes will be made"
    fi
    
    if [[ "$VM_MODE" == "true" ]]; then
        log_info "Running in VM mode - hardware-specific configs will be skipped"
    fi
    
    # Detect distribution first
    log_info "Detecting Linux distribution..."
    detect_distro
    DETECTED_DISTRO=$(get_distro)
    if [[ -z "$DETECTED_DISTRO" ]]; then
        log_error "Failed to detect Linux distribution"
        exit 1
    fi
    log_info "Detected distribution: $DETECTED_DISTRO"
    
    # Validate distribution support
    if ! validate_distro_support; then
        log_error "Distribution not supported or validation failed"
        exit 1
    fi
    
    # Validate system prerequisites
    log_info "Validating system requirements..."
    validate_system || {
        log_error "System validation failed"
        exit 1
    }
    
    # Execute command
    case "$COMMAND" in
        install)
            run_installation
            ;;
        restore)
            run_restoration
            ;;
        validate)
            run_validation
            ;;
        backup)
            run_backup
            ;;
        list)
            list_components
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            exit 1
            ;;
    esac
    
    log_success "Operation completed successfully"
}

# Run installation process
run_installation() {
    log_info "Starting installation process..."
    
    # Component selection
    if [[ ${#SELECTED_COMPONENTS[@]} -eq 0 ]]; then
        log_info "Opening component selection menu..."
        select_components
    else
        log_info "Using pre-selected components: ${SELECTED_COMPONENTS[*]}"
    fi
    
    # Create pre-installation backup
    if ask_yes_no "Create backup before installation?"; then
        log_info "Creating pre-installation backup..."
        source "$CONFIGS_DIR/backup.sh"
        create_system_backup
    fi
    
    # Route to distribution-specific handler
    case "$DETECTED_DISTRO" in
        "arch")
            source "$DISTROS_DIR/arch/arch-main.sh"
            arch_main_install "${SELECTED_COMPONENTS[@]}"
            ;;
        "ubuntu")
            source "$DISTROS_DIR/ubuntu/ubuntu-main.sh"
            ubuntu_main_install "${SELECTED_COMPONENTS[@]}"
            ;;
        *)
            log_error "Unsupported distribution: $DETECTED_DISTRO"
            exit 1
            ;;
    esac
    
    # Apply dotfiles configurations
    log_info "Applying dotfiles configurations..."
    source "$CONFIGS_DIR/dotfiles-manager.sh"
    manage_dotfiles "${SELECTED_COMPONENTS[@]}"
    
    # Post-installation validation
    log_info "Running post-installation validation..."
    if [[ -f "$TESTS_DIR/validate.sh" ]]; then
        source "$TESTS_DIR/validate.sh"
        validate_installation
    fi
    
    log_success "Installation process completed successfully!"
}

# Run restoration process
run_restoration() {
    log_info "Starting restoration process..."
    
    # Source restoration utilities
    source "$CONFIGS_DIR/restore.sh"
    
    # Check if specific backup file provided
    if [[ ${#SELECTED_COMPONENTS[@]} -gt 0 ]]; then
        # Treat first component as backup file path
        local backup_file="${SELECTED_COMPONENTS[0]}"
        
        if [[ -f "$backup_file" ]]; then
            log_info "Restoring from specified backup: $backup_file"
            restore_from_backup "$backup_file"
        else
            log_error "Backup file not found: $backup_file"
            exit 1
        fi
    else
        # Interactive restoration
        interactive_restore
    fi
}

# Run validation process
run_validation() {
    log_info "Starting validation process..."
    
    # Source validation utilities
    source "$TESTS_DIR/validate.sh"
    
    # Validate system state
    validate_installation
}

# Run backup process
run_backup() {
    log_info "Starting backup process..."
    
    # Source backup utilities
    source "$CONFIGS_DIR/backup.sh"
    
    if [[ ${#SELECTED_COMPONENTS[@]} -gt 0 ]]; then
        # Backup specific components
        for component in "${SELECTED_COMPONENTS[@]}"; do
            create_config_backup "$component"
        done
    else
        # Create comprehensive system backup
        create_system_backup
    fi
}

# List available components
list_components() {
    log_info "Available components:"
    
    echo
    echo "=== Terminal Components ==="
    echo "  - alacritty    : Alacritty terminal emulator"
    echo "  - kitty        : Kitty terminal emulator"
    echo "  - tmux         : Terminal multiplexer"
    
    echo
    echo "=== Shell Components ==="
    echo "  - zsh          : Z shell with plugins"
    echo "  - starship     : Cross-shell prompt"
    
    echo
    echo "=== Editor Components ==="
    echo "  - neovim       : Neovim text editor"
    echo "  - vscode       : Visual Studio Code"
    
    echo
    echo "=== Window Manager Components ==="
    echo "  - hyprland     : Hyprland wayland compositor"
    echo "  - waybar       : Wayland status bar"
    echo "  - wofi         : Application launcher"
    echo "  - swaync       : Notification daemon"
    
    echo
    echo "=== Development Tools ==="
    echo "  - git          : Git version control"
    echo "  - docker       : Docker containerization"
    echo "  - languages    : Programming language tools"
    
    echo
    echo "=== Component Groups ==="
    echo "  - terminal     : All terminal-related components"
    echo "  - shell        : All shell-related components"
    echo "  - editor       : All editor-related components"
    echo "  - wm           : All window manager components"
    echo "  - dev-tools    : All development tools"
    
    echo
    echo "Usage examples:"
    echo "  $0 --components terminal,shell    # Install terminal and shell components"
    echo "  $0 --components hyprland         # Install only Hyprland"
    echo "  $0 backup --components terminal  # Backup terminal configurations"
    echo "  $0 restore                       # Interactive restoration menu"
}

# Error handling
trap 'log_error "Script interrupted"; exit 1' INT TERM

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi