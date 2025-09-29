#!/usr/bin/env bash

# configs/backup.sh - Configuration backup utilities
# This module provides timestamp-based backup directory creation and selective backup capabilities
# Requirements: 6.2, 10.2

# Prevent multiple sourcing
if [[ -n "${BACKUP_UTILS_SOURCED:-}" ]]; then
    return 0
fi
readonly BACKUP_UTILS_SOURCED=1

# Initialize all project paths
source "$(dirname "${BASH_SOURCE[0]}")/../core/init-paths.sh"

# Source core utilities
source "$CORE_DIR/common.sh"
source "$CORE_DIR/logger.sh"

# Global configuration
BACKUP_BASE_DIR="${BACKUP_BASE_DIR:-$HOME/.config/install-backups}"
BACKUP_METADATA_FILE=".backup_metadata"
BACKUP_INDEX_FILE="backup_index.json"

#######################################
# Backup Session Management
#######################################

# Create a new backup session with timestamp
# Arguments: $1 - session name (optional, defaults to 'system')
# Returns: Echoes backup session directory path
# Requirements: 6.2 - Create backups of existing configurations before making changes
create_backup_session() {
    local session_name="${1:-system}"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local session_dir="$BACKUP_BASE_DIR/${session_name}_$timestamp"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create backup session: $session_dir"
        echo "$session_dir"
        return 0
    fi
    
    # Create backup directory structure
    if ! mkdir -p "$session_dir"; then
        log_error "Failed to create backup session directory: $session_dir"
        return 1
    fi
    
    # Create metadata file
    local metadata_file="$session_dir/$BACKUP_METADATA_FILE"
    cat > "$metadata_file" << EOF
# Backup Session Metadata
SESSION_NAME=$session_name
TIMESTAMP=$timestamp
CREATED_BY=$USER
CREATED_ON=$(uname -n 2>/dev/null || cat /proc/sys/kernel/hostname 2>/dev/null || echo "unknown")
CREATED_AT=$(date -Iseconds 2>/dev/null || date)
BACKUP_VERSION=1.0
EOF
    
    log_info "Created backup session: $session_dir"
    echo "$session_dir"
    return 0
}

# Get the latest backup session for a given name
# Arguments: $1 - session name (optional, defaults to 'system')
# Returns: Echoes latest backup session directory path
get_latest_backup_session() {
    local session_name="${1:-system}"
    
    if [[ ! -d "$BACKUP_BASE_DIR" ]]; then
        log_debug "Backup base directory does not exist: $BACKUP_BASE_DIR"
        return 1
    fi
    
    # Find the most recent backup session
    local latest_session
    latest_session=$(find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "${session_name}_*" | sort -r | head -n1)
    
    if [[ -z "$latest_session" ]]; then
        log_debug "No backup sessions found for: $session_name"
        return 1
    fi
    
    echo "$latest_session"
    return 0
}

# List all backup sessions
# Arguments: $1 - session name filter (optional)
# Returns: Echoes list of backup sessions with metadata
list_backup_sessions() {
    local session_filter="$1"
    local pattern="*"
    
    if [[ -n "$session_filter" ]]; then
        pattern="${session_filter}_*"
    fi
    
    if [[ ! -d "$BACKUP_BASE_DIR" ]]; then
        log_info "No backup sessions found (backup directory does not exist)"
        return 0
    fi
    
    log_section "Available Backup Sessions"
    
    local sessions_found=0
    while IFS= read -r -d '' session_dir; do
        local session_name
        session_name=$(basename "$session_dir")
        
        # Read metadata if available
        local metadata_file="$session_dir/$BACKUP_METADATA_FILE"
        local created_at="Unknown"
        local created_by="Unknown"
        local backup_size="Unknown"
        
        if [[ -f "$metadata_file" ]]; then
            # Source metadata safely
            while IFS='=' read -r key value; do
                case "$key" in
                    "CREATED_AT") created_at="$value" ;;
                    "CREATED_BY") created_by="$value" ;;
                esac
            done < "$metadata_file"
        fi
        
        # Calculate backup size
        if command -v du >/dev/null 2>&1; then
            backup_size=$(du -sh "$session_dir" 2>/dev/null | cut -f1)
        fi
        
        # Count backed up files
        local file_count
        file_count=$(find "$session_dir" -type f ! -name "$BACKUP_METADATA_FILE" | wc -l)
        
        echo "  Session: $session_name"
        echo "    Created: $created_at by $created_by"
        echo "    Size: $backup_size ($file_count files)"
        echo "    Path: $session_dir"
        echo
        
        ((sessions_found++))
    done < <(find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "$pattern" -print0 | sort -z)
    
    if [[ $sessions_found -eq 0 ]]; then
        log_info "No backup sessions found matching pattern: $pattern"
    else
        log_info "Found $sessions_found backup session(s)"
    fi
    
    return 0
}

