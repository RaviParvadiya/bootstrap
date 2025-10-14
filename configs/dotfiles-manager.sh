#!/usr/bin/env bash

# configs/dotfiles-manager.sh - Dotfiles management module
# This module handles symlink creation, configuration file discovery,
# and conflict resolution for dotfiles management.

# Prevent multiple sourcing
if [[ -n "${DOTFILES_MANAGER_SOURCED:-}" ]]; then
    return 0
fi
readonly DOTFILES_MANAGER_SOURCED=1

# Initialize all project paths
source "$(dirname "${BASH_SOURCE[0]}")/../core/init-paths.sh"

# Source core utilities
source "$CORE_DIR/common.sh"
source "$CORE_DIR/logger.sh"

#######################################
# Dotfiles Discovery Functions
#######################################

# Map directory names back to component names
# Arguments: $1 - directory name
map_directory_to_component() {
    local dir_name="$1"
    
    case "$dir_name" in
        "zshrc")
            echo "zsh"
            ;;
        *)
            echo "$dir_name"
            ;;
    esac
}

# Discover all available dotfiles configurations
discover_dotfiles_components() {
    local components=()
    
    if [[ ! -d "$DOTFILES_DIR" ]]; then
        log_error "Dotfiles directory not found: $DOTFILES_DIR"
        return 1
    fi
    
    log_debug "Discovering dotfiles components in: $DOTFILES_DIR"
    
    # Find all component directories (exclude hidden files and scripts)
    while IFS= read -r -d '' dir; do
        local dir_name component_name
        dir_name=$(basename "$dir")
        
        # Skip non-component files and directories
        case "$dir_name" in
            ".*"|".git"|"install.sh"|"update.sh"|"README.md"|"TODO.txt"|"pkglist-"*|"banner")
                continue
                ;;
            *)
                component_name=$(map_directory_to_component "$dir_name")
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

# Map component names to actual directory names
# Arguments: $1 - component name
map_component_to_directory() {
    local component="$1"
    
    case "$component" in
        "zsh")
            echo "zshrc"
            ;;
        *)
            echo "$component"
            ;;
    esac
}

# Get component configuration structure
# Arguments: $1 - component name
get_component_config_structure() {
    local component="$1"
    local actual_component
    actual_component=$(map_component_to_directory "$component")
    local component_dir="$DOTFILES_DIR/$actual_component"
    
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
has_configurations() {
    local component="$1"
    local config_count
    
    config_count=$(get_component_config_structure "$component" | wc -l)
    [[ $config_count -gt 0 ]]
}

#######################################
# Conflict Resolution Functions
#######################################

# Check for configuration conflicts
# Arguments: $1 - component name
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
resolve_config_conflicts() {
    local component="$1"
    local resolution_strategy=""
    
    if ! check_config_conflicts "$component"; then
        echo
        echo "Configuration conflicts detected for component: $component"
        echo "How would you like to resolve these conflicts?"
        echo
        echo "1. Skip conflicting files and only link non-conflicting ones"
        echo "2. Overwrite existing files (dangerous)"
        echo "3. Cancel installation for this component"
        echo
        
        local choice
        choice=$(ask_choice "Select resolution strategy" \
            "Skip conflicts" \
            "Overwrite" \
            "Cancel")
        
        case "$choice" in
            "Skip conflicts")
                resolution_strategy="skip"
                ;;
            "Overwrite")
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
create_managed_symlink() {
    local source_file="$1"
    local target_path="$2"
    local resolution="${3:-skip}"
    
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
        if ! mkdir -p "$target_dir"; then
            log_error "Failed to create directory: $target_dir"
            return 1
        fi
        log_debug "Created directory: $target_dir"
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
        if ! rm -rf "$target_path"; then
            log_error "Failed to remove existing file: $target_path"
            return 1
        fi
    fi
    
    # Create the symlink
    if ! ln -s "$source_file" "$target_path"; then
        log_error "Failed to create symlink: $target_path -> $source_file"
        return 1
    fi
    log_success "Created symlink: $target_path -> $source_file"
    
    return 0
}

# Remove symlinks for a component
# Arguments: $1 - component name
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
                if rm "$target_path"; then
                    log_debug "Removed symlink: $target_path"
                    ((removed_count++))
                else
                    log_error "Failed to remove symlink: $target_path"
                    ((failed_count++))
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
apply_component_configs() {
    local component="$1"
    local resolution="${CONFLICT_RESOLUTION:-skip}"
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
        log_info "  $component ($config_count configuration files)"
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
    
    log_info "Configuration mappings:"
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
        
        local relative_source="${source_file#$SCRIPT_DIR/}"
        local relative_target="${target_path#$HOME/}"
        log_info "  $relative_source -> ~/$relative_target [$status]"
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
        *)
            echo "Usage: $0 {list|show|apply|remove|validate} [args...]"
            echo
            echo "Commands:"
            echo "  list                    - List all available components"
            echo "  show <component>        - Show details for a specific component"
            echo "  apply <component>...    - Apply configurations for one or more components"
            echo "  remove <component>      - Remove configurations for a component"
            echo "  validate               - Validate dotfiles structure"
            exit 1
            ;;
    esac
}

#######################################
# Main Dotfiles Management Function
#######################################

# Main dotfiles management function called by install.sh
# Arguments: Array of component names
manage_dotfiles() {
    local components=("$@")
    
    if [[ ${#components[@]} -eq 0 ]]; then
        log_error "No components specified for dotfiles management"
        return 1
    fi
    
    log_info "Managing dotfiles for components: ${components[*]}"
    
    # Initialize the dotfiles manager
    if ! init_dotfiles_manager; then
        return 1
    fi
    
    # Apply configurations for all specified components
    if ! apply_multiple_components "${components[@]}"; then
        log_error "Failed to apply dotfiles configurations"
        return 1
    fi
    
    log_success "Dotfiles management completed successfully"
    return 0
}

# Allow script to be sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

# Simple safe symlink creation
create_symlink_safe() {
    local source="$1"
    local destination="$2"
    local force="${3:-false}"
    
    if [[ -z "$source" || -z "$destination" ]]; then
        fail "create_symlink_safe" "Source and destination are required"
        return 1
    fi
    
    if [[ ! -e "$source" ]]; then
        fail "create_symlink_safe" "Source does not exist: $source"
        return 1
    fi
    
    # Create destination directory if needed
    local dest_dir
    dest_dir=$(dirname "$destination")
    if [[ ! -d "$dest_dir" ]]; then
        mkdir -p "$dest_dir" || {
            fail "create_symlink_safe" "Failed to create directory: $dest_dir"
            return 1
        }
    fi
    
    # Handle existing destination
    if [[ -e "$destination" || -L "$destination" ]]; then
        if [[ -L "$destination" ]]; then
            local current_target
            current_target=$(readlink "$destination")
            if [[ "$current_target" == "$source" ]]; then
                log_info "Symlink already exists and is correct: $destination"
                return 0
            fi
        fi
        
        if [[ "$force" == "true" ]]; then
            rm -f "$destination" || {
                fail "create_symlink_safe" "Failed to remove existing file: $destination"
                return 1
            }
        else
            fail "create_symlink_safe" "Destination already exists (use force=true to overwrite): $destination"
            return 1
        fi
    fi
    
    # Create the symlink
    if ln -s "$source" "$destination"; then
        log_success "Symlink created successfully: $destination -> $source"
    else
        fail "create_symlink_safe" "Failed to create symlink: $destination -> $source"
        return 1
    fi
    
    return 0
}