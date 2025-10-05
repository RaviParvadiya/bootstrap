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
#   --components LIST  Install specific components (comma-separated)
#   --help             Show help message
# 
# Examples:
#   ./install.sh                           # Interactive installation
#   ./install.sh --components terminal,shell  # Install specific components
#   ./install.sh --all                    # Install all available components

# 
# Requirements:
#   - Linux system (Arch Linux or Ubuntu 18.04+)
#   - Internet connection
#   - Sudo access (do not run as root)
#   - Basic tools: curl, git, tar, unzip
#######################################

set -euo pipefail
IFS=$'\n\t'

# Initialize project paths (centralized path resolution)
source "$(dirname "${BASH_SOURCE[0]}")/core/init-paths.sh"

# Global variables
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
source_with_error_check "$CORE_DIR/recovery-system.sh"

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
    -c, --components    Comma-separated list of components to install
    -a, --all           Install all available components
    -m, --minimal       Use minimal package lists (default for post-installation)
    -f, --full          Use full package lists (for fresh installations)

COMMANDS:
    install             Run interactive installation (default)
    restore             Restore from backup
    validate            Validate current installation
    backup              Create system backup
    list                List available components

EXAMPLES:
    $0                                 # Interactive installation
    $0 --dry-run install               # Preview installation
    $0 --components terminal,shell     # Install specific components
    $0 --all                           # Install all available components
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
            -c|--components)
                IFS=',' read -ra SELECTED_COMPONENTS <<< "$2"
                shift 2
                ;;
            -a|--all)
                # Load all available components
                if ! load_all_components; then
                    log_error "Failed to load all components"
                    exit 1
                fi
                shift
                ;;
            -m|--minimal)
                USE_MINIMAL_PACKAGES=true
                shift
                ;;
            -f|--full)
                USE_MINIMAL_PACKAGES=false
                shift
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

# Load all available components from metadata
load_all_components() {
    local metadata_file="$DATA_DIR/component-deps.json"
    
    if [[ ! -f "$metadata_file" ]]; then
        log_error "Component metadata file not found: $metadata_file"
        return 1
    fi
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        log_error "jq is required for parsing component metadata"
        log_info "Please install jq: sudo pacman -S jq (Arch) or sudo apt install jq (Ubuntu)"
        return 1
    fi
    
    log_info "Loading all available components..."
    
    # Parse JSON and get all component names
    local components
    components=$(jq -r '.components | keys[]' "$metadata_file" 2>/dev/null)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to parse component metadata JSON"
        return 1
    fi
    
    # Clear existing selection and add all components
    SELECTED_COMPONENTS=()
    while IFS= read -r component; do
        [[ -z "$component" ]] && continue
        SELECTED_COMPONENTS+=("$component")
    done <<< "$components"
    
    log_success "Loaded ${#SELECTED_COMPONENTS[@]} components for installation"
    log_info "Selected components: ${SELECTED_COMPONENTS[*]}"
    
    return 0
}