#######################################
# File and Directory Backup Functions
#######################################

# Backup a single file or directory
# Arguments: $1 - source path, $2 - backup session directory, $3 - relative backup path (optional)
# Returns: 0 if successful, 1 if failed
backup_path() {
    local source_path="$1"
    local session_dir="$2"
    local relative_path="${3:-}"
    
    if [[ -z "$source_path" || -z "$session_dir" ]]; then
        log_error "Source path and session directory are required"
        return 1
    fi
    
    if [[ ! -e "$source_path" ]]; then
        log_debug "Source path does not exist, skipping backup: $source_path"
        return 0
    fi
    
    # Determine backup path
    local backup_path
    if [[ -n "$relative_path" ]]; then
        backup_path="$session_dir/$relative_path"
    else
        # Create relative path based on source location
        if [[ "$source_path" == "$HOME"/* ]]; then
            # Remove $HOME prefix for home directory files
            local rel_path="${source_path#$HOME/}"
            backup_path="$session_dir/home/$rel_path"
        elif [[ "$source_path" == /etc/* ]]; then
            # System configuration files
            backup_path="$session_dir/system${source_path}"
        else
            # Other absolute paths
            backup_path="$session_dir/root${source_path}"
        fi
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would backup: $source_path -> $backup_path"
        return 0
    fi
    
    # Create backup directory
    local backup_dir
    backup_dir=$(dirname "$backup_path")
    if ! mkdir -p "$backup_dir"; then
        log_error "Failed to create backup directory: $backup_dir"
        return 1
    fi
    
    # Perform backup based on file type
    if [[ -d "$source_path" ]]; then
        # Backup directory recursively
        if ! cp -rp "$source_path" "$backup_path"; then
            log_error "Failed to backup directory: $source_path"
            return 1
        fi
        log_debug "Backed up directory: $source_path -> $backup_path"
    elif [[ -L "$source_path" ]]; then
        # Backup symlink (preserve link)
        local link_target
        link_target=$(readlink "$source_path")
        if ! ln -s "$link_target" "$backup_path"; then
            log_error "Failed to backup symlink: $source_path"
            return 1
        fi
        log_debug "Backed up symlink: $source_path -> $backup_path (target: $link_target)"
    else
        # Backup regular file
        if ! cp -p "$source_path" "$backup_path"; then
            log_error "Failed to backup file: $source_path"
            return 1
        fi
        log_debug "Backed up file: $source_path -> $backup_path"
    fi
    
    return 0
}

# Backup multiple paths to a session
# Arguments: $1 - session directory, $@ - list of paths to backup
# Returns: 0 if all successful, 1 if any failed
backup_multiple_paths() {
    local session_dir="$1"
    shift
    local paths=("$@")
    
    if [[ -z "$session_dir" ]]; then
        log_error "Session directory is required"
        return 1
    fi
    
    if [[ ${#paths[@]} -eq 0 ]]; then
        log_error "No paths specified for backup"
        return 1
    fi
    
    local success_count=0
    local failed_count=0
    local failed_paths=()
    
    log_info "Backing up ${#paths[@]} paths to session: $(basename "$session_dir")"
    
    for path in "${paths[@]}"; do
        if backup_path "$path" "$session_dir"; then
            ((success_count++))
        else
            ((failed_count++))
            failed_paths+=("$path")
        fi
    done
    
    # Report results
    if [[ $success_count -gt 0 ]]; then
        log_success "Successfully backed up $success_count paths"
    fi
    
    if [[ $failed_count -gt 0 ]]; then
        log_error "Failed to backup $failed_count paths:"
        for failed_path in "${failed_paths[@]}"; do
            log_error "  - $failed_path"
        done
        return 1
    fi
    
    return 0
}

#######################################
# Component-Specific Backup Functions
#######################################

# Backup configurations for a specific component
# Arguments: $1 - component name, $2 - session directory
# Returns: 0 if successful, 1 if failed
backup_component_configs() {
    local component="$1"
    local session_dir="$2"
    
    if [[ -z "$component" || -z "$session_dir" ]]; then
        log_error "Component name and session directory are required"
        return 1
    fi
    
    # Source dotfiles manager to get component configuration structure
    if [[ -f "$CONFIGS_DIR/dotfiles-manager.sh" ]]; then
        source "$CONFIGS_DIR/dotfiles-manager.sh"
    else
        log_error "Dotfiles manager not found, cannot determine component configurations"
        return 1
    fi
    
    log_info "Backing up configurations for component: $component"
    
    # Get component configuration mappings
    local config_paths=()
    while IFS='|' read -r source_file target_path; do
        config_paths+=("$target_path")
    done < <(get_component_config_structure "$component" 2>/dev/null)
    
    if [[ ${#config_paths[@]} -eq 0 ]]; then
        log_info "No configurations found for component: $component"
        return 0
    fi
    
    # Create component-specific backup directory
    local component_backup_dir="$session_dir/components/$component"
    if [[ "$DRY_RUN" != "true" ]]; then
        mkdir -p "$component_backup_dir"
    fi
    
    # Backup each configuration path
    local success_count=0
    local failed_count=0
    
    for config_path in "${config_paths[@]}"; do
        if [[ -e "$config_path" ]]; then
            local relative_path="components/$component/$(basename "$config_path")"
            if backup_path "$config_path" "$session_dir" "$relative_path"; then
                ((success_count++))
            else
                ((failed_count++))
            fi
        fi
    done
    
    if [[ $success_count -gt 0 ]]; then
        log_success "Backed up $success_count configurations for component: $component"
    fi
    
    if [[ $failed_count -gt 0 ]]; then
        log_warn "Failed to backup $failed_count configurations for component: $component"
        return 1
    fi
    
    return 0
}

# Backup configurations for multiple components
# Arguments: $1 - session directory, $@ - list of component names
# Returns: 0 if all successful, 1 if any failed
backup_multiple_components() {
    local session_dir="$1"
    shift
    local components=("$@")
    
    if [[ -z "$session_dir" ]]; then
        log_error "Session directory is required"
        return 1
    fi
    
    if [[ ${#components[@]} -eq 0 ]]; then
        log_error "No components specified for backup"
        return 1
    fi
    
    local success_count=0
    local failed_count=0
    local failed_components=()
    
    log_section "Backing Up Component Configurations"
    log_info "Components to backup: ${components[*]}"
    
    for component in "${components[@]}"; do
        if backup_component_configs "$component" "$session_dir"; then
            ((success_count++))
        else
            ((failed_count++))
            failed_components+=("$component")
        fi
    done
    
    # Report final results
    if [[ $success_count -gt 0 ]]; then
        log_success "Successfully backed up $success_count components"
    fi
    
    if [[ $failed_count -gt 0 ]]; then
        log_error "Failed to backup components: ${failed_components[*]}"
        return 1
    fi
    
    return 0
}

#######################################
# System Backup Functions
#######################################

# Backup common system configuration files
# Arguments: $1 - session directory
# Returns: 0 if successful, 1 if failed
backup_system_configs() {
    local session_dir="$1"
    
    if [[ -z "$session_dir" ]]; then
        log_error "Session directory is required"
        return 1
    fi
    
    log_info "Backing up system configuration files"
    
    # Common system configuration files to backup
    local system_configs=(
        "/etc/fstab"
        "/etc/hosts"
        "/etc/hostname"
        "/etc/locale.conf"
        "/etc/vconsole.conf"
        "/etc/mkinitcpio.conf"
        "/etc/pacman.conf"
        "/etc/makepkg.conf"
        "/boot/loader/loader.conf"
        "/boot/loader/entries"
    )
    
    # User-specific system files
    local user_configs=(
        "$HOME/.bashrc"
        "$HOME/.bash_profile"
        "$HOME/.profile"
        "$HOME/.xinitrc"
        "$HOME/.xprofile"
        "$HOME/.pam_environment"
    )
    
    local all_configs=("${system_configs[@]}" "${user_configs[@]}")
    
    # Filter existing files
    local existing_configs=()
    for config in "${all_configs[@]}"; do
        if [[ -e "$config" ]]; then
            existing_configs+=("$config")
        fi
    done
    
    if [[ ${#existing_configs[@]} -eq 0 ]]; then
        log_info "No system configuration files found to backup"
        return 0
    fi
    
    backup_multiple_paths "$session_dir" "${existing_configs[@]}"
}

# Create a system backup (wrapper for create_full_system_backup)
# Arguments: $1 - session name (optional)
# Returns: 0 if successful, 1 if failed
create_system_backup() {
    local session_name="${1:-system}"
    create_full_system_backup "$session_name"
}

# Create a backup for a specific component configuration
# Arguments: $1 - component name
# Returns: 0 if successful, 1 if failed
create_config_backup() {
    local component="$1"
    
    if [[ -z "$component" ]]; then
        log_error "Component name is required for config backup"
        return 1
    fi
    
    log_info "Creating configuration backup for component: $component"
    
    # Create backup session for this component
    local session_dir
    if ! session_dir=$(create_backup_session "config_${component}"); then
        return 1
    fi
    
    # Backup the component configurations
    if backup_component_configs "$component" "$session_dir"; then
        log_success "Configuration backup completed for $component: $session_dir"
        return 0
    else
        log_error "Failed to backup configurations for component: $component"
        return 1
    fi
}

# Create a full system backup
# Arguments: $1 - session name (optional)
# Returns: 0 if successful, 1 if failed
create_full_system_backup() {
    local session_name="${1:-full_system}"
    
    log_section "Creating Full System Backup"
    
    # Create backup session
    local session_dir
    if ! session_dir=$(create_backup_session "$session_name"); then
        return 1
    fi
    
    # Backup system configurations
    if ! backup_system_configs "$session_dir"; then
        log_error "Failed to backup system configurations"
        return 1
    fi
    
    # Backup all available components
    if [[ -f "$CONFIGS_DIR/dotfiles-manager.sh" ]]; then
        source "$CONFIGS_DIR/dotfiles-manager.sh"
        
        local components
        if components=$(discover_dotfiles_components 2>/dev/null); then
            local component_array
            readarray -t component_array <<< "$components"
            backup_multiple_components "$session_dir" "${component_array[@]}"
        fi
    fi
    
    log_success "Full system backup completed: $session_dir"
    return 0
}

#######################################
# Backup Validation and Cleanup
#######################################

# Validate backup session integrity
# Arguments: $1 - session directory
# Returns: 0 if valid, 1 if invalid
validate_backup_session() {
    local session_dir="$1"
    
    if [[ -z "$session_dir" ]]; then
        log_error "Session directory is required"
        return 1
    fi
    
    if [[ ! -d "$session_dir" ]]; then
        log_error "Backup session directory does not exist: $session_dir"
        return 1
    fi
    
    log_info "Validating backup session: $(basename "$session_dir")"
    
    # Check for metadata file
    local metadata_file="$session_dir/$BACKUP_METADATA_FILE"
    if [[ ! -f "$metadata_file" ]]; then
        log_warn "Backup metadata file missing: $metadata_file"
    fi
    
    # Count files in backup
    local file_count
    file_count=$(find "$session_dir" -type f ! -name "$BACKUP_METADATA_FILE" | wc -l)
    
    if [[ $file_count -eq 0 ]]; then
        log_warn "Backup session contains no files"
        return 1
    fi
    
    log_success "Backup session is valid ($file_count files)"
    return 0
}

# Clean up old backup sessions
# Arguments: $1 - number of sessions to keep (default: 5), $2 - session name pattern (optional)
# Returns: 0 if successful, 1 if failed
cleanup_old_backups() {
    local keep_count="${1:-5}"
    local session_pattern="${2:-*}"
    
    if [[ ! -d "$BACKUP_BASE_DIR" ]]; then
        log_info "No backup directory to clean up"
        return 0
    fi
    
    log_info "Cleaning up old backup sessions (keeping $keep_count most recent)"
    
    # Find all backup sessions matching pattern, sorted by modification time (newest first)
    local sessions
    readarray -t sessions < <(find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "$session_pattern" -printf '%T@ %p\n' | sort -rn | cut -d' ' -f2-)
    
    if [[ ${#sessions[@]} -le $keep_count ]]; then
        log_info "No cleanup needed (${#sessions[@]} sessions, keeping $keep_count)"
        return 0
    fi
    
    # Remove old sessions
    local removed_count=0
    for ((i=keep_count; i<${#sessions[@]}; i++)); do
        local session_dir="${sessions[i]}"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would remove old backup session: $(basename "$session_dir")"
            ((removed_count++))
        else
            if rm -rf "$session_dir"; then
                log_info "Removed old backup session: $(basename "$session_dir")"
                ((removed_count++))
            else
                log_error "Failed to remove backup session: $session_dir"
            fi
        fi
    done
    
    if [[ $removed_count -gt 0 ]]; then
        log_success "Cleaned up $removed_count old backup sessions"
    fi
    
    return 0
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
        "create")
            local session_name="${1:-system}"
            create_backup_session "$session_name"
            ;;
        "list")
            list_backup_sessions "$1"
            ;;
        "backup-path")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: backup-path <source_path> <session_dir> [relative_path]"
                exit 1
            fi
            backup_path "$1" "$2" "$3"
            ;;
        "backup-component")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: backup-component <component_name> <session_dir>"
                exit 1
            fi
            backup_component_configs "$1" "$2"
            ;;
        "backup-system")
            backup_system_configs "$1"
            ;;
        "full-backup")
            create_full_system_backup "$1"
            ;;
        "validate")
            if [[ -z "$1" ]]; then
                log_error "Session directory required for validate action"
                exit 1
            fi
            validate_backup_session "$1"
            ;;
        "cleanup")
            cleanup_old_backups "$1" "$2"
            ;;
        *)
            echo "Usage: $0 {create|list|backup-path|backup-component|backup-system|full-backup|validate|cleanup} [args...]"
            echo
            echo "Commands:"
            echo "  create [session_name]                    - Create new backup session"
            echo "  list [session_filter]                    - List backup sessions"
            echo "  backup-path <source> <session> [rel]     - Backup single path"
            echo "  backup-component <component> <session>   - Backup component configs"
            echo "  backup-system <session>                  - Backup system configs"
            echo "  full-backup [session_name]               - Create full system backup"
            echo "  validate <session_dir>                   - Validate backup session"
            echo "  cleanup [keep_count] [pattern]           - Clean up old backups"
            exit 1
            ;;
    esac
}

# Allow script to be sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi