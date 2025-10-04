#!/usr/bin/env bash

# tests/dry-run.sh - Dry-run testing mode for the modular install framework
# This module provides comprehensive dry-run testing capabilities that show
# planned operations without executing them, with detailed operation logging
# and preview capabilities.

# Prevent multiple sourcing
if [[ -n "${DRY_RUN_SOURCED:-}" ]]; then
    return 0
fi
readonly DRY_RUN_SOURCED=1

# Initialize all project paths
source "$(dirname "${BASH_SOURCE[0]}")/../core/init-paths.sh"

# Source required modules (only if not already sourced)
if [[ -z "${COMMON_SOURCED:-}" ]]; then
    source "$CORE_DIR/common.sh"
fi
if [[ -z "${LOGGER_SOURCED:-}" ]]; then
    source "$CORE_DIR/logger.sh"
fi

# Dry-run configuration
DRY_RUN_LOG_FILE=""
DRY_RUN_OPERATIONS=()
DRY_RUN_PACKAGES=()
DRY_RUN_CONFIGS=()
DRY_RUN_SERVICES=()
DRY_RUN_COMMANDS=()

#######################################
# Dry-Run Initialization Functions
#######################################

# Initialize dry-run mode
# Sets up logging and tracking for dry-run operations
init_dry_run() {
    # Set global dry-run flag
    export DRY_RUN=true
    
    # Create dry-run log file
    local timestamp=$(date +%Y%m%d_%H%M%S)
    DRY_RUN_LOG_FILE="/tmp/dry-run-preview-$timestamp.log"
    touch "$DRY_RUN_LOG_FILE"
    
    # Initialize tracking arrays
    DRY_RUN_OPERATIONS=()
    DRY_RUN_PACKAGES=()
    DRY_RUN_CONFIGS=()
    DRY_RUN_SERVICES=()
    DRY_RUN_COMMANDS=()
    
    log_section "DRY-RUN MODE INITIALIZED"
    log_info "All operations will be simulated without making changes"
    log_info "Dry-run log file: $DRY_RUN_LOG_FILE"
    echo
}

# Finalize dry-run mode
# Displays comprehensive summary of planned operations
finalize_dry_run() {
    log_section "DRY-RUN SUMMARY"
    
    echo "Total operations planned: ${#DRY_RUN_OPERATIONS[@]}"
    echo "Packages to install: ${#DRY_RUN_PACKAGES[@]}"
    echo "Configuration files to modify: ${#DRY_RUN_CONFIGS[@]}"
    echo "Services to manage: ${#DRY_RUN_SERVICES[@]}"
    echo "Commands to execute: ${#DRY_RUN_COMMANDS[@]}"
    echo
    
    # Show detailed breakdown
    show_dry_run_packages
    show_dry_run_configs
    show_dry_run_services
    show_dry_run_commands
    show_dry_run_operations
    
    echo
    log_info "Dry-run preview saved to: $DRY_RUN_LOG_FILE"
    log_info "To execute these operations, run without --dry-run flag"
    echo
}

#######################################
# Dry-Run Tracking Functions
#######################################

# Track a dry-run operation
# Arguments: $1 - operation type, $2 - operation description, $3+ - additional details
track_dry_run_operation() {
    local op_type="$1"
    local description="$2"
    shift 2
    local details=("$@")
    
    local operation="[$op_type] $description"
    if [[ ${#details[@]} -gt 0 ]]; then
        operation="$operation (${details[*]})"
    fi
    
    DRY_RUN_OPERATIONS+=("$operation")
    
    # Log to file
    echo "$(date '+%Y-%m-%d %H:%M:%S') $operation" >> "$DRY_RUN_LOG_FILE"
    
    # Display to user
    log_custom "$CYAN" "DRY-RUN" "$operation"
}

# Track package installation
# Arguments: $1 - package name, $2 - package manager, $3 - source (optional)
track_package_install() {
    local package="$1"
    local pm="$2"
    local source="${3:-official}"
    
    local package_info="$package ($pm)"
    if [[ "$source" != "official" ]]; then
        package_info="$package_info [$source]"
    fi
    
    DRY_RUN_PACKAGES+=("$package_info")
    track_dry_run_operation "PACKAGE" "Install $package using $pm" "$source"
}

# Track configuration file modification
# Arguments: $1 - config file path, $2 - operation (create/modify/backup/symlink)
track_config_operation() {
    local config_file="$1"
    local operation="$2"
    local details="${3:-}"
    
    local config_info="$config_file ($operation)"
    if [[ -n "$details" ]]; then
        config_info="$config_info - $details"
    fi
    
    DRY_RUN_CONFIGS+=("$config_info")
    track_dry_run_operation "CONFIG" "$operation $config_file" "$details"
}

# Track service management operation
# Arguments: $1 - service name, $2 - operation (enable/disable/start/stop)
track_service_operation() {
    local service="$1"
    local operation="$2"
    local details="${3:-}"
    
    local service_info="$service ($operation)"
    if [[ -n "$details" ]]; then
        service_info="$service_info - $details"
    fi
    
    DRY_RUN_SERVICES+=("$service_info")
    track_dry_run_operation "SERVICE" "$operation $service" "$details"
}

# Track command execution
# Arguments: $1 - command, $2 - description (optional)
track_command_execution() {
    local command="$1"
    local description="${2:-$command}"
    
    DRY_RUN_COMMANDS+=("$description")
    track_dry_run_operation "COMMAND" "Execute: $description"
}

#######################################
# Dry-Run Display Functions
#######################################

# Show planned package installations
show_dry_run_packages() {
    if [[ ${#DRY_RUN_PACKAGES[@]} -eq 0 ]]; then
        return 0
    fi
    
    echo "=== PACKAGES TO INSTALL ==="
    printf "%-40s %-15s %s\n" "Package" "Manager" "Source"
    printf "%-40s %-15s %s\n" "$(printf '%.40s' "----------------------------------------")" "$(printf '%.15s' "---------------")" "----------"
    
    for package_info in "${DRY_RUN_PACKAGES[@]}"; do
        # Parse package info: "package (manager) [source]" or "package (manager)"
        if [[ "$package_info" =~ ^([^(]+)\s*\(([^)]+)\)\s*(\[([^\]]+)\])?$ ]]; then
            local package="${BASH_REMATCH[1]}"
            local manager="${BASH_REMATCH[2]}"
            local source="${BASH_REMATCH[4]:-official}"
            
            printf "%-40s %-15s %s\n" "$package" "$manager" "$source"
        else
            printf "%-40s %-15s %s\n" "$package_info" "unknown" "unknown"
        fi
    done
    echo
}

# Show planned configuration operations
show_dry_run_configs() {
    if [[ ${#DRY_RUN_CONFIGS[@]} -eq 0 ]]; then
        return 0
    fi
    
    echo "=== CONFIGURATION OPERATIONS ==="
    printf "%-50s %-15s %s\n" "File/Directory" "Operation" "Details"
    printf "%-50s %-15s %s\n" "$(printf '%.50s' "--------------------------------------------------")" "$(printf '%.15s' "---------------")" "----------"
    
    for config_info in "${DRY_RUN_CONFIGS[@]}"; do
        # Parse config info: "path (operation) - details" or "path (operation)"
        if [[ "$config_info" =~ ^([^(]+)\s*\(([^)]+)\)(\s*-\s*(.+))?$ ]]; then
            local path="${BASH_REMATCH[1]}"
            local operation="${BASH_REMATCH[2]}"
            local details="${BASH_REMATCH[4]:-}"
            
            # Truncate long paths
            if [[ ${#path} -gt 50 ]]; then
                path="...${path: -47}"
            fi
            
            printf "%-50s %-15s %s\n" "$path" "$operation" "$details"
        else
            printf "%-50s %-15s %s\n" "$config_info" "unknown" ""
        fi
    done
    echo
}

# Show planned service operations
show_dry_run_services() {
    if [[ ${#DRY_RUN_SERVICES[@]} -eq 0 ]]; then
        return 0
    fi
    
    echo "=== SERVICE OPERATIONS ==="
    printf "%-30s %-15s %s\n" "Service" "Operation" "Details"
    printf "%-30s %-15s %s\n" "$(printf '%.30s' "------------------------------")" "$(printf '%.15s' "---------------")" "----------"
    
    for service_info in "${DRY_RUN_SERVICES[@]}"; do
        # Parse service info: "service (operation) - details" or "service (operation)"
        if [[ "$service_info" =~ ^([^(]+)\s*\(([^)]+)\)(\s*-\s*(.+))?$ ]]; then
            local service="${BASH_REMATCH[1]}"
            local operation="${BASH_REMATCH[2]}"
            local details="${BASH_REMATCH[4]:-}"
            
            printf "%-30s %-15s %s\n" "$service" "$operation" "$details"
        else
            printf "%-30s %-15s %s\n" "$service_info" "unknown" ""
        fi
    done
    echo
}

# Show planned command executions
show_dry_run_commands() {
    if [[ ${#DRY_RUN_COMMANDS[@]} -eq 0 ]]; then
        return 0
    fi
    
    echo "=== COMMANDS TO EXECUTE ==="
    for i in "${!DRY_RUN_COMMANDS[@]}"; do
        printf "%3d. %s\n" $((i + 1)) "${DRY_RUN_COMMANDS[i]}"
    done
    echo
}

# Show all planned operations in chronological order
show_dry_run_operations() {
    if [[ ${#DRY_RUN_OPERATIONS[@]} -eq 0 ]]; then
        return 0
    fi
    
    echo "=== OPERATION TIMELINE ==="
    for i in "${!DRY_RUN_OPERATIONS[@]}"; do
        printf "%3d. %s\n" $((i + 1)) "${DRY_RUN_OPERATIONS[i]}"
    done
    echo
}

#######################################
# Dry-Run Wrapper Functions
#######################################

# Dry-run wrapper for package installation
# Arguments: Same as install_package function
dry_run_install_package() {
    local package="$1"
    local pm="${2:-auto}"
    local source="${3:-official}"
    
    # Detect package manager if auto
    if [[ "$pm" == "auto" ]]; then
        local distro
        distro=$(get_distro)
        case "$distro" in
            "arch") pm="pacman" ;;
            "ubuntu") pm="apt" ;;
            *) pm="unknown" ;;
        esac
    fi
    
    track_package_install "$package" "$pm" "$source"
    return 0
}

# Dry-run wrapper for configuration file operations
# Arguments: $1 - source, $2 - target, $3 - operation type
dry_run_config_operation() {
    local source="$1"
    local target="$2"
    local operation="${3:-symlink}"
    
    local details=""
    if [[ "$operation" == "symlink" ]]; then
        details="$target -> $source"
    elif [[ "$operation" == "copy" ]]; then
        details="$source -> $target"
    elif [[ "$operation" == "backup" ]]; then
        details="backup existing $target"
    fi
    
    track_config_operation "$target" "$operation" "$details"
    return 0
}

# Dry-run wrapper for service operations
# Arguments: $1 - service name, $2 - operation
dry_run_service_operation() {
    local service="$1"
    local operation="$2"
    
    track_service_operation "$service" "$operation"
    return 0
}

# Dry-run wrapper for command execution
# Arguments: $1 - command, $2 - description (optional)
dry_run_execute_command() {
    local command="$1"
    local description="${2:-$command}"
    
    track_command_execution "$command" "$description"
    return 0
}

#######################################
# Integration Functions
#######################################

# Override common functions for dry-run mode
# This function replaces real operations with dry-run tracking
enable_dry_run_overrides() {
    # Override install_package function
    if declare -f install_package >/dev/null; then
        eval "$(declare -f install_package | sed '1s/install_package/original_install_package/')"
        install_package() {
            dry_run_install_package "$@"
        }
    fi
    
    # Override create_symlink function
    if declare -f create_symlink >/dev/null; then
        eval "$(declare -f create_symlink | sed '1s/create_symlink/original_create_symlink/')"
        create_symlink() {
            dry_run_config_operation "$1" "$2" "symlink"
        }
    fi
    
    # Override systemctl commands (if used)
    systemctl() {
        case "$1" in
            enable|disable|start|stop|restart)
                dry_run_service_operation "$2" "$1"
                ;;
            *)
                dry_run_execute_command "systemctl $*" "systemctl $1"
                ;;
        esac
    }
    
    # Override common commands
    sudo() {
        if [[ "$1" == "systemctl" ]]; then
            shift
            systemctl "$@"
        else
            dry_run_execute_command "sudo $*" "sudo command"
        fi
    }
    
    # Override package managers
    pacman() {
        case "$1" in
            -S|--sync)
                shift
                for pkg in "$@"; do
                    [[ "$pkg" =~ ^-- ]] && continue
                    dry_run_install_package "$pkg" "pacman"
                done
                ;;
            *)
                dry_run_execute_command "pacman $*" "pacman command"
                ;;
        esac
    }
    
    apt-get() {
        case "$1" in
            install)
                shift
                for pkg in "$@"; do
                    [[ "$pkg" =~ ^- ]] && continue
                    dry_run_install_package "$pkg" "apt"
                done
                ;;
            *)
                dry_run_execute_command "apt-get $*" "apt-get command"
                ;;
        esac
    }
    
    yay() {
        case "$1" in
            -S|--sync)
                shift
                for pkg in "$@"; do
                    [[ "$pkg" =~ ^-- ]] && continue
                    dry_run_install_package "$pkg" "yay" "AUR"
                done
                ;;
            *)
                dry_run_execute_command "yay $*" "yay command"
                ;;
        esac
    }
    

    

}

# Disable dry-run overrides and restore original functions
disable_dry_run_overrides() {
    # Restore original functions if they exist
    if declare -f original_install_package >/dev/null; then
        eval "$(declare -f original_install_package | sed '1s/original_install_package/install_package/')"
        unset -f original_install_package
    fi
    
    if declare -f original_create_symlink >/dev/null; then
        eval "$(declare -f original_create_symlink | sed '1s/original_create_symlink/create_symlink/')"
        unset -f original_create_symlink
    fi
    
    # Remove command overrides
    unset -f systemctl sudo pacman apt-get yay 2>/dev/null || true
}

#######################################
# Main Dry-Run Functions
#######################################

# Run dry-run test for installation
# Arguments: $@ - components to test
run_dry_run_test() {
    local components=("$@")
    
    log_section "STARTING DRY-RUN TEST"
    
    # Initialize dry-run mode
    init_dry_run
    
    # Enable function overrides
    enable_dry_run_overrides
    
    # Source and run the main installation with dry-run enabled
    if [[ ${#components[@]} -gt 0 ]]; then
        log_info "Testing installation of components: ${components[*]}"
        export SELECTED_COMPONENTS=("${components[@]}")
    else
        log_info "Testing full installation (all components)"
    fi
    
    # Run the installation process in dry-run mode
    # This will call the main installation functions but with overrides
    if [[ -f "$SCRIPT_DIR/install.sh" ]]; then
        # Set dry-run environment
        export DRY_RUN=true
        
        # Source the main installation script functions
        source "$SCRIPT_DIR/install.sh"
        
        # Run installation process
        if [[ ${#components[@]} -gt 0 ]]; then
            SELECTED_COMPONENTS=("${components[@]}")
        fi
        
        # Execute the installation in dry-run mode
        run_installation 2>/dev/null || true
    else
        log_warn "Main installation script not found, running component tests only"
        
        # Test individual components
        for component in "${components[@]}"; do
            test_component_dry_run "$component"
        done
    fi
    
    # Disable overrides
    disable_dry_run_overrides
    
    # Show final summary
    finalize_dry_run
}

# Test individual component in dry-run mode
# Arguments: $1 - component name
test_component_dry_run() {
    local component="$1"
    
    log_info "Testing component: $component"
    
    # Determine component script path
    local component_script=""
    
    # Check different component directories
    for dir in terminal shell editor wm dev-tools; do
        local script_path="$COMPONENTS_DIR/$dir/$component.sh"
        if [[ -f "$script_path" ]]; then
            component_script="$script_path"
            break
        fi
    done
    
    if [[ -z "$component_script" ]]; then
        log_warn "Component script not found for: $component"
        track_dry_run_operation "WARNING" "Component script not found: $component"
        return 1
    fi
    
    # Source and test the component
    if source "$component_script" 2>/dev/null; then
        # Try to call the install function if it exists
        local install_function="install_${component}"
        if declare -f "$install_function" >/dev/null; then
            log_debug "Calling $install_function in dry-run mode"
            "$install_function" true  # Pass dry-run flag
        else
            log_debug "No install function found for $component"
            track_dry_run_operation "INFO" "Component loaded: $component" "no install function"
        fi
    else
        log_warn "Failed to source component script: $component_script"
        track_dry_run_operation "ERROR" "Failed to load component: $component"
        return 1
    fi
    
    return 0
}

# Interactive dry-run mode
# Allows user to select components and preview installation
interactive_dry_run() {
    log_section "INTERACTIVE DRY-RUN MODE"
    
    echo "This mode will show you exactly what would be installed without making any changes."
    echo
    
    # Component selection
    local components=()
    
    if ask_yes_no "Select specific components to test?" "n"; then
        # Use menu system if available
        if declare -f select_components >/dev/null; then
            select_components
            components=("${SELECTED_COMPONENTS[@]}")
        else
            # Manual component selection
            echo "Available component categories:"
            echo "1. terminal (alacritty, kitty, tmux)"
            echo "2. shell (zsh, starship)"
            echo "3. editor (neovim, vscode)"
            echo "4. wm (hyprland, waybar, wofi, swaync)"
            echo "5. dev-tools (git, docker, languages)"
            echo "6. all (test everything)"
            echo
            
            local choice
            choice=$(ask_choice "Select category to test:" "terminal" "shell" "editor" "wm" "dev-tools" "all")
            
            case "$choice" in
                "terminal") components=("alacritty" "kitty" "tmux") ;;
                "shell") components=("zsh" "starship") ;;
                "editor") components=("neovim" "vscode") ;;
                "wm") components=("hyprland" "waybar" "wofi" "swaync") ;;
                "dev-tools") components=("git" "docker" "languages") ;;
                "all") components=() ;;
            esac
        fi
    fi
    
    # Run the dry-run test
    run_dry_run_test "${components[@]}"
    
    # Ask if user wants to proceed with actual installation
    echo
    if ask_yes_no "Would you like to proceed with the actual installation?" "n"; then
        log_info "Proceeding with actual installation..."
        
        # Disable dry-run mode
        export DRY_RUN=false
        
        # Run actual installation
        if [[ ${#components[@]} -gt 0 ]]; then
            export SELECTED_COMPONENTS=("${components[@]}")
        fi
        
        # Call main installation
        source "$SCRIPT_DIR/install.sh"
        run_installation
    else
        log_info "Dry-run completed. No changes were made to your system."
    fi
}

#######################################
# Command Line Interface
#######################################

# Main function for dry-run script
main_dry_run() {
    local mode="${1:-interactive}"
    shift
    local components=("$@")
    
    case "$mode" in
        "test"|"run")
            run_dry_run_test "${components[@]}"
            ;;
        "interactive"|"menu")
            interactive_dry_run
            ;;
        "component")
            if [[ ${#components[@]} -eq 0 ]]; then
                log_error "Component name required for component test mode"
                exit 1
            fi
            
            init_dry_run
            enable_dry_run_overrides
            
            for component in "${components[@]}"; do
                test_component_dry_run "$component"
            done
            
            disable_dry_run_overrides
            finalize_dry_run
            ;;
        *)
            echo "Usage: $0 [mode] [components...]"
            echo
            echo "Modes:"
            echo "  interactive  - Interactive component selection and preview (default)"
            echo "  test         - Test specified components or full installation"
            echo "  component    - Test individual components only"
            echo
            echo "Examples:"
            echo "  $0                           # Interactive mode"
            echo "  $0 test                      # Test full installation"
            echo "  $0 test terminal shell       # Test specific components"
            echo "  $0 component hyprland        # Test hyprland component only"
            exit 1
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_dry_run "$@"
fi