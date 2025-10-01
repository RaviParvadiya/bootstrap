#!/usr/bin/env bash

#######################################
# Modular Install Framework
# 
# Main entry point for the modular installation system that automates
# Linux development environment setup across multiple distributions.
# 
# Supported Distributions:
#   - Arch Linux (complete installation from scratch)
#   - Ubuntu 18.04+ (Hyprland environment installation)
# 
# Features:
#   - Interactive component selection
#   - Hardware detection (NVIDIA, ASUS TUF)
#   - Safety modes (dry-run, VM testing, backups)
#   - Modular architecture for easy extension
#   - Comprehensive logging and error handling
# 
# Usage:
#   ./install.sh [OPTIONS]
# 
# Options:
#   --dry-run          Preview operations without making changes
#   --test             VM-safe mode (skips hardware-specific configs)
#   --verbose          Enable detailed output
#   --components LIST  Install specific components (comma-separated)
#   --help             Show help message
# 
# Examples:
#   ./install.sh                           # Interactive installation
#   ./install.sh --dry-run                 # Preview mode
#   ./install.sh --components terminal,shell  # Install specific components
#   ./install.sh --test --verbose          # VM testing with detailed output
# 
# Requirements:
#   - Linux system (Arch Linux or Ubuntu 18.04+)
#   - Internet connection
#   - Sudo access (do not run as root)
#   - Basic tools: curl, git, tar, unzip
# 
# Documentation:
#   - README.md - Main installation guide
#   - TESTING.md - Safety testing procedures
#   - docs/USAGE_EXAMPLES.md - Comprehensive examples
#   - docs/FUNCTION_REFERENCE.md - Developer reference
#######################################

set -euo pipefail
IFS=$'\n\t'

# Initialize project paths (centralized path resolution)
source "$(dirname "${BASH_SOURCE[0]}")/core/init-paths.sh"

# Global variables
DRY_RUN=false
VM_MODE=false
VERBOSE=false
USE_MINIMAL_PACKAGES=true  # Use minimal package lists by default for post-installation
SELECTED_COMPONENTS=()
DETECTED_DISTRO=""

# Source core utilities with error handling
source_with_error_check() {
    local file="$1"
    if [[ -f "$file" ]]; then
        source "$file"
    else
        echo "ERROR: Required file not found: $file" >&2
        exit 1
    fi
}

source_with_error_check "$CORE_DIR/common.sh"
source_with_error_check "$CORE_DIR/logger.sh"
source_with_error_check "$CORE_DIR/validator.sh"
source_with_error_check "$CORE_DIR/menu.sh"
source_with_error_check "$CORE_DIR/error-handler.sh"
source_with_error_check "$CORE_DIR/error-wrappers.sh"
source_with_error_check "$CORE_DIR/recovery-system.sh"

# Source additional utilities based on mode
if [[ "$DRY_RUN" == "true" ]]; then
    source_with_error_check "$TESTS_DIR/dry-run.sh"
fi

# Source package manager utilities
source_with_error_check "$CORE_DIR/package-manager.sh"
source_with_error_check "$CORE_DIR/service-manager.sh"

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
    -m, --minimal       Use minimal package lists (default for post-installation)
    -f, --full          Use full package lists (for fresh installations)

COMMANDS:
    install             Run interactive installation (default)
    restore             Restore from backup
    validate            Validate current installation
    backup              Create system backup
    list                List available components
    dry-run             Run dry-run test mode
    test                Run comprehensive integration tests

EXAMPLES:
    $0                                  # Interactive installation
    $0 --dry-run install               # Preview installation
    $0 --components terminal,shell      # Install specific components
    $0 dry-run                         # Interactive dry-run mode
    $0 validate                        # Validate installation
    $0 test                            # Run integration tests
    $0 test --components terminal      # Test specific components

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
            -m|--minimal)
                USE_MINIMAL_PACKAGES=true
                shift
                ;;
            -f|--full)
                USE_MINIMAL_PACKAGES=false
                shift
                ;;
            install|restore|validate|backup|list|dry-run|test)
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

# Main installation orchestrator with comprehensive error handling
main() {
    local exit_code=0
    
    # Initialize logging first
    init_logger
    
    # Initialize error handling system with comprehensive configuration
    init_error_handler "/tmp/modular-install-errors-$(date +%Y%m%d_%H%M%S).log"
    set_error_recovery_mode "graceful"
    set_rollback_enabled "true"
    
    # Initialize recovery system
    init_recovery_system
    
    # Create initial system checkpoint
    create_checkpoint "system_start" "System state before installation"
    
    log_info "Starting Modular Install Framework v1.0"
    log_info "Error handling: graceful recovery mode enabled"
    log_info "Rollback system: enabled"
    
    # Parse command line arguments with error handling
    if ! parse_arguments "$@"; then
        handle_error "critical" "Failed to parse command line arguments" "argument_parsing"
        cleanup_and_exit 1
    fi
    
    # Set global flags and export for child processes
    export DRY_RUN VERBOSE VM_MODE COMMAND
    
    # Initialize mode-specific systems
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Running in DRY-RUN mode - no changes will be made"
        # Source dry-run utilities if not already sourced
        if [[ -f "$TESTS_DIR/dry-run.sh" ]]; then
            source "$TESTS_DIR/dry-run.sh"
            init_dry_run
            enable_dry_run_overrides
        else
            handle_error "critical" "Dry-run utilities not found" "dry_run_init"
            cleanup_and_exit 1
        fi
    fi
    
    if [[ "$VM_MODE" == "true" ]]; then
        log_info "Running in VM mode - hardware-specific configs will be skipped"
        # Detect VM environment for better hardware skipping
        if [[ -f "$TESTS_DIR/vm-test.sh" ]]; then
            source "$TESTS_DIR/vm-test.sh"
            detect_vm_environment
        fi
    fi
    
    # System detection and validation with error handling
    push_error_context "system_detection" "Detecting and validating system"
    
    log_info "Detecting Linux distribution..."
    if ! detect_distro; then
        handle_error "critical" "Failed to detect Linux distribution" "distro_detection"
        cleanup_and_exit 1
    fi
    
    DETECTED_DISTRO=$(get_distro)
    if [[ -z "$DETECTED_DISTRO" ]]; then
        handle_error "critical" "Distribution detection returned empty result" "distro_detection"
        cleanup_and_exit 1
    fi
    
    log_info "Detected distribution: $DETECTED_DISTRO $(get_distro_version)"
    
    # Validate distribution support
    if ! validate_distro_support; then
        handle_error "critical" "Distribution not supported or validation failed" "distro_validation"
        cleanup_and_exit 1
    fi
    
    # Validate system prerequisites
    log_info "Validating system requirements..."
    if ! validate_system; then
        handle_error "critical" "System validation failed" "system_validation"
        cleanup_and_exit 1
    fi
    
    # Check and setup dotfiles repository
    log_info "Checking dotfiles repository..."
    if [[ -d "$SCRIPT_DIR/dotfiles" ]]; then
        if [[ -d "$SCRIPT_DIR/dotfiles/.git" ]]; then
            log_info "Dotfiles repository found and is a valid git repository"
            log_info "Fetching latest changes from remote repository..."
            
            # Change to dotfiles directory and fetch latest changes
            pushd "$SCRIPT_DIR/dotfiles" > /dev/null
            if ! git fetch origin; then
                handle_error "config" "Failed to fetch latest changes from dotfiles repository" "dotfiles_fetch"
                log_warn "Continuing with existing dotfiles version"
            else
                # Pull latest changes if we're on a branch that tracks origin
                local current_branch
                current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
                if [[ -n "$current_branch" && "$current_branch" != "HEAD" ]]; then
                    if git rev-parse --verify "origin/$current_branch" >/dev/null 2>&1; then
                        if ! git pull origin "$current_branch"; then
                            handle_error "config" "Failed to pull latest changes from dotfiles repository" "dotfiles_pull"
                            log_warn "Continuing with existing dotfiles version"
                        else
                            log_success "Dotfiles repository updated to latest version"
                        fi
                    else
                        log_info "Current branch does not track origin, skipping pull"
                    fi
                else
                    log_info "Not on a named branch, skipping pull"
                fi
            fi
            popd > /dev/null
        else
            log_warn "Dotfiles directory exists but is not a git repository"
            log_info "Removing existing dotfiles directory and cloning repository..."
            rm -rf "$SCRIPT_DIR/dotfiles"
            if ! git clone https://github.com/RaviParvadiya/dotfiles.git "$SCRIPT_DIR/dotfiles"; then
                handle_error "critical" "Failed to clone dotfiles repository" "dotfiles_clone"
                cleanup_and_exit 1
            fi
            log_success "Dotfiles repository cloned successfully"
        fi
    else
        log_info "Dotfiles directory not found, cloning repository..."
        if ! git clone https://github.com/RaviParvadiya/dotfiles.git "$SCRIPT_DIR/dotfiles"; then
            handle_error "critical" "Failed to clone dotfiles repository" "dotfiles_clone"
            cleanup_and_exit 1
        fi
        log_success "Dotfiles repository cloned successfully"
    fi
    pop_error_context
    
    # Execute command with comprehensive error handling
    push_error_context "command_execution" "Executing command: $COMMAND"
    
    case "$COMMAND" in
        install)
            if ! run_installation; then
                exit_code=1
            fi
            ;;
        restore)
            if ! run_restoration; then
                exit_code=1
            fi
            ;;
        validate)
            if ! run_validation; then
                exit_code=1
            fi
            ;;
        backup)
            if ! run_backup; then
                exit_code=1
            fi
            ;;
        list)
            list_components
            ;;
        dry-run)
            if ! run_dry_run_mode; then
                exit_code=1
            fi
            ;;
        test)
            if ! run_integration_tests; then
                exit_code=1
            fi
            ;;
        *)
            handle_error "critical" "Unknown command: $COMMAND" "command_execution"
            exit_code=1
            ;;
    esac
    
    pop_error_context
    
    # Finalize systems
    if [[ "$DRY_RUN" == "true" ]]; then
        finalize_dry_run
        disable_dry_run_overrides
    fi
    
    # Show error summary if there were any issues
    if [[ ${#FAILED_OPERATIONS[@]} -gt 0 ]]; then
        show_error_summary
        log_warn "Installation completed with ${#FAILED_OPERATIONS[@]} issues"
        exit_code=1
    fi
    
    # Create final checkpoint
    create_checkpoint "system_end" "System state after installation"
    
    if [[ $exit_code -eq 0 ]]; then
        log_success "Operation completed successfully ✓"
    else
        log_warn "Operation completed with issues (exit code: $exit_code)"
    fi
    
    # Clean up old checkpoints
    cleanup_old_checkpoints 5
    
    exit $exit_code
}

# Run installation process with comprehensive error handling and recovery
run_installation() {
    push_error_context "installation" "Main installation process"
    
    log_info "Starting installation process..."
    local installation_success=true
    
    # Create pre-installation checkpoint
    create_checkpoint "pre_installation" "System state before installation"
    
    # Component selection with error handling
    if [[ ${#SELECTED_COMPONENTS[@]} -eq 0 ]]; then
        log_info "Opening component selection menu..."
        if ! select_components; then
            handle_error "critical" "Component selection failed" "component_selection"
            pop_error_context
            return 1
        fi
    else
        log_info "Using pre-selected components: ${SELECTED_COMPONENTS[*]}"
    fi
    
    # Validate component selection
    if [[ ${#SELECTED_COMPONENTS[@]} -eq 0 ]]; then
        handle_error "critical" "No components selected for installation" "component_selection"
        pop_error_context
        return 1
    fi
    
    # Create pre-installation backup with error handling
    if ask_yes_no "Create backup before installation?" "y"; then
        log_info "Creating pre-installation backup..."
        push_error_context "backup" "Creating pre-installation backup"
        
        if [[ -f "$CONFIGS_DIR/backup.sh" ]]; then
            source "$CONFIGS_DIR/backup.sh"
            if ! safe_execute_command "create_system_backup" "Create system backup"; then
                handle_error "config" "Failed to create pre-installation backup" "backup_creation"
                if ask_yes_no "Continue installation without backup?" "n"; then
                    log_warn "Continuing installation without backup"
                else
                    pop_error_context
                    pop_error_context
                    return 1
                fi
            else
                log_success "Pre-installation backup created successfully"
            fi
        else
            handle_error "config" "Backup utilities not found" "backup_utilities"
        fi
        
        pop_error_context
    fi
    
    # Route to distribution-specific handler with error handling
    push_error_context "distro_install" "Distribution-specific installation"
    
    case "$DETECTED_DISTRO" in
        "arch")
            log_info "Starting Arch Linux installation..."
            if [[ -f "$DISTROS_DIR/arch/arch-main.sh" ]]; then
                source "$DISTROS_DIR/arch/arch-main.sh"
                if ! arch_main_install "${SELECTED_COMPONENTS[@]}"; then
                    handle_error "package" "Arch Linux installation failed" "arch_installation"
                    installation_success=false
                fi
            else
                handle_error "critical" "Arch Linux installer not found" "arch_installer"
                pop_error_context
                pop_error_context
                return 1
            fi
            ;;
        "ubuntu")
            log_info "Starting Ubuntu installation..."
            if [[ -f "$DISTROS_DIR/ubuntu/ubuntu-main.sh" ]]; then
                source "$DISTROS_DIR/ubuntu/ubuntu-main.sh"
                if ! ubuntu_main_install "${SELECTED_COMPONENTS[@]}"; then
                    handle_error "package" "Ubuntu installation failed" "ubuntu_installation"
                    installation_success=false
                fi
            else
                handle_error "critical" "Ubuntu installer not found" "ubuntu_installer"
                pop_error_context
                pop_error_context
                return 1
            fi
            ;;
        *)
            handle_error "critical" "Unsupported distribution: $DETECTED_DISTRO" "distro_support"
            pop_error_context
            pop_error_context
            return 1
            ;;
    esac
    
    pop_error_context
    
    # Apply dotfiles configurations with error handling
    push_error_context "dotfiles" "Applying dotfiles configurations"
    
    log_info "Applying dotfiles configurations..."
    if [[ -f "$CONFIGS_DIR/dotfiles-manager.sh" ]]; then
        source "$CONFIGS_DIR/dotfiles-manager.sh"
        if ! manage_dotfiles "${SELECTED_COMPONENTS[@]}"; then
            handle_error "config" "Failed to apply dotfiles configurations" "dotfiles_management"
            installation_success=false
        else
            log_success "Dotfiles configurations applied successfully"
        fi
    else
        handle_error "config" "Dotfiles manager not found" "dotfiles_manager"
        installation_success=false
    fi
    
    pop_error_context
    
    # Post-installation validation with error handling
    push_error_context "validation" "Post-installation validation"
    
    log_info "Running post-installation validation..."
    if [[ -f "$TESTS_DIR/validate.sh" ]]; then
        source "$TESTS_DIR/validate.sh"
        if ! validate_installation "${SELECTED_COMPONENTS[@]}"; then
            handle_error "validation" "Post-installation validation failed" "post_install_validation"
            installation_success=false
        else
            log_success "Post-installation validation passed"
        fi
    else
        log_warn "Validation utilities not found, skipping validation"
    fi
    
    pop_error_context
    
    # Create post-installation checkpoint
    create_checkpoint "post_installation" "System state after installation"
    
    # Final status
    if [[ "$installation_success" == "true" ]]; then
        log_success "Installation process completed successfully! ✓"
        
        # Show installation summary
        show_installation_summary "${SELECTED_COMPONENTS[@]}"
        
        pop_error_context
        return 0
    else
        log_error "Installation process completed with errors"
        
        # Offer recovery options
        offer_recovery_options
        
        pop_error_context
        return 1
    fi
}

# Show installation summary
show_installation_summary() {
    local components=("$@")
    
    log_section "INSTALLATION SUMMARY"
    
    echo "Installed components:"
    for component in "${components[@]}"; do
        echo "  ✓ $component"
    done
    echo
    
    echo "System information:"
    echo "  Distribution: $(get_distro) $(get_distro_version)"
    echo "  Installation mode: ${DRY_RUN:+DRY-RUN }${VM_MODE:+VM }NORMAL"
    echo "  Error recovery: $ERROR_RECOVERY_MODE"
    echo
    
    if [[ ${#FAILED_OPERATIONS[@]} -gt 0 ]]; then
        echo "Issues encountered: ${#FAILED_OPERATIONS[@]}"
        echo "Recovery actions taken: ${#RECOVERY_ACTIONS[@]}"
        echo
    fi
    
    echo "Next steps:"
    echo "  1. Review any error messages above"
    echo "  2. Restart your session to apply shell changes"
    echo "  3. Run 'validate' command to verify installation"
    echo "  4. Check service status with 'systemctl --user status'"
    echo
}

# Offer recovery options after failed installation
offer_recovery_options() {
    log_section "RECOVERY OPTIONS"
    
    echo "The installation encountered errors. What would you like to do?"
    echo
    echo "1. Continue anyway (ignore errors)"
    echo "2. Retry failed operations"
    echo "3. Rollback to previous state"
    echo "4. Generate error report"
    echo "5. Exit"
    echo
    
    local choice
    read -r -p "Enter your choice (1-5): " choice
    
    case "$choice" in
        1)
            log_info "Continuing with errors ignored"
            ;;
        2)
            log_info "Retrying failed operations..."
            retry_failed_operations
            ;;
        3)
            log_info "Rolling back to previous state..."
            if perform_emergency_rollback; then
                log_success "Rollback completed successfully"
            else
                log_error "Rollback failed"
            fi
            ;;
        4)
            log_info "Generating error report..."
            local report_file
            report_file=$(generate_error_report)
            log_info "Error report generated: $report_file"
            ;;
        5)
            log_info "Exiting..."
            cleanup_and_exit 1
            ;;
        *)
            log_warn "Invalid choice, continuing anyway"
            ;;
    esac
}

# Retry failed operations
retry_failed_operations() {
    if [[ ${#FAILED_OPERATIONS[@]} -eq 0 ]]; then
        log_info "No failed operations to retry"
        return 0
    fi
    
    log_info "Retrying ${#FAILED_OPERATIONS[@]} failed operations..."
    
    # This is a simplified retry - in a full implementation,
    # we would re-execute the specific failed operations
    for failed_op in "${FAILED_OPERATIONS[@]}"; do
        local operation="${failed_op#*|*|}"
        operation="${operation%%|*}"
        log_info "Would retry operation: $operation"
    done
    
    log_info "Retry functionality is simplified in this implementation"
}

# Run integration tests
run_integration_tests() {
    push_error_context "integration_tests" "Comprehensive integration testing"
    
    log_info "Starting comprehensive integration tests..."
    
    # Source integration test utilities with error handling
    if [[ -f "$TESTS_DIR/integration-test.sh" ]]; then
        source "$TESTS_DIR/integration-test.sh"
    else
        handle_error "critical" "Integration test utilities not found" "integration_test_utilities"
        pop_error_context
        return 1
    fi
    
    local test_mode="full"
    local test_components=()
    
    # Use selected components if provided
    if [[ ${#SELECTED_COMPONENTS[@]} -gt 0 ]]; then
        test_components=("${SELECTED_COMPONENTS[@]}")
        log_info "Running integration tests for components: ${test_components[*]}"
    else
        log_info "Running full integration test suite"
    fi
    
    # Run integration tests
    if run_integration_tests "$test_mode" "${test_components[@]}"; then
        log_success "Integration tests completed successfully ✓"
        pop_error_context
        return 0
    else
        handle_error "validation" "Integration tests failed" "integration_testing"
        pop_error_context
        return 1
    fi
}

# Run restoration process with error handling
run_restoration() {
    push_error_context "restoration" "System restoration process"
    
    log_info "Starting restoration process..."
    
    # Source restoration utilities with error handling
    if [[ -f "$CONFIGS_DIR/restore.sh" ]]; then
        source "$CONFIGS_DIR/restore.sh"
    else
        handle_error "critical" "Restoration utilities not found" "restore_utilities"
        pop_error_context
        return 1
    fi
    
    local restore_success=true
    
    # Check if specific backup file provided
    if [[ ${#SELECTED_COMPONENTS[@]} -gt 0 ]]; then
        # Treat first component as backup file path
        local backup_file="${SELECTED_COMPONENTS[0]}"
        
        if [[ -f "$backup_file" ]]; then
            log_info "Restoring from specified backup: $backup_file"
            if ! safe_execute_command "restore_from_backup \"$backup_file\"" "Restore from backup"; then
                handle_error "config" "Failed to restore from backup: $backup_file" "backup_restore"
                restore_success=false
            fi
        else
            handle_error "config" "Backup file not found: $backup_file" "backup_file"
            restore_success=false
        fi
    else
        # Interactive restoration
        log_info "Starting interactive restoration..."
        if ! safe_execute_command "interactive_restore" "Interactive restoration"; then
            handle_error "config" "Interactive restoration failed" "interactive_restore"
            restore_success=false
        fi
    fi
    
    if [[ "$restore_success" == "true" ]]; then
        log_success "Restoration process completed successfully ✓"
        pop_error_context
        return 0
    else
        log_error "Restoration process completed with errors"
        pop_error_context
        return 1
    fi
}

# Run validation process with error handling
run_validation() {
    push_error_context "validation" "System validation process"
    
    log_info "Starting validation process..."
    
    # Source validation utilities with error handling
    if [[ -f "$TESTS_DIR/validate.sh" ]]; then
        source "$TESTS_DIR/validate.sh"
    else
        handle_error "critical" "Validation utilities not found" "validation_utilities"
        pop_error_context
        return 1
    fi
    
    # Validate system state
    if validate_installation "${SELECTED_COMPONENTS[@]}"; then
        log_success "System validation completed successfully ✓"
        pop_error_context
        return 0
    else
        handle_error "validation" "System validation failed" "system_validation"
        pop_error_context
        return 1
    fi
}

# Run backup process with error handling
run_backup() {
    push_error_context "backup" "System backup process"
    
    log_info "Starting backup process..."
    
    # Source backup utilities with error handling
    if [[ -f "$CONFIGS_DIR/backup.sh" ]]; then
        source "$CONFIGS_DIR/backup.sh"
    else
        handle_error "critical" "Backup utilities not found" "backup_utilities"
        pop_error_context
        return 1
    fi
    
    local backup_success=true
    
    if [[ ${#SELECTED_COMPONENTS[@]} -gt 0 ]]; then
        # Backup specific components
        log_info "Creating component-specific backups for: ${SELECTED_COMPONENTS[*]}"
        for component in "${SELECTED_COMPONENTS[@]}"; do
            if ! safe_execute_command "create_config_backup \"$component\"" "Backup component: $component"; then
                handle_error "config" "Failed to backup component: $component" "component_backup"
                backup_success=false
            fi
        done
    else
        # Create comprehensive system backup
        log_info "Creating comprehensive system backup..."
        if ! safe_execute_command "create_system_backup" "Create system backup"; then
            handle_error "config" "Failed to create system backup" "system_backup"
            backup_success=false
        fi
    fi
    
    if [[ "$backup_success" == "true" ]]; then
        log_success "Backup process completed successfully ✓"
        pop_error_context
        return 0
    else
        log_error "Backup process completed with errors"
        pop_error_context
        return 1
    fi
}

# Run dry-run mode with error handling
run_dry_run_mode() {
    push_error_context "dry_run" "Dry-run testing mode"
    
    log_info "Starting dry-run mode..."
    
    # Source dry-run utilities with error handling
    if [[ -f "$TESTS_DIR/dry-run.sh" ]]; then
        source "$TESTS_DIR/dry-run.sh"
    else
        handle_error "critical" "Dry-run utilities not found" "dry_run_utilities"
        pop_error_context
        return 1
    fi
    
    local dry_run_success=true
    
    # Run dry-run test
    if [[ ${#SELECTED_COMPONENTS[@]} -gt 0 ]]; then
        # Run dry-run test with pre-selected components
        log_info "Running dry-run test for components: ${SELECTED_COMPONENTS[*]}"
        if ! run_dry_run_test "${SELECTED_COMPONENTS[@]}"; then
            handle_error "validation" "Dry-run test failed for selected components" "dry_run_test"
            dry_run_success=false
        fi
    else
        # Interactive dry-run mode
        log_info "Starting interactive dry-run mode..."
        if ! interactive_dry_run; then
            handle_error "validation" "Interactive dry-run failed" "interactive_dry_run"
            dry_run_success=false
        fi
    fi
    
    if [[ "$dry_run_success" == "true" ]]; then
        log_success "Dry-run mode completed successfully ✓"
        pop_error_context
        return 0
    else
        log_error "Dry-run mode completed with errors"
        pop_error_context
        return 1
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