# Main installation orchestrator with comprehensive error handling
main() {
    local exit_code=0
    
    # Initialize logging first
    init_logger
    
    log_info "Starting Modular Install Framework v1.0"
    
    # Parse command line arguments with error handling
    if ! parse_arguments "$@"; then
        handle_error "critical" "Failed to parse command line arguments" "argument_parsing"
        cleanup_and_exit 1
    fi
    
    # Set global flags and export for child processes
    export COMMAND
    
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
        *)
            handle_error "critical" "Unknown command: $COMMAND" "command_execution"
            exit_code=1
            ;;
    esac
    
    # Show error summary if there were any issues
    if [[ ${#FAILED_OPERATIONS[@]} -gt 0 ]]; then
        show_failures
        log_warn "Installation completed with ${#FAILED_OPERATIONS[@]} issues"
        exit_code=1
    fi
    
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
    
    # Component selection with error handling
    if [[ ${#SELECTED_COMPONENTS[@]} -eq 0 ]]; then
        log_info "Opening component selection menu..."
        if ! select_components; then
            handle_error "critical" "Component selection failed" "component_selection"
            return 1
        fi
    else
        log_info "Using pre-selected components: ${SELECTED_COMPONENTS[*]}"
    fi
    
    # Validate component selection
    if [[ ${#SELECTED_COMPONENTS[@]} -eq 0 ]]; then
        handle_error "critical" "No components selected for installation" "component_selection"
        return 1
    fi
    
    # Check shell safety before proceeding
    if ! check_shell_safety "${SELECTED_COMPONENTS[@]}"; then
        return 1
    fi
    
    # Create pre-installation backup with error handling
    if ask_yes_no "Create backup before installation?" "y"; then
        log_info "Creating pre-installation backup..."
        push_error_context "backup" "Creating pre-installation backup"
        
        if [[ -f "$CONFIGS_DIR/backup.sh" ]]; then
            source "$CONFIGS_DIR/backup.sh"
            if ! exec_safe "create_system_backup" "Create system backup"; then
                handle_error "config" "Failed to create pre-installation backup" "backup_creation"
                if ask_yes_no "Continue installation without backup?" "n"; then
                    log_warn "Continuing installation without backup"
                else
                    return 1
                fi
            else
                log_success "Pre-installation backup created successfully"
                
                # Additional shell backup if zsh is being installed
                for component in "${SELECTED_COMPONENTS[@]}"; do
                    if [[ "$component" == "shell" || "$component" == "zsh" ]]; then
                        log_info "Shell component detected - ensuring shell information is backed up"
                        break
                    fi
                done
            fi
        else
            handle_error "config" "Backup utilities not found" "backup_utilities"
        fi
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
                return 1
            fi
            ;;
        *)
            handle_error "critical" "Unsupported distribution: $DETECTED_DISTRO" "distro_support"
            return 1
            ;;
    esac
    
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
    
    # Final status
    if [[ "$installation_success" == "true" ]]; then
        log_success "Installation process completed successfully! ✓"
        
        # Show installation summary
        show_installation_summary "${SELECTED_COMPONENTS[@]}"

        return 0
    else
        log_error "Installation process completed with errors"
        
        # Offer recovery options
        offer_recovery_options

        return 1
    fi
}

# Check and warn about shell safety before operations
# Arguments: $@ - list of components being processed
check_shell_safety() {
    local components=("$@")
    local shell_component_found=false
    
    # Check if shell/zsh component is involved
    for component in "${components[@]}"; do
        if [[ "$component" == "shell" || "$component" == "zsh" ]]; then
            shell_component_found=true
            break
        fi
    done
    
    if [[ "$shell_component_found" == "true" && "$SHELL" == *"zsh"* ]]; then
        log_warn "Shell component operation detected while zsh is your default shell"
        log_warn "This operation may affect your shell configuration"
        
        if ! ask_yes_no "Do you want to continue? (Backup recommended)" "y"; then
            log_info "Operation cancelled by user for shell safety"
            return 1
        fi
    fi
    
    return 0
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
    echo "  Current shell: $SHELL"
    echo
    
    if [[ ${#FAILED_OPERATIONS[@]} -gt 0 ]]; then
        echo "Issues encountered: ${#FAILED_OPERATIONS[@]}"
        echo
    fi
    
    echo "Next steps:"
    echo "  1. Review any error messages above"
    echo "  2. Restart your session to apply shell changes"
    echo "  3. Run 'validate' command to verify installation"
    echo "  4. Check service status with 'systemctl --user status'"
    
    # Shell-specific warnings
    local shell_component_installed=false
    for component in "${components[@]}"; do
        if [[ "$component" == "shell" || "$component" == "zsh" ]]; then
            shell_component_installed=true
            break
        fi
    done
    
    if [[ "$shell_component_installed" == "true" ]]; then
        echo "  5. IMPORTANT: Log out and back in to activate new shell settings"
    fi
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
            exit 1
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

# Run restoration process with error handling
run_restoration() {
    push_error_context "restoration" "System restoration process"
    
    log_info "Starting restoration process..."
    
    # Source restoration utilities with error handling
    if [[ -f "$CONFIGS_DIR/restore.sh" ]]; then
        source "$CONFIGS_DIR/restore.sh"
    else
        handle_error "critical" "Restoration utilities not found" "restore_utilities"
        return 1
    fi
    
    local restore_success=true
    
    # Check if specific backup file provided
    if [[ ${#SELECTED_COMPONENTS[@]} -gt 0 ]]; then
        # Treat first component as backup file path
        local backup_file="${SELECTED_COMPONENTS[0]}"
        
        if [[ -f "$backup_file" ]]; then
            log_info "Restoring from specified backup: $backup_file"
            if ! exec_safe "restore_from_backup \"$backup_file\"" "Restore from backup"; then
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
        if ! exec_safe "interactive_restore" "Interactive restoration"; then
            handle_error "config" "Interactive restoration failed" "interactive_restore"
            restore_success=false
        fi
    fi
    
    if [[ "$restore_success" == "true" ]]; then
        log_success "Restoration process completed successfully ✓"
        return 0
    else
        log_error "Restoration process completed with errors"
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
        return 1
    fi
    
    # Validate system state
    if validate_installation "${SELECTED_COMPONENTS[@]}"; then
        log_success "System validation completed successfully ✓"
        return 0
    else
        handle_error "validation" "System validation failed" "system_validation"
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
        return 1
    fi
    
    local backup_success=true
    
    if [[ ${#SELECTED_COMPONENTS[@]} -gt 0 ]]; then
        # Backup specific components
        log_info "Creating component-specific backups for: ${SELECTED_COMPONENTS[*]}"
        for component in "${SELECTED_COMPONENTS[@]}"; do
            if ! exec_safe "create_config_backup \"$component\"" "Backup component: $component"; then
                handle_error "config" "Failed to backup component: $component" "component_backup"
                backup_success=false
            fi
        done
    else
        # Create comprehensive system backup
        log_info "Creating comprehensive system backup..."
        if ! exec_safe "create_system_backup" "Create system backup"; then
            handle_error "config" "Failed to create system backup" "system_backup"
            backup_success=false
        fi
    fi
    
    if [[ "$backup_success" == "true" ]]; then
        log_success "Backup process completed successfully ✓"
        return 0
    else
        log_error "Backup process completed with errors"
        return 1
    fi
}

# List available components
list_components() {
    local metadata_file="$DATA_DIR/component-deps.json"
    
    if [[ ! -f "$metadata_file" ]]; then
        log_error "Component metadata file not found: $metadata_file"
        return 1
    fi
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        log_error "jq is required for parsing component metadata"
        log_info "Please install jq: sudo pacman -S jq (Arch) or sudo apt install jq (Ubuntu)"
        return 1
    fi
    
    log_info "Available components:"
    echo
    
    # Parse JSON and display components by category
    local categories
    categories=$(jq -r '.categories | keys[]' "$metadata_file" 2>/dev/null | sort)
    
    while IFS= read -r category; do
        [[ -z "$category" ]] && continue
        
        local category_name
        category_name=$(jq -r ".categories.\"$category\".name" "$metadata_file")
        local category_desc
        category_desc=$(jq -r ".categories.\"$category\".description" "$metadata_file")
        
        echo "=== $category_name ==="
        
        # Find components in this category
        local components
        components=$(jq -r ".components | to_entries[] | select(.value.category == \"$category\") | .key" "$metadata_file" | sort)
        
        while IFS= read -r component; do
            [[ -z "$component" ]] && continue
            
            local description
            description=$(jq -r ".components.\"$component\".description" "$metadata_file")
            echo "  - $component : $description"
        done <<< "$components"
        
        echo
    done <<< "$categories"
    
    echo "=== Installation Options ==="
    echo "  --components <list>    : Install specific components (comma-separated)"
    echo "  --all                  : Install ALL available components"
    echo "  (no options)           : Interactive component selection"
    echo
    
    echo "Usage examples:"
    echo "  $0 --components terminal,shell   # Install specific components"
    echo "  $0 --all                         # Install everything"
    echo "  $0 list                          # Show this component list"
}

# Error handling
trap 'echo "ERROR: Script interrupted" >&2; exit 1' INT TERM

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi