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
SELECTED_COMPONENTS=()

# Source core utilities with error handling
source_with_error_check() {
    local file="$1"
    [[ -f "$file" ]] || die "Required file not found: $file"
    source "$file"
}

source_with_error_check "$CORE_DIR/common.sh"
source_with_error_check "$CORE_DIR/logger.sh"
source_with_error_check "$CORE_DIR/menu.sh"

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

COMMANDS:
    install             Run interactive installation (default)
    validate            Validate current installation
    list                List available components

EXAMPLES:
    $0                                 # Interactive installation
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
                load_all_components || die "Failed to load all components"
                shift
                ;;

            install|validate|list)
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
    
    log_info "Loading all available components..."
    
    # Parse JSON and get all component names
    local components
    components=$(jq -r '.components | keys[]' "$metadata_file")
    
    # Clear existing selection and add all components
    SELECTED_COMPONENTS=()
    while IFS= read -r component; do
        [[ -z "$component" ]] && continue
        SELECTED_COMPONENTS+=("$component")
    done <<< "$components"
    
    log_success "Loaded ${#SELECTED_COMPONENTS[@]} components for installation"
    log_info "Selected components: ${SELECTED_COMPONENTS[*]}"
}

# Main installation orchestrator with comprehensive error handling
main() {
    local exit_code=0
    
    # Initialize logging first
    init_logger
    
    log_info "Starting Modular Install Framework v1.0"
    
    # Parse command line arguments with error handling
    if ! parse_arguments "$@"; then
        die "Failed to parse command line arguments"
    fi
    
    # Set global flags and export for child processes
    export COMMAND
    
    # System detection and validation with error handling
    log_info "Detecting Linux distribution..."
    if ! detect_distro; then
        die "Failed to detect Linux distribution"
    fi

    DETECTED_DISTRO=$(get_distro)
    if [[ -z "$DETECTED_DISTRO" ]]; then
        die "Distribution detection returned empty result"
    fi
    
    log_success "Detected: ${DETECTED_DISTRO^} ($(get_distro_version))"
    
    # Validate distribution support
    if ! validate_distro_support; then
        die "Distribution not supported or validation failed"
    fi
    
    # Validate system prerequisites
    log_info "Validating system requirements..."
    if ! validate_system; then
        die "System validation failed"
    fi
    
    # Check and setup dotfiles repository
    log_info "Checking dotfiles repository..."
    if [[ -d "$DOTFILES_DIR" ]]; then
        if [[ -d "$DOTFILES_DIR/.git" ]]; then
            log_success "Dotfiles repo found and valid"
            log_info "Fetching latest changes..."
            
            # Change to dotfiles directory and fetch latest changes
            pushd "$DOTFILES_DIR" > /dev/null
            if ! git fetch origin; then
                fail "dotfiles_fetch" "Failed to fetch latest changes from dotfiles repository"
                log_warn "Continuing with existing dotfiles version"
            else
                # Pull latest changes if we're on a branch that tracks origin
                local current_branch
                current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
                if [[ -n "$current_branch" && "$current_branch" != "HEAD" ]]; then
                    if git rev-parse --verify "origin/$current_branch" >/dev/null 2>&1; then
                        if ! git pull origin "$current_branch"; then
                            fail "dotfiles_pull" "Failed to pull latest changes from dotfiles repository"
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
            rm -rf "$DOTFILES_DIR"
            if ! git clone https://github.com/RaviParvadiya/dotfiles.git "$DOTFILES_DIR"; then
                die "Failed to clone dotfiles repository"
            fi
            log_success "Dotfiles repository cloned successfully"
        fi
    else
        log_info "Dotfiles directory not found, cloning repository..."
        if ! git clone https://github.com/RaviParvadiya/dotfiles.git "$DOTFILES_DIR"; then
            die "Failed to clone dotfiles repository"
        fi
        log_success "Dotfiles repository cloned successfully"
    fi
    
    # Execute command with comprehensive error handling
    case "$COMMAND" in
        install)
            if ! run_installation; then
                exit_code=1
            fi
            ;;
        validate)
            if ! run_validation; then
                exit_code=1
            fi
            ;;
        list)
            list_components
            ;;
        *)
            die "Unknown command: $COMMAND"
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
    
    exit $exit_code
}

# Run installation process with comprehensive error handling and recovery
run_installation() {
    log_info "Starting installation process..."
    local installation_success=true
    
    # Component selection with error handling
    if [[ ${#SELECTED_COMPONENTS[@]} -eq 0 ]]; then
        log_info "Opening component selection menu..."
        if ! select_components; then
            die "Component selection failed"
        fi
    else
        log_info "Using pre-selected components: ${SELECTED_COMPONENTS[*]}"
    fi
    
    # Validate component selection
    if [[ ${#SELECTED_COMPONENTS[@]} -eq 0 ]]; then
        die "No components selected for installation"
    fi
    
    # Check shell safety before proceeding
    if ! check_shell_safety "${SELECTED_COMPONENTS[@]}"; then
        return 1
    fi
    
    # Route to distribution-specific handler with error handling
    case "$DETECTED_DISTRO" in
        "arch")
            log_info "Starting Arch Linux installation..."
            if [[ -f "$DISTROS_DIR/arch/arch-main.sh" ]]; then
                source "$DISTROS_DIR/arch/arch-main.sh"
                if ! arch_main_install "${SELECTED_COMPONENTS[@]}"; then
                    fail "arch_installation" "Arch Linux installation failed"
                    installation_success=false
                fi
            else
                die "Arch Linux installer not found"
            fi
            ;;
        "ubuntu")
            log_info "Starting Ubuntu installation..."
            if [[ -f "$DISTROS_DIR/ubuntu/ubuntu-main.sh" ]]; then
                source "$DISTROS_DIR/ubuntu/ubuntu-main.sh"
                if ! ubuntu_main_install "${SELECTED_COMPONENTS[@]}"; then
                    fail "ubuntu_installation" "Ubuntu installation failed"
                    installation_success=false
                fi
            else
                die "Ubuntu installer not found"
            fi
            ;;
        *)
            die "Unsupported distribution: $DETECTED_DISTRO"
            ;;
    esac
    
    # Final status
    if [[ "$installation_success" == "true" ]]; then
        log_success "Installation process completed successfully! ✓"
        
        # Show installation summary
        show_installation_summary "${SELECTED_COMPONENTS[@]}"

        return 0
    else
        log_warn "Installation completed with errors. Check the log for details."

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
        
        if ! ask_yes_no "Do you want to continue?" "y"; then
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
    echo "  Distribution: ${(get_distro)^} ($(get_distro_version))"
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

# Run validation process with error handling
run_validation() {
    log_info "Starting validation process..."
    
    # Source validation utilities with error handling
    if [[ -f "$TESTS_DIR/validate.sh" ]]; then
        source "$TESTS_DIR/validate.sh"
    else
        die "Validation utilities not found"
    fi
    
    # Validate system state
    if validate_installation "${SELECTED_COMPONENTS[@]}"; then
        log_success "System validation completed successfully ✓"
        return 0
    else
        fail "system_validation" "System validation failed"
        return 1
    fi
}

# List available components
list_components() {
    local metadata_file="$DATA_DIR/component-deps.json"
    
    log_info "Available components:"
    echo
    
    # Parse JSON and display components by category
    local categories
    categories=$(jq -r '.categories | keys[]' "$metadata_file" | sort)
    
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
trap 'echo && log_error "Script interrupted"; exit 1' INT TERM

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi