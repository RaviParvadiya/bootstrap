#!/bin/bash

# configs/dotfiles-manager.sh - Dotfiles management module
# This module handles symlink creation, configuration file discovery,
# conflict resolution, and backup creation for dotfiles management.
# Requirements: 7.1, 7.2, 7.3

# Prevent multiple sourcing
if [[ -n "${DOTFILES_MANAGER_SOURCED:-}" ]]; then
    return 0
fi
readonly DOTFILES_MANAGER_SOURCED=1

# Source required modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source core utilities
source "$PROJECT_ROOT/core/common.sh"
source "$PROJECT_ROOT/core/logger.sh"

# Global configuration
DOTFILES_DIR="$PROJECT_ROOT/dotfiles"
BACKUP_BASE_DIR="$HOME/.config/install-backups"
CURRENT_BACKUP_DIR=""

#######################################
# Dotfiles Discovery Functions
#######################################

# Discover all available dotfiles configurations
# Returns: Echoes list of available components
# Requirements: 7.1 - Configuration file discovery from existing dotfiles repository
discover_dotfiles_components() {
    local components=()
    
    if [[ ! -d "$DOTFILES_DIR" ]]; then
        log_error "Dotfiles directory not found: $DOTFILES_DIR"
        return 1
    fi
    
    log_debug "Discovering dotfiles components in: $DOTFILES_DIR"
    
    # Find all component directories (exclude hidden files and scripts)
    while IFS= read -r -d '' dir; do
        local component_name
        component_name=$(basename "$dir")
        
        # Skip non-component files and directories
        case "$component_name" in
            ".*"|"install.sh"|"update.sh"|"README.md"|"TODO.txt"|"pkglist-"*)
                continue
                ;;
            *)
                components+=("$component_name")
                ;;
        esac
    done < <(find "$DOTFILES_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
    
    if [[ ${#components[@]} -eq 0 ]]; then
        log_warn "No dotfiles components found in $DOTFILES_DIR"
        return 1
    fi
    
    log_debug "Found ${#components[@]} dotfiles components: ${components[*]}"
    printf '%s\n' "${components[@]}"
    return 0
}

# Get component configuration structure
# Arguments: $1 - component name
# Returns: Echoes configuration paths and their target locations
get_component_config_structure() {
    local component="$1"
    local component_dir="$DOTFILES_DIR/$component"
    
    if [[ -z "$component" ]]; then
        log_error "Component name is required"
        return 1
    fi
    
    if [[ ! -d "$component_dir" ]]; then
        log_error "Component directory not found: $component_dir"
        return 1
    fi
    
    log_debug "Analyzing configuration structure for component: $component"
    
    # Find all configuration files and determine their target locations
    while IFS= read -r -d '' file; do
        local relative_path="${file#$component_dir/}"
        local target_path
        
        # Determine target path based on file structure
        if [[ "$relative_path" == .config/* ]]; then
            # Files in .config/ go to $HOME/.config/
            target_path="$HOME/$relative_path"
        elif [[ "$relative_path" == .* ]]; then
            # Hidden files go directly to $HOME/
            target_path="$HOME/$relative_path"
        else
            # Other files go to $HOME/.config/ by default
            target_path="$HOME/.config/$relative_path"
        fi
        
        echo "$file|$target_path"
    done < <(find "$component_dir" -type f -print0)
}

# Check if component has configurations
# Arguments: $1 - component name
# Returns: 0 if has configs, 1 if no configs
has_configurations() {
    local component="$1"
    local config_count
    
    config_count=$(get_component_config_structure "$component" | wc -l)
    [[ $config_count -gt 0 ]]
}

#######################################
# Backup Management Functions
#######################################

# Initialize backup directory for current session
# Returns: 0 if successful, 1 if failed
# Requirements: 7.3 - Backup creation for existing configurations
init_backup_session() {
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    CURRENT_BACKUP_DIR="$BACKUP_BASE_DIR/dotfiles_$timestamp"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create backup directory: $CURRENT_BACKUP_DIR"
        return 0
    fi
    
    if ! mkdir -p "$CURRENT_BACKUP_DIR"; then
        log_error "Failed to create backup directory: $CURRENT_BACKUP_DIR"
        return 1
    fi
    
    log_info "Initialized backup session: $CURRENT_BACKUP_DIR"
    return 0
}

# Create backup of existing file or directory
# Arguments: $1 - source path to backup
# Returns: 0 if successful, 1 if failed
create_backup() {
    local source_path="$1"
    local backup_path
    
    if [[ -z "$source_path" ]]; then
        log_error "Source path is required for backup"
        return 1
    fi
    
    if [[ ! -e "$source_path" ]]; then
        log_debug "Source path does not exist, no backup needed: $source_path"
        return 0
    fi
    
    # Ensure backup session is initialized
    if [[ -z "$CURRENT_BACKUP_DIR" ]]; then
        if ! init_backup_session; then
            return 1
        fi
    fi
    
    # Create backup path maintaining directory structure
    if [[ "$source_path" == "$HOME"/* ]]; then
        # Remove $HOME prefix and create relative path
        local relative_path="${source_path#$HOME/}"
        backup_path="$CURRENT_BACKUP_DIR/home/$relative_path"
    else
        # For absolute paths, create full path structure
        backup_path="$CURRENT_BACKUP_DIR/root$source_path"
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
    
    # Copy file or directory to backup location
    if [[ -d "$source_path" ]]; then
        if ! cp -r "$source_path" "$backup_path"; then
            log_error "Failed to backup directory: $source_path"
            return 1
        fi
    else
        if ! cp "$source_path" "$backup_path"; then
            log_error "Failed to backup file: $source_path"
            return 1
        fi
    fi
    
    log_debug "Created backup: $source_path -> $backup_path"
    return 0
}

# List all backup sessions
# Returns: Echoes list of backup directories
list_backup_sessions() {
    if [[ ! -d "$BACKUP_BASE_DIR" ]]; then
        log_info "No backup sessions found"
        return 0
    fi
    
    find "$BACKUP_BASE_DIR" -mindepth 1 -maxdepth 1 -type d -name "dotfiles_*" | sort
}

# Restore from backup session
# Arguments: $1 - backup session directory, $2 - specific file (optional)
# Returns: 0 if successful, 1 if failed
restore_from_backup() {
    local backup_session="$1"
    local specific_file="$2"
    
    if [[ ! -d "$backup_session" ]]; then
        log_error "Backup session not found: $backup_session"
        return 1
    fi
    
    log_info "Restoring from backup session: $backup_session"
    
    if [[ -n "$specific_file" ]]; then
        # Restore specific file
        local backup_file="$backup_session/home/$specific_file"
        local target_file="$HOME/$specific_file"
        
        if [[ ! -e "$backup_file" ]]; then
            log_error "Backup file not found: $backup_file"
            return 1
        fi
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would restore: $backup_file -> $target_file"
            return 0
        fi
        
        cp -r "$backup_file" "$target_file"
        log_success "Restored: $target_file"
    else
        # Restore entire session
        local home_backup="$backup_session/home"
        
        if [[ ! -d "$home_backup" ]]; then
            log_error "Home backup not found in session: $home_backup"
            return 1
        fi
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would restore entire session from: $home_backup"
            return 0
        fi
        
        # Copy all files from backup to home directory
        if ! cp -r "$home_backup"/* "$HOME/"; then
            log_error "Failed to restore backup session"
            return 1
        fi
        
        log_success "Restored entire backup session"
    fi
    
    return 0
}

#######################################
# Conflict Resolution Functions
#######################################

# Check for configuration conflicts
# Arguments: $1 - component name
# Returns: 0 if no conflicts, 1 if conflicts found
# Requirements: 7.3 - Conflict resolution
check_config_conflicts() {
    local component="$1"
    local conflicts=()
    
    if [[ -z "$component" ]]; then
        log_error "Component name is required"
        return 1
    fi
    
    log_debug "Checking for configuration conflicts: $component"
    
    # Get all configuration mappings for the component
    while IFS='|' read -r source_file target_path; do
        if [[ -e "$target_path" ]]; then
            # Check if it's already a symlink to our source
            if [[ -L "$target_path" ]]; then
                local current_target
                current_target=$(readlink "$target_path")
                if [[ "$current_target" != "$source_file" ]]; then
                    conflicts+=("$target_path (symlink to different target)")
                fi
            else
                conflicts+=("$target_path (regular file/directory)")
            fi
        fi
    done < <(get_component_config_structure "$component")
    
    if [[ ${#conflicts[@]} -gt 0 ]]; then
        log_warn "Configuration conflicts found for $component:"
        for conflict in "${conflicts[@]}"; do
            log_warn "  - $conflict"
        done
        return 1
    fi
    
    log_debug "No configuration conflicts found for: $component"
    return 0
}

# Resolve configuration conflicts interactively
# Arguments: $1 - component name
# Returns: 0 if resolved, 1 if user cancelled
resolve_config_conflicts() {
    local component="$1"
    local resolution_strategy=""
    
    if ! check_config_conflicts "$component"; then
        echo
        echo "Configuration conflicts detected for component: $component"
        echo "How would you like to resolve these conflicts?"
        echo
        echo "1. Backup existing files and create symlinks (recommended)"
        echo "2. Skip conflicting files and only link non-conflicting ones"
        echo "3. Overwrite existing files without backup (dangerous)"
        echo "4. Cancel installation for this component"
        echo
        
        local choice
        choice=$(ask_choice "Select resolution strategy" \
            "Backup and replace" \
            "Skip conflicts" \
            "Overwrite without backup" \
            "Cancel")
        
        case "$choice" in
            "Backup and replace")
                resolution_strategy="backup"
                ;;
            "Skip conflicts")
                resolution_strategy="skip"
                ;;
            "Overwrite without backup")
                resolution_strategy="overwrite"
                if ! ask_yes_no "Are you sure? This will permanently delete existing configurations!" "n"; then
                    resolution_strategy="cancel"
                fi
                ;;
            "Cancel")
                resolution_strategy="cancel"
                ;;
        esac
        
        if [[ "$resolution_strategy" == "cancel" ]]; then
            log_info "Installation cancelled for component: $component"
            return 1
        fi
        
        # Store resolution strategy for apply_component_configs
        export CONFLICT_RESOLUTION="$resolution_strategy"
    fi
    
    return 0
}

#######################################
# Symlink Management Functions
#######################################

# Create symlink with conflict handling
# Arguments: $1 - source file, $2 - target path, $3 - conflict resolution strategy
# Returns: 0 if successful, 1 if failed or skipped
create_managed_symlink() {
    local source_file="$1"
    local target_path="$2"
    local resolution="${3:-backup}"
    
    if [[ -z "$source_file" || -z "$target_path" ]]; then
        log_error "Source file and target path are required"
        return 1
    fi
    
    if [[ ! -e "$source_file" ]]; then
        log_error "Source file does not exist: $source_file"
        return 1
    fi
    
    # Create target directory if needed
    local target_dir
    target_dir=$(dirname "$target_path")
    if [[ ! -d "$target_dir" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_debug "[DRY RUN] Would create directory: $target_dir"
        else
            if ! mkdir -p "$target_dir"; then
                log_error "Failed to create directory: $target_dir"
                return 1
            fi
            log_debug "Created directory: $target_dir"
        fi
    fi
    
    # Handle existing file/symlink
    if [[ -e "$target_path" || -L "$target_path" ]]; then
        # Check if it's already the correct symlink
        if [[ -L "$target_path" ]]; then
            local current_target
            current_target=$(readlink "$target_path")
            if [[ "$current_target" == "$source_file" ]]; then
                log_debug "Symlink already exists and is correct: $target_path"
                return 0
            fi
        fi
        
        # Handle conflict based on resolution strategy
        case "$resolution" in
            "backup")
                if ! create_backup "$target_path"; then
                    log_error "Failed to create backup for: $target_path"
                    return 1
                fi
                log_info "Backed up existing file: $target_path"
                ;;
            "skip")
                log_info "Skipping conflicting file: $target_path"
                return 0
                ;;
            "overwrite")
                log_warn "Overwriting existing file: $target_path"
                ;;
            *)
                log_error "Unknown conflict resolution strategy: $resolution"
                return 1
                ;;
        esac
        
        # Remove existing file/symlink
        if [[ "$DRY_RUN" == "true" ]]; then
            log_debug "[DRY RUN] Would remove existing: $target_path"
        else
            if ! rm -rf "$target_path"; then
                log_error "Failed to remove existing file: $target_path"
                return 1
            fi
        fi
    fi
    
    # Create the symlink
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create symlink: $target_path -> $source_file"
    else
        if ! ln -s "$source_file" "$target_path"; then
            log_error "Failed to create symlink: $target_path -> $source_file"
            return 1
        fi
        log_success "Created symlink: $target_path -> $source_file"
    fi
    
    return 0
}

# Remove symlinks for a component
# Arguments: $1 - component name
# Returns: 0 if successful, 1 if failed
remove_component_symlinks() {
    local component="$1"
    local removed_count=0
    local failed_count=0
    
    if [[ -z "$component" ]]; then
        log_error "Component name is required"
        return 1
    fi
    
    log_info "Removing symlinks for component: $component"
    
    # Get all configuration mappings for the component
    while IFS='|' read -r source_file target_path; do
        if [[ -L "$target_path" ]]; then
            local current_target
            current_target=$(readlink "$target_path")
            if [[ "$current_target" == "$source_file" ]]; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    log_info "[DRY RUN] Would remove symlink: $target_path"
                    ((removed_count++))
                else
                    if rm "$target_path"; then
                        log_debug "Removed symlink: $target_path"
                        ((removed_count++))
                    else
                        log_error "Failed to remove symlink: $target_path"
                        ((failed_count++))
                    fi
                fi
            fi
        fi
    done < <(get_component_config_structure "$component")
    
    if [[ $removed_count -gt 0 ]]; then
        log_success "Removed $removed_count symlinks for component: $component"
    else
        log_info "No symlinks found to remove for component: $component"
    fi
    
    if [[ $failed_count -gt 0 ]]; then
        log_warn "Failed to remove $failed_count symlinks"
        return 1
    fi
    
    return 0
}

#######################################
# Main Configuration Application Functions
#######################################

# Apply configurations for a specific component
# Arguments: $1 - component name
# Returns: 0 if successful, 1 if failed
# Requirements: 7.1, 7.2 - Symlink creation and configuration management
apply_component_configs() {
    local component="$1"
    local resolution="${CONFLICT_RESOLUTION:-backup}"
    local success_count=0
    local failed_count=0
    
    if [[ -z "$component" ]]; then
        log_error "Component name is required"
        return 1
    fi
    
    if ! has_configurations "$component"; then
        log_info "No configurations found for component: $component"
        return 0
    fi
    
    log_section "Applying Configurations: $component"
    
    # Initialize backup session if using backup resolution
    if [[ "$resolution" == "backup" ]]; then
        init_backup_session
    fi
    
    # Apply each configuration file
    while IFS='|' read -r source_file target_path; do
        if create_managed_symlink "$source_file" "$target_path" "$resolution"; then
            ((success_count++))
        else
            ((failed_count++))
        fi
    done < <(get_component_config_structure "$component")
    
    # Report results
    if [[ $success_count -gt 0 ]]; then
        log_success "Applied $success_count configurations for component: $component"
    fi
    
    if [[ $failed_count -gt 0 ]]; then
        log_error "Failed to apply $failed_count configurations for component: $component"
        return 1
    fi
    
    # Clear resolution strategy
    unset CONFLICT_RESOLUTION
    
    return 0
}

# Apply configurations for multiple components
# Arguments: Array of component names
# Returns: 0 if all successful, 1 if any failed
apply_multiple_components() {
    local components=("$@")
    local failed_components=()
    
    if [[ ${#components[@]} -eq 0 ]]; then
        log_error "No components specified"
        return 1
    fi
    
    log_section "Applying Multiple Component Configurations"
    log_info "Components to configure: ${components[*]}"
    
    for component in "${components[@]}"; do
        # Check for conflicts and resolve them
        if ! resolve_config_conflicts "$component"; then
            log_warn "Skipping component due to unresolved conflicts: $component"
            failed_components+=("$component")
            continue
        fi
        
        # Apply configurations
        if ! apply_component_configs "$component"; then
            failed_components+=("$component")
        fi
    done
    
    # Report final results
    local success_count=$((${#components[@]} - ${#failed_components[@]}))
    
    if [[ $success_count -gt 0 ]]; then
        log_success "Successfully configured $success_count components"
    fi
    
    if [[ ${#failed_components[@]} -gt 0 ]]; then
        log_error "Failed to configure components: ${failed_components[*]}"
        return 1
    fi
    
    return 0
}

# Remove configurations for a component
# Arguments: $1 - component name
# Returns: 0 if successful, 1 if failed
remove_component_configs() {
    local component="$1"
    
    if [[ -z "$component" ]]; then
        log_error "Component name is required"
        return 1
    fi
    
    log_section "Removing Configurations: $component"
    
    if ! remove_component_symlinks "$component"; then
        return 1
    fi
    
    log_success "Removed configurations for component: $component"
    return 0
}

#######################################
# Utility Functions
#######################################

# List all available components
list_available_components() {
    log_section "Available Dotfiles Components"
    
    local components
    if ! components=$(discover_dotfiles_components); then
        return 1
    fi
    
    echo "$components" | while read -r component; do
        local config_count
        config_count=$(get_component_config_structure "$component" | wc -l)
        echo "  $component ($config_count configuration files)"
    done
}

# Show component configuration details
# Arguments: $1 - component name
show_component_details() {
    local component="$1"
    
    if [[ -z "$component" ]]; then
        log_error "Component name is required"
        return 1
    fi
    
    log_section "Component Details: $component"
    
    if ! has_configurations "$component"; then
        log_info "No configurations found for component: $component"
        return 0
    fi
    
    echo "Configuration mappings:"
    while IFS='|' read -r source_file target_path; do
        local status="NEW"
        if [[ -e "$target_path" ]]; then
            if [[ -L "$target_path" ]]; then
                local current_target
                current_target=$(readlink "$target_path")
                if [[ "$current_target" == "$source_file" ]]; then
                    status="LINKED"
                else
                    status="CONFLICT (symlink)"
                fi
            else
                status="CONFLICT (file)"
            fi
        fi
        
        local relative_source="${source_file#$PROJECT_ROOT/}"
        local relative_target="${target_path#$HOME/}"
        echo "  $relative_source -> ~/$relative_target [$status]"
    done < <(get_component_config_structure "$component")
}

# Validate dotfiles structure
validate_dotfiles_structure() {
    log_section "Validating Dotfiles Structure"
    
    if [[ ! -d "$DOTFILES_DIR" ]]; then
        log_error "Dotfiles directory not found: $DOTFILES_DIR"
        return 1
    fi
    
    local components
    if ! components=$(discover_dotfiles_components); then
        log_error "No valid components found in dotfiles directory"
        return 1
    fi
    
    local total_configs=0
    echo "$components" | while read -r component; do
        local config_count
        config_count=$(get_component_config_structure "$component" | wc -l)
        total_configs=$((total_configs + config_count))
        
        if [[ $config_count -eq 0 ]]; then
            log_warn "Component has no configuration files: $component"
        else
            log_info "Component $component: $config_count configuration files"
        fi
    done
    
    log_success "Dotfiles structure validation complete"
    return 0
}

# Initialize dotfiles manager
init_dotfiles_manager() {
    # Initialize logger if not already done
    if [[ -z "$LOG_FILE" ]]; then
        init_logger
    fi
    
    # Validate dotfiles directory
    if [[ ! -d "$DOTFILES_DIR" ]]; then
        log_error "Dotfiles directory not found: $DOTFILES_DIR"
        log_error "Please ensure the dotfiles directory exists and contains configuration files"
        return 1
    fi
    
    log_debug "Dotfiles manager initialized"
    log_debug "Dotfiles directory: $DOTFILES_DIR"
    log_debug "Backup directory: $BACKUP_BASE_DIR"
    
    return 0
}

# Main function for command-line usage
main() {
    local action="$1"
    shift
    
    # Initialize the dotfiles manager
    if ! init_dotfiles_manager; then
        exit 1
    fi
    
    case "$action" in
        "list")
            list_available_components
            ;;
        "show")
            show_component_details "$1"
            ;;
        "apply")
            if [[ $# -eq 0 ]]; then
                log_error "No components specified for apply action"
                exit 1
            fi
            apply_multiple_components "$@"
            ;;
        "remove")
            if [[ -z "$1" ]]; then
                log_error "Component name required for remove action"
                exit 1
            fi
            remove_component_configs "$1"
            ;;
        "validate")
            validate_dotfiles_structure
            ;;
        "backup-list")
            list_backup_sessions
            ;;
        "restore")
            if [[ -z "$1" ]]; then
                log_error "Backup session required for restore action"
                exit 1
            fi
            restore_from_backup "$1" "$2"
            ;;
        *)
            echo "Usage: $0 {list|show|apply|remove|validate|backup-list|restore} [args...]"
            echo
            echo "Commands:"
            echo "  list                    - List all available components"
            echo "  show <component>        - Show details for a specific component"
            echo "  apply <component>...    - Apply configurations for one or more components"
            echo "  remove <component>      - Remove configurations for a component"
            echo "  validate               - Validate dotfiles structure"
            echo "  backup-list            - List all backup sessions"
            echo "  restore <session> [file] - Restore from backup session"
            exit 1
            ;;
    esac
}

# Allow script to be sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi