#!/usr/bin/env bash

# configs/restore.sh - Configuration restoration and rollback utilities
# This module provides configuration restoration and rollback capabilities from backup sessions
# Requirements: 6.2, 10.2

# Prevent multiple sourcing
if [[ -n "${RESTORE_UTILS_SOURCED:-}" ]]; then
    return 0
fi
readonly RESTORE_UTILS_SOURCED=1

# Initialize all project paths
source "$(dirname "${BASH_SOURCE[0]}")/../core/init-paths.sh"

# Source core utilities
source "$CORE_DIR/common.sh"
source "$CORE_DIR/logger.sh"

# Source backup utilities for session management
source "$CONFIGS_DIR/backup.sh"

# Global configuration
RESTORE_TEMP_DIR="/tmp/install_restore_$$"
RESTORE_LOG_FILE="$HOME/.config/install-restore.log"

#######################################
# Restore Session Management
#######################################

# Initialize restore environment
# Returns: 0 if successful, 1 if failed
init_restore_environment() {
    # Create temporary directory for restore operations
    if [[ "$DRY_RUN" != "true" ]]; then
        if ! mkdir -p "$RESTORE_TEMP_DIR"; then
            log_error "Failed to create restore temporary directory: $RESTORE_TEMP_DIR"
            return 1
        fi
        
        # Set up cleanup trap
        trap 'cleanup_restore_environment' EXIT
    fi
    
    log_debug "Restore environment initialized"
    return 0
}

# Clean up restore environment
cleanup_restore_environment() {
    if [[ -d "$RESTORE_TEMP_DIR" ]]; then
        rm -rf "$RESTORE_TEMP_DIR"
        log_debug "Cleaned up restore temporary directory"
    fi
}

# Validate backup session for restore
# Arguments: $1 - backup session directory
# Returns: 0 if valid, 1 if invalid
# Requirements: 10.2 - Validate prerequisites before proceeding
validate_restore_session() {
    local session_dir="$1"
    
    if [[ -z "$session_dir" ]]; then
        log_error "Backup session directory is required"
        return 1
    fi
    
    if [[ ! -d "$session_dir" ]]; then
        log_error "Backup session directory does not exist: $session_dir"
        return 1
    fi
    
    # Use backup validation function
    if ! validate_backup_session "$session_dir"; then
        log_error "Backup session validation failed"
        return 1
    fi
    
    log_debug "Backup session validated for restore: $session_dir"
    return 0
}

#######################################
# File and Directory Restore Functions
#######################################

# Restore a single file or directory from backup
# Arguments: $1 - backup path, $2 - target path, $3 - restore mode (replace|merge|skip)
# Returns: 0 if successful, 1 if failed
restore_path() {
    local backup_path="$1"
    local target_path="$2"
    local restore_mode="${3:-replace}"
    
    if [[ -z "$backup_path" || -z "$target_path" ]]; then
        log_error "Backup path and target path are required"
        return 1
    fi
    
    if [[ ! -e "$backup_path" ]]; then
        log_error "Backup path does not exist: $backup_path"
        return 1
    fi
    
    log_debug "Restoring: $backup_path -> $target_path (mode: $restore_mode)"
    
    # Handle existing target based on restore mode
    if [[ -e "$target_path" ]]; then
        case "$restore_mode" in
            "replace")
                log_info "Replacing existing file: $target_path"
                if [[ "$DRY_RUN" == "true" ]]; then
                    log_info "[DRY RUN] Would remove existing: $target_path"
                else
                    if ! rm -rf "$target_path"; then
                        log_error "Failed to remove existing file: $target_path"
                        return 1
                    fi
                fi
                ;;
            "skip")
                log_info "Skipping existing file: $target_path"
                return 0
                ;;
            "merge")
                if [[ -d "$backup_path" && -d "$target_path" ]]; then
                    log_info "Merging directory contents: $target_path"
                    # Directory merge will be handled by cp -r
                else
                    log_warn "Cannot merge non-directory files, replacing: $target_path"
                    if [[ "$DRY_RUN" != "true" ]]; then
                        rm -rf "$target_path"
                    fi
                fi
                ;;
            *)
                log_error "Unknown restore mode: $restore_mode"
                return 1
                ;;
        esac
    fi
    
    # Create target directory if needed
    local target_dir
    target_dir=$(dirname "$target_path")
    if [[ ! -d "$target_dir" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_debug "[DRY RUN] Would create directory: $target_dir"
        else
            if ! mkdir -p "$target_dir"; then
                log_error "Failed to create target directory: $target_dir"
                return 1
            fi
            log_debug "Created target directory: $target_dir"
        fi
    fi
    
    # Perform restore based on backup type
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would restore: $backup_path -> $target_path"
        return 0
    fi
    
    if [[ -d "$backup_path" ]]; then
        # Restore directory
        if [[ "$restore_mode" == "merge" && -d "$target_path" ]]; then
            # Merge directory contents
            if ! cp -rp "$backup_path"/* "$target_path"/; then
                log_error "Failed to merge directory: $backup_path -> $target_path"
                return 1
            fi
        else
            # Replace directory
            if ! cp -rp "$backup_path" "$target_path"; then
                log_error "Failed to restore directory: $backup_path -> $target_path"
                return 1
            fi
        fi
        log_success "Restored directory: $target_path"
    elif [[ -L "$backup_path" ]]; then
        # Restore symlink
        local link_target
        link_target=$(readlink "$backup_path")
        if ! ln -s "$link_target" "$target_path"; then
            log_error "Failed to restore symlink: $backup_path -> $target_path"
            return 1
        fi
        log_success "Restored symlink: $target_path -> $link_target"
    else
        # Restore regular file
        if ! cp -p "$backup_path" "$target_path"; then
            log_error "Failed to restore file: $backup_path -> $target_path"
            return 1
        fi
        log_success "Restored file: $target_path"
    fi
    
    return 0
}

# Restore multiple paths from backup session
# Arguments: $1 - backup session directory, $2 - restore mode, $@ - list of relative paths
# Returns: 0 if all successful, 1 if any failed
restore_multiple_paths() {
    local session_dir="$1"
    local restore_mode="$2"
    shift 2
    local relative_paths=("$@")
    
    if [[ -z "$session_dir" ]]; then
        log_error "Backup session directory is required"
        return 1
    fi
    
    if [[ ${#relative_paths[@]} -eq 0 ]]; then
        log_error "No paths specified for restore"
        return 1
    fi
    
    local success_count=0
    local failed_count=0
    local failed_paths=()
    
    log_info "Restoring ${#relative_paths[@]} paths from session: $(basename "$session_dir")"
    
    for rel_path in "${relative_paths[@]}"; do
        local backup_path="$session_dir/$rel_path"
        local target_path
        
        # Determine target path based on backup structure
        if [[ "$rel_path" == home/* ]]; then
            # Home directory files
            target_path="$HOME/${rel_path#home/}"
        elif [[ "$rel_path" == system/* ]]; then
            # System files
            target_path="/${rel_path#system/}"
        elif [[ "$rel_path" == root/* ]]; then
            # Root filesystem files
            target_path="/${rel_path#root/}"
        else
            # Default to home directory
            target_path="$HOME/$rel_path"
        fi
        
        if restore_path "$backup_path" "$target_path" "$restore_mode"; then
            ((success_count++))
        else
            ((failed_count++))
            failed_paths+=("$rel_path")
        fi
    done
    
    # Report results
    if [[ $success_count -gt 0 ]]; then
        log_success "Successfully restored $success_count paths"
    fi
    
    if [[ $failed_count -gt 0 ]]; then
        log_error "Failed to restore $failed_count paths:"
        for failed_path in "${failed_paths[@]}"; do
            log_error "  - $failed_path"
        done
        return 1
    fi
    
    return 0
}

#######################################
# Component-Specific Restore Functions
#######################################

# Restore configurations for a specific component
# Arguments: $1 - component name, $2 - backup session directory, $3 - restore mode
# Returns: 0 if successful, 1 if failed
restore_component_configs() {
    local component="$1"
    local session_dir="$2"
    local restore_mode="${3:-replace}"
    
    if [[ -z "$component" || -z "$session_dir" ]]; then
        log_error "Component name and session directory are required"
        return 1
    fi
    
    local component_backup_dir="$session_dir/components/$component"
    
    if [[ ! -d "$component_backup_dir" ]]; then
        log_warn "No backup found for component: $component"
        return 1
    fi
    
    log_info "Restoring configurations for component: $component"
    
    # Source dotfiles manager to get component configuration structure
    if [[ -f "$CONFIGS_DIR/dotfiles-manager.sh" ]]; then
        source "$CONFIGS_DIR/dotfiles-manager.sh"
    else
        log_error "Dotfiles manager not found, cannot determine restore targets"
        return 1
    fi
    
    # Get component configuration mappings
    local config_mappings=()
    while IFS='|' read -r source_file target_path; do
        config_mappings+=("$target_path")
    done < <(get_component_config_structure "$component" 2>/dev/null)
    
    if [[ ${#config_mappings[@]} -eq 0 ]]; then
        log_warn "No configuration mappings found for component: $component"
        return 1
    fi
    
    # Restore each configuration file
    local success_count=0
    local failed_count=0
    
    for target_path in "${config_mappings[@]}"; do
        local config_name
        config_name=$(basename "$target_path")
        local backup_path="$component_backup_dir/$config_name"
        
        if [[ -e "$backup_path" ]]; then
            if restore_path "$backup_path" "$target_path" "$restore_mode"; then
                ((success_count++))
            else
                ((failed_count++))
            fi
        else
            log_debug "No backup found for configuration: $config_name"
        fi
    done
    
    if [[ $success_count -gt 0 ]]; then
        log_success "Restored $success_count configurations for component: $component"
    fi
    
    if [[ $failed_count -gt 0 ]]; then
        log_warn "Failed to restore $failed_count configurations for component: $component"
        return 1
    fi
    
    return 0
}

# Restore configurations for multiple components
# Arguments: $1 - backup session directory, $2 - restore mode, $@ - list of component names
# Returns: 0 if all successful, 1 if any failed
restore_multiple_components() {
    local session_dir="$1"
    local restore_mode="$2"
    shift 2
    local components=("$@")
    
    if [[ -z "$session_dir" ]]; then
        log_error "Backup session directory is required"
        return 1
    fi
    
    if [[ ${#components[@]} -eq 0 ]]; then
        log_error "No components specified for restore"
        return 1
    fi
    
    local success_count=0
    local failed_count=0
    local failed_components=()
    
    log_section "Restoring Component Configurations"
    log_info "Components to restore: ${components[*]}"
    log_info "Restore mode: $restore_mode"
    
    for component in "${components[@]}"; do
        if restore_component_configs "$component" "$session_dir" "$restore_mode"; then
            ((success_count++))
        else
            ((failed_count++))
            failed_components+=("$component")
        fi
    done
    
    # Report final results
    if [[ $success_count -gt 0 ]]; then
        log_success "Successfully restored $success_count components"
    fi
    
    if [[ $failed_count -gt 0 ]]; then
        log_error "Failed to restore components: ${failed_components[*]}"
        return 1
    fi
    
    return 0
}

#######################################
# System Restore Functions
#######################################

# Restore system configuration files from backup
# Arguments: $1 - backup session directory, $2 - restore mode
# Returns: 0 if successful, 1 if failed
restore_system_configs() {
    local session_dir="$1"
    local restore_mode="${2:-replace}"
    
    if [[ -z "$session_dir" ]]; then
        log_error "Backup session directory is required"
        return 1
    fi
    
    log_info "Restoring system configuration files"
    
    # Find all system configuration files in backup
    local system_backup_dir="$session_dir/system"
    local home_backup_dir="$session_dir/home"
    
    local restored_count=0
    local failed_count=0
    
    # Restore system files (requires root privileges)
    if [[ -d "$system_backup_dir" ]]; then
        log_info "Restoring system configuration files (may require sudo)"
        
        while IFS= read -r -d '' backup_file; do
            local relative_path="${backup_file#$system_backup_dir/}"
            local target_path="/$relative_path"
            
            # Check if we need sudo for this file
            local target_dir
            target_dir=$(dirname "$target_path")
            
            if [[ ! -w "$target_dir" ]] && [[ "$DRY_RUN" != "true" ]]; then
                log_warn "Insufficient permissions to restore system file: $target_path"
                log_info "You may need to run this with sudo or restore manually"
                ((failed_count++))
                continue
            fi
            
            if restore_path "$backup_file" "$target_path" "$restore_mode"; then
                ((restored_count++))
            else
                ((failed_count++))
            fi
        done < <(find "$system_backup_dir" -type f -print0 2>/dev/null)
    fi
    
    # Restore home directory system files
    if [[ -d "$home_backup_dir" ]]; then
        while IFS= read -r -d '' backup_file; do
            local relative_path="${backup_file#$home_backup_dir/}"
            local target_path="$HOME/$relative_path"
            
            # Only restore system-related files in home directory
            case "$relative_path" in
                .bashrc|.bash_profile|.profile|.xinitrc|.xprofile|.pam_environment)
                    if restore_path "$backup_file" "$target_path" "$restore_mode"; then
                        ((restored_count++))
                    else
                        ((failed_count++))
                    fi
                    ;;
            esac
        done < <(find "$home_backup_dir" -type f -print0 2>/dev/null)
    fi
    
    if [[ $restored_count -gt 0 ]]; then
        log_success "Restored $restored_count system configuration files"
    fi
    
    if [[ $failed_count -gt 0 ]]; then
        log_warn "Failed to restore $failed_count system configuration files"
        return 1
    fi
    
    return 0
}

#######################################
# Full Session Restore Functions
#######################################

# Restore entire backup session
# Arguments: $1 - backup session directory, $2 - restore mode, $3 - filter (optional)
# Returns: 0 if successful, 1 if failed
# Requirements: 10.2 - Provide recovery instructions on critical errors
restore_full_session() {
    local session_dir="$1"
    local restore_mode="${2:-replace}"
    local filter="$3"
    
    if [[ -z "$session_dir" ]]; then
        log_error "Backup session directory is required"
        return 1
    fi
    
    if ! validate_restore_session "$session_dir"; then
        return 1
    fi
    
    log_section "Restoring Full Backup Session"
    log_info "Session: $(basename "$session_dir")"
    log_info "Restore mode: $restore_mode"
    
    if [[ -n "$filter" ]]; then
        log_info "Filter: $filter"
    fi
    
    # Initialize restore environment
    if ! init_restore_environment; then
        return 1
    fi
    
    local total_restored=0
    local total_failed=0
    
    # Restore system configurations
    if [[ -z "$filter" || "$filter" == "system" ]]; then
        log_info "Restoring system configurations..."
        if restore_system_configs "$session_dir" "$restore_mode"; then
            ((total_restored++))
        else
            ((total_failed++))
        fi
    fi
    
    # Restore component configurations
    if [[ -z "$filter" || "$filter" == "components" ]]; then
        local components_dir="$session_dir/components"
        if [[ -d "$components_dir" ]]; then
            log_info "Restoring component configurations..."
            
            # Find all components in backup
            local components=()
            while IFS= read -r -d '' component_dir; do
                local component_name
                component_name=$(basename "$component_dir")
                components+=("$component_name")
            done < <(find "$components_dir" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
            
            if [[ ${#components[@]} -gt 0 ]]; then
                if restore_multiple_components "$session_dir" "$restore_mode" "${components[@]}"; then
                    ((total_restored++))
                else
                    ((total_failed++))
                fi
            fi
        fi
    fi
    
    # Restore home directory files (excluding components)
    if [[ -z "$filter" || "$filter" == "home" ]]; then
        local home_backup_dir="$session_dir/home"
        if [[ -d "$home_backup_dir" ]]; then
            log_info "Restoring home directory files..."
            
            # Find all files not already handled by components
            local home_files=()
            while IFS= read -r -d '' backup_file; do
                local relative_path="${backup_file#$home_backup_dir/}"
                
                # Skip files that are handled by component restore
                if [[ "$relative_path" == .config/* ]]; then
                    # Check if this is a component config
                    local is_component_config=false
                    if [[ -d "$session_dir/components" ]]; then
                        while IFS= read -r -d '' component_dir; do
                            local component_name
                            component_name=$(basename "$component_dir")
                            if [[ "$relative_path" == .config/"$component_name"/* ]]; then
                                is_component_config=true
                                break
                            fi
                        done < <(find "$session_dir/components" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
                    fi
                    
                    if [[ "$is_component_config" == "true" ]]; then
                        continue
                    fi
                fi
                
                home_files+=("home/$relative_path")
            done < <(find "$home_backup_dir" -type f -print0 2>/dev/null)
            
            if [[ ${#home_files[@]} -gt 0 ]]; then
                if restore_multiple_paths "$session_dir" "$restore_mode" "${home_files[@]}"; then
                    ((total_restored++))
                else
                    ((total_failed++))
                fi
            fi
        fi
    fi
    
    # Report final results
    if [[ $total_restored -gt 0 ]]; then
        log_success "Successfully restored backup session"
    fi
    
    if [[ $total_failed -gt 0 ]]; then
        log_error "Some restore operations failed"
        log_error "Check the logs above for details"
        log_error "You may need to manually restore some files or run with sudo for system files"
        return 1
    fi
    
    return 0
}

#######################################
# Interactive Restore Functions
#######################################

# Interactive restore with user prompts
# Arguments: $1 - backup session directory
# Returns: 0 if successful, 1 if failed or cancelled
interactive_restore() {
    local session_dir="$1"
    
    if [[ -z "$session_dir" ]]; then
        # Let user select from available sessions
        log_section "Available Backup Sessions"
        list_backup_sessions
        
        echo
        read -p "Enter backup session directory path: " session_dir
        
        if [[ -z "$session_dir" ]]; then
            log_info "Restore cancelled by user"
            return 1
        fi
    fi
    
    if ! validate_restore_session "$session_dir"; then
        return 1
    fi
    
    # Show session information
    log_section "Backup Session Information"
    log_info "Session: $(basename "$session_dir")"
    
    local metadata_file="$session_dir/$BACKUP_METADATA_FILE"
    if [[ -f "$metadata_file" ]]; then
        while IFS='=' read -r key value; do
            case "$key" in
                "CREATED_AT") log_info "Created: $value" ;;
                "CREATED_BY") log_info "Created by: $value" ;;
                "CREATED_ON") log_info "Created on: $value" ;;
            esac
        done < "$metadata_file"
    fi
    
    # Count files
    local file_count
    file_count=$(find "$session_dir" -type f ! -name "$BACKUP_METADATA_FILE" | wc -l)
    log_info "Files in backup: $file_count"
    
    echo
    
    # Ask for restore mode
    echo "Select restore mode:"
    echo "1. Replace existing files (recommended for full restore)"
    echo "2. Skip existing files (safe mode)"
    echo "3. Merge directories where possible"
    echo
    
    local restore_mode
    local choice
    choice=$(ask_choice "Select restore mode" \
        "Replace existing" \
        "Skip existing" \
        "Merge directories")
    
    case "$choice" in
        "Replace existing") restore_mode="replace" ;;
        "Skip existing") restore_mode="skip" ;;
        "Merge directories") restore_mode="merge" ;;
        *) 
            log_info "Restore cancelled by user"
            return 1
            ;;
    esac
    
    # Ask for restore scope
    echo
    echo "Select what to restore:"
    echo "1. Everything (full restore)"
    echo "2. System configurations only"
    echo "3. Component configurations only"
    echo "4. Home directory files only"
    echo
    
    local restore_filter=""
    choice=$(ask_choice "Select restore scope" \
        "Everything" \
        "System only" \
        "Components only" \
        "Home directory only")
    
    case "$choice" in
        "Everything") restore_filter="" ;;
        "System only") restore_filter="system" ;;
        "Components only") restore_filter="components" ;;
        "Home directory only") restore_filter="home" ;;
        *)
            log_info "Restore cancelled by user"
            return 1
            ;;
    esac
    
    # Confirm restore operation
    echo
    log_warn "This will restore files from the backup session to your system"
    if [[ "$restore_mode" == "replace" ]]; then
        log_warn "Existing files will be REPLACED without backup"
    fi
    
    if ! ask_yes_no "Are you sure you want to proceed with the restore?" "n"; then
        log_info "Restore cancelled by user"
        return 1
    fi
    
    # Perform restore
    restore_full_session "$session_dir" "$restore_mode" "$restore_filter"
}

#######################################
# Rollback Functions
#######################################

# Quick rollback to most recent backup
# Arguments: $1 - session name pattern (optional)
# Returns: 0 if successful, 1 if failed
# Requirements: 10.2 - Provide recovery instructions on critical errors
quick_rollback() {
    local session_pattern="${1:-system}"
    
    log_section "Quick Rollback"
    log_info "Looking for most recent backup session matching: $session_pattern"
    
    # Find most recent backup session
    local latest_session
    if ! latest_session=$(get_latest_backup_session "$session_pattern"); then
        log_error "No backup sessions found matching pattern: $session_pattern"
        log_error "Available sessions:"
        list_backup_sessions
        return 1
    fi
    
    log_info "Found latest backup session: $(basename "$latest_session")"
    
    # Confirm rollback
    if ! ask_yes_no "Rollback to this backup session?" "y"; then
        log_info "Rollback cancelled by user"
        return 1
    fi
    
    # Perform rollback with replace mode
    restore_full_session "$latest_session" "replace"
}

#######################################
# Main Function and CLI Interface
#######################################

# Main function for command-line usage
main() {
    local action="$1"
    shift
    
    # Initialize logger if not already done
    if [[ -z "$LOG_FILE" ]]; then
        init_logger
    fi
    
    case "$action" in
        "restore-path")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: restore-path <backup_path> <target_path> [mode]"
                exit 1
            fi
            restore_path "$1" "$2" "$3"
            ;;
        "restore-component")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: restore-component <component_name> <session_dir> [mode]"
                exit 1
            fi
            restore_component_configs "$1" "$2" "$3"
            ;;
        "restore-system")
            if [[ $# -lt 1 ]]; then
                log_error "Usage: restore-system <session_dir> [mode]"
                exit 1
            fi
            restore_system_configs "$1" "$2"
            ;;
        "restore-session")
            if [[ $# -lt 1 ]]; then
                log_error "Usage: restore-session <session_dir> [mode] [filter]"
                exit 1
            fi
            restore_full_session "$1" "$2" "$3"
            ;;
        "interactive")
            interactive_restore "$1"
            ;;
        "rollback")
            quick_rollback "$1"
            ;;
        "validate")
            if [[ -z "$1" ]]; then
                log_error "Session directory required for validate action"
                exit 1
            fi
            validate_restore_session "$1"
            ;;
        *)
            echo "Usage: $0 {restore-path|restore-component|restore-system|restore-session|interactive|rollback|validate} [args...]"
            echo
            echo "Commands:"
            echo "  restore-path <backup> <target> [mode]     - Restore single path"
            echo "  restore-component <comp> <session> [mode] - Restore component configs"
            echo "  restore-system <session> [mode]          - Restore system configs"
            echo "  restore-session <session> [mode] [filter] - Restore full session"
            echo "  interactive [session]                     - Interactive restore"
            echo "  rollback [pattern]                        - Quick rollback to latest backup"
            echo "  validate <session_dir>                    - Validate session for restore"
            echo
            echo "Restore modes: replace, skip, merge"
            echo "Filters: system, components, home"
            exit 1
            ;;
    esac
}

# Allow script to be sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi