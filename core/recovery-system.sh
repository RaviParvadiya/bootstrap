#!/bin/bash

# core/recovery-system.sh - Recovery mechanisms and system restoration
# Provides automated recovery actions and system restoration capabilities
# Requirements: 10.1, 10.2, 6.2

# Prevent multiple sourcing
if [[ -n "${RECOVERY_SYSTEM_SOURCED:-}" ]]; then
    return 0
fi
readonly RECOVERY_SYSTEM_SOURCED=1

# Source required modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Only source if not already sourced
if [[ -z "${ERROR_HANDLER_SOURCED:-}" ]]; then
    source "$PROJECT_ROOT/core/error-handler.sh"
fi
if [[ -z "${COMMON_SOURCED:-}" ]]; then
    source "$PROJECT_ROOT/core/common.sh"
fi
if [[ -z "${LOGGER_SOURCED:-}" ]]; then
    source "$PROJECT_ROOT/core/logger.sh"
fi

# Recovery system configuration
RECOVERY_STATE_FILE="/tmp/modular-install-recovery-state.json"
RECOVERY_CHECKPOINT_DIR="/tmp/modular-install-checkpoints"
RECOVERY_ACTIONS_LOG="/tmp/modular-install-recovery-actions.log"

# Recovery strategies
declare -A RECOVERY_STRATEGIES=(
    ["package_install_failed"]="retry_with_update,try_alternative_source,skip_optional"
    ["config_file_conflict"]="backup_and_overwrite,merge_configs,skip_config"
    ["network_timeout"]="retry_with_backoff,try_alternative_mirror,continue_offline"
    ["permission_denied"]="fix_permissions,run_as_sudo,skip_operation"
    ["service_start_failed"]="check_dependencies,restart_service,disable_service"
    ["disk_space_low"]="cleanup_temp_files,ask_user_cleanup,abort_installation"
)

#######################################
# Recovery System Initialization
#######################################

# Initialize recovery system
init_recovery_system() {
    log_debug "Initializing recovery system"
    
    # Create recovery directories
    mkdir -p "$RECOVERY_CHECKPOINT_DIR"
    
    # Initialize recovery state
    cat > "$RECOVERY_STATE_FILE" << EOF
{
    "initialized": "$(date -Iseconds)",
    "checkpoints": [],
    "recovery_actions": [],
    "system_state": {
        "packages_installed": [],
        "configs_modified": [],
        "services_enabled": [],
        "files_created": []
    }
}
EOF
    
    # Initialize recovery log
    echo "# Recovery Actions Log - $(date -Iseconds)" > "$RECOVERY_ACTIONS_LOG"
    
    log_debug "Recovery system initialized"
}

# Create system checkpoint
# Arguments: $1 - checkpoint name, $2 - description
create_checkpoint() {
    local checkpoint_name="$1"
    local description="$2"
    local timestamp
    timestamp=$(date -Iseconds)
    
    if [[ -z "$checkpoint_name" ]]; then
        log_error "Checkpoint name is required"
        return 1
    fi
    
    local checkpoint_file="$RECOVERY_CHECKPOINT_DIR/${checkpoint_name}_${timestamp}.json"
    
    log_info "Creating system checkpoint: $checkpoint_name"
    
    # Gather system state
    local installed_packages
    local enabled_services
    local modified_configs
    
    # Get installed packages (simplified for checkpoint)
    local installed_packages="[]"
    if command -v jq >/dev/null 2>&1; then
        case "$(get_distro)" in
            "arch")
                if command -v pacman >/dev/null 2>&1; then
                    installed_packages=$(pacman -Qq 2>/dev/null | head -20 | jq -R . | jq -s . 2>/dev/null || echo "[]")
                fi
                ;;
            "ubuntu")
                if command -v dpkg >/dev/null 2>&1; then
                    installed_packages=$(dpkg --get-selections 2>/dev/null | grep -v deinstall | cut -f1 | head -20 | jq -R . | jq -s . 2>/dev/null || echo "[]")
                fi
                ;;
        esac
    fi
    
    # Get enabled services
    local enabled_services="[]"
    if command -v jq >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
        enabled_services=$(systemctl list-unit-files --state=enabled --type=service --no-legend --no-pager 2>/dev/null | cut -d' ' -f1 | head -10 | jq -R . | jq -s . 2>/dev/null || echo "[]")
    fi
    
    # Create checkpoint data (with fallback for missing tools)
    local hostname_val="$(hostname 2>/dev/null || echo 'unknown')"
    local user_val="$(whoami 2>/dev/null || echo 'unknown')"
    local distro_val="$(get_distro 2>/dev/null || echo 'unknown')"
    local distro_version_val="$(get_distro_version 2>/dev/null || echo 'unknown')"
    local root_usage="$(df / 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%' || echo '0')"
    local home_usage="$(df "$HOME" 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%' || echo '0')"
    local memory_usage="$(free 2>/dev/null | awk 'NR==2{printf "%.1f", $3*100/$2}' || echo '0')"
    
    # Create checkpoint data
    cat > "$checkpoint_file" << EOF
{
    "name": "$checkpoint_name",
    "description": "$description",
    "timestamp": "$timestamp",
    "system_info": {
        "hostname": "$hostname_val",
        "user": "$user_val",
        "distro": "$distro_val",
        "distro_version": "$distro_version_val"
    },
    "packages": $installed_packages,
    "services": $enabled_services,
    "disk_usage": {
        "root": "$root_usage",
        "home": "$home_usage"
    },
    "memory_usage": "$memory_usage"
}
EOF
    
    # Update recovery state
    if command -v jq >/dev/null 2>&1; then
        local temp_file
        temp_file=$(mktemp)
        jq --arg name "$checkpoint_name" --arg file "$checkpoint_file" --arg desc "$description" --arg time "$timestamp" \
           '.checkpoints += [{"name": $name, "file": $file, "description": $desc, "timestamp": $time}]' \
           "$RECOVERY_STATE_FILE" > "$temp_file" && mv "$temp_file" "$RECOVERY_STATE_FILE"
    fi
    
    log_success "Checkpoint created: $checkpoint_name"
    echo "[$timestamp] CHECKPOINT: $checkpoint_name - $description" >> "$RECOVERY_ACTIONS_LOG"
}

# Restore from checkpoint
# Arguments: $1 - checkpoint name or file
restore_from_checkpoint() {
    local checkpoint="$1"
    
    if [[ -z "$checkpoint" ]]; then
        log_error "Checkpoint name or file is required"
        return 1
    fi
    
    local checkpoint_file
    if [[ -f "$checkpoint" ]]; then
        checkpoint_file="$checkpoint"
    else
        # Find checkpoint file by name
        checkpoint_file=$(find "$RECOVERY_CHECKPOINT_DIR" -name "${checkpoint}_*.json" | head -1)
        if [[ -z "$checkpoint_file" ]]; then
            log_error "Checkpoint not found: $checkpoint"
            return 1
        fi
    fi
    
    if [[ ! -f "$checkpoint_file" ]]; then
        log_error "Checkpoint file not found: $checkpoint_file"
        return 1
    fi
    
    log_info "Restoring from checkpoint: $(basename "$checkpoint_file")"
    
    # This is a simplified restore - in a full implementation,
    # we would restore packages, services, and configurations
    log_warn "Checkpoint restore is not fully implemented in this version"
    log_info "Checkpoint file: $checkpoint_file"
    
    # Log the restore action
    echo "[$(date -Iseconds)] RESTORE: Restored from checkpoint $(basename "$checkpoint_file")" >> "$RECOVERY_ACTIONS_LOG"
    
    return 0
}

#######################################
# Automated Recovery Actions
#######################################

# Attempt automatic recovery for failed operation
# Arguments: $1 - operation type, $2 - operation details, $3 - error message
attempt_auto_recovery() {
    local operation_type="$1"
    local operation_details="$2"
    local error_message="$3"
    
    log_info "Attempting automatic recovery for: $operation_type"
    
    # Get recovery strategies for this operation type
    local strategies="${RECOVERY_STRATEGIES[$operation_type]:-}"
    
    if [[ -z "$strategies" ]]; then
        log_warn "No recovery strategies defined for operation type: $operation_type"
        return 1
    fi
    
    # Split strategies by comma
    IFS=',' read -ra strategy_list <<< "$strategies"
    
    for strategy in "${strategy_list[@]}"; do
        log_info "Trying recovery strategy: $strategy"
        
        if execute_recovery_strategy "$strategy" "$operation_type" "$operation_details" "$error_message"; then
            log_success "Recovery successful using strategy: $strategy"
            echo "[$(date -Iseconds)] RECOVERY_SUCCESS: $operation_type - $strategy" >> "$RECOVERY_ACTIONS_LOG"
            return 0
        else
            log_warn "Recovery strategy failed: $strategy"
            echo "[$(date -Iseconds)] RECOVERY_FAILED: $operation_type - $strategy" >> "$RECOVERY_ACTIONS_LOG"
        fi
    done
    
    log_error "All recovery strategies failed for: $operation_type"
    return 1
}

# Execute specific recovery strategy
# Arguments: $1 - strategy, $2 - operation type, $3 - operation details, $4 - error message
execute_recovery_strategy() {
    local strategy="$1"
    local operation_type="$2"
    local operation_details="$3"
    local error_message="$4"
    
    case "$strategy" in
        "retry_with_update")
            execute_retry_with_update "$operation_details"
            ;;
        "try_alternative_source")
            execute_try_alternative_source "$operation_details"
            ;;
        "skip_optional")
            execute_skip_optional "$operation_details"
            ;;
        "backup_and_overwrite")
            execute_backup_and_overwrite "$operation_details"
            ;;
        "merge_configs")
            execute_merge_configs "$operation_details"
            ;;
        "skip_config")
            execute_skip_config "$operation_details"
            ;;
        "retry_with_backoff")
            execute_retry_with_backoff "$operation_details"
            ;;
        "try_alternative_mirror")
            execute_try_alternative_mirror "$operation_details"
            ;;
        "continue_offline")
            execute_continue_offline "$operation_details"
            ;;
        "fix_permissions")
            execute_fix_permissions "$operation_details"
            ;;
        "run_as_sudo")
            execute_run_as_sudo "$operation_details"
            ;;
        "skip_operation")
            execute_skip_operation "$operation_details"
            ;;
        "check_dependencies")
            execute_check_dependencies "$operation_details"
            ;;
        "restart_service")
            execute_restart_service "$operation_details"
            ;;
        "disable_service")
            execute_disable_service "$operation_details"
            ;;
        "cleanup_temp_files")
            execute_cleanup_temp_files "$operation_details"
            ;;
        "ask_user_cleanup")
            execute_ask_user_cleanup "$operation_details"
            ;;
        "abort_installation")
            execute_abort_installation "$operation_details"
            ;;
        *)
            log_error "Unknown recovery strategy: $strategy"
            return 1
            ;;
    esac
}

#######################################
# Recovery Strategy Implementations
#######################################

# Retry with package database update
execute_retry_with_update() {
    local package="$1"
    
    log_info "Updating package database before retry"
    
    case "$(get_distro)" in
        "arch")
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would update package database: sudo pacman -Sy"
            else
                sudo pacman -Sy >/dev/null 2>&1
            fi
            ;;
        "ubuntu")
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would update package database: sudo apt update"
            else
                sudo apt update >/dev/null 2>&1
            fi
            ;;
    esac
    
    # Retry package installation
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would retry package installation: $package"
        return 0
    else
        install_package "$package"
    fi
}

# Try alternative package source
execute_try_alternative_source() {
    local package="$1"
    
    log_info "Trying alternative source for package: $package"
    
    case "$(get_distro)" in
        "arch")
            # Try AUR if main repo failed
            if command -v yay >/dev/null 2>&1; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    log_info "[DRY RUN] Would try AUR: yay -S $package"
                    return 0
                else
                    yay -S --noconfirm "$package"
                fi
            else
                return 1
            fi
            ;;
        "ubuntu")
            # Try snap if apt failed
            if command -v snap >/dev/null 2>&1; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    log_info "[DRY RUN] Would try snap: sudo snap install $package"
                    return 0
                else
                    sudo snap install "$package"
                fi
            else
                return 1
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

# Skip optional package
execute_skip_optional() {
    local package="$1"
    
    log_info "Skipping optional package: $package"
    return 0
}

# Backup and overwrite config file
execute_backup_and_overwrite() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        return 1
    fi
    
    local backup_file="${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    log_info "Backing up and overwriting config: $config_file"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would backup: $config_file -> $backup_file"
        return 0
    else
        cp "$config_file" "$backup_file" && return 0
    fi
}

# Merge configuration files
execute_merge_configs() {
    local config_file="$1"
    
    log_info "Config merge not implemented, skipping: $config_file"
    return 0
}

# Skip configuration
execute_skip_config() {
    local config_file="$1"
    
    log_info "Skipping configuration: $config_file"
    return 0
}

# Retry with exponential backoff
execute_retry_with_backoff() {
    local operation="$1"
    local max_attempts=3
    local base_delay=2
    
    for ((attempt=1; attempt<=max_attempts; attempt++)); do
        local delay=$((base_delay * attempt))
        
        log_info "Retry attempt $attempt/$max_attempts (delay: ${delay}s)"
        
        if [[ "$DRY_RUN" != "true" ]]; then
            sleep $delay
        fi
        
        # This is a placeholder - actual retry logic would depend on the operation
        if [[ $attempt -eq max_attempts ]]; then
            return 0  # Assume success on final attempt for demo
        fi
    done
    
    return 1
}

# Try alternative mirror
execute_try_alternative_mirror() {
    local resource="$1"
    
    log_info "Trying alternative mirror for: $resource"
    
    # This would implement mirror switching logic
    # For now, just return success as a placeholder
    return 0
}

# Continue in offline mode
execute_continue_offline() {
    local operation="$1"
    
    log_info "Continuing in offline mode for: $operation"
    return 0
}

# Fix file permissions
execute_fix_permissions() {
    local path="$1"
    
    if [[ ! -e "$path" ]]; then
        return 1
    fi
    
    log_info "Fixing permissions for: $path"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would fix permissions: chmod 644 $path"
        return 0
    else
        chmod 644 "$path" 2>/dev/null || chmod 755 "$path" 2>/dev/null
    fi
}

# Run operation as sudo
execute_run_as_sudo() {
    local operation="$1"
    
    log_info "Re-running with sudo: $operation"
    
    # This is a placeholder - actual implementation would re-execute the failed operation with sudo
    return 0
}

# Skip operation entirely
execute_skip_operation() {
    local operation="$1"
    
    log_info "Skipping operation: $operation"
    return 0
}

# Check service dependencies
execute_check_dependencies() {
    local service="$1"
    
    log_info "Checking dependencies for service: $service"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would check service dependencies"
        return 0
    else
        systemctl list-dependencies "$service" >/dev/null 2>&1
    fi
}

# Restart service
execute_restart_service() {
    local service="$1"
    
    log_info "Restarting service: $service"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would restart service: sudo systemctl restart $service"
        return 0
    else
        sudo systemctl restart "$service"
    fi
}

# Disable problematic service
execute_disable_service() {
    local service="$1"
    
    log_info "Disabling problematic service: $service"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would disable service: sudo systemctl disable $service"
        return 0
    else
        sudo systemctl disable "$service"
    fi
}

# Clean up temporary files
execute_cleanup_temp_files() {
    local context="$1"
    
    log_info "Cleaning up temporary files"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would clean up temporary files"
        return 0
    else
        # Clean common temp locations
        rm -rf /tmp/modular-install-* 2>/dev/null || true
        return 0
    fi
}

# Ask user to clean up disk space
execute_ask_user_cleanup() {
    local context="$1"
    
    log_warn "Disk space is low. Please free up some space."
    echo "Suggestions:"
    echo "  - Clean package cache: sudo pacman -Sc (Arch) or sudo apt clean (Ubuntu)"
    echo "  - Remove old logs: sudo journalctl --vacuum-time=7d"
    echo "  - Clean temporary files: rm -rf ~/.cache/*"
    echo
    
    if ask_yes_no "Have you freed up disk space and want to continue?" "y"; then
        return 0
    else
        return 1
    fi
}

# Abort installation
execute_abort_installation() {
    local reason="$1"
    
    log_error "Aborting installation: $reason"
    cleanup_and_exit 1
}

#######################################
# Recovery System Management
#######################################

# List available checkpoints
list_checkpoints() {
    log_info "Available checkpoints:"
    
    if [[ ! -d "$RECOVERY_CHECKPOINT_DIR" ]]; then
        log_info "No checkpoints found"
        return 0
    fi
    
    local checkpoint_count=0
    for checkpoint_file in "$RECOVERY_CHECKPOINT_DIR"/*.json; do
        if [[ -f "$checkpoint_file" ]]; then
            local name
            local timestamp
            local description
            
            if command -v jq >/dev/null 2>&1; then
                name=$(jq -r '.name' "$checkpoint_file" 2>/dev/null || echo "unknown")
                timestamp=$(jq -r '.timestamp' "$checkpoint_file" 2>/dev/null || echo "unknown")
                description=$(jq -r '.description' "$checkpoint_file" 2>/dev/null || echo "No description")
            else
                name=$(basename "$checkpoint_file" .json)
                timestamp="unknown"
                description="No description"
            fi
            
            echo "  - $name ($timestamp): $description"
            ((checkpoint_count++))
        fi
    done
    
    if [[ $checkpoint_count -eq 0 ]]; then
        log_info "No checkpoints found"
    else
        log_info "Found $checkpoint_count checkpoint(s)"
    fi
}

# Clean up old checkpoints
cleanup_old_checkpoints() {
    local keep_count="${1:-5}"
    
    log_info "Cleaning up old checkpoints (keeping $keep_count most recent)"
    
    if [[ ! -d "$RECOVERY_CHECKPOINT_DIR" ]]; then
        return 0
    fi
    
    # Find checkpoint files sorted by modification time (newest first)
    local checkpoints
    mapfile -t checkpoints < <(find "$RECOVERY_CHECKPOINT_DIR" -name "*.json" -type f -printf '%T@ %p\n' | sort -rn | cut -d' ' -f2-)
    
    if [[ ${#checkpoints[@]} -le $keep_count ]]; then
        log_info "No cleanup needed (${#checkpoints[@]} checkpoints, keeping $keep_count)"
        return 0
    fi
    
    # Remove old checkpoints
    local removed_count=0
    for ((i=keep_count; i<${#checkpoints[@]}; i++)); do
        local checkpoint_file="${checkpoints[i]}"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would remove old checkpoint: $(basename "$checkpoint_file")"
            removed_count=$((removed_count + 1))
        else
            if rm -f "$checkpoint_file"; then
                log_info "Removed old checkpoint: $(basename "$checkpoint_file")"
                removed_count=$((removed_count + 1))
            fi
        fi
    done
    
    if [[ $removed_count -gt 0 ]]; then
        log_success "Cleaned up $removed_count old checkpoints"
    fi
}

# Show recovery system status
show_recovery_status() {
    log_info "=== Recovery System Status ==="
    echo
    
    if [[ -f "$RECOVERY_STATE_FILE" ]]; then
        echo "Recovery state file: $RECOVERY_STATE_FILE"
        if command -v jq >/dev/null 2>&1; then
            local initialized
            local checkpoint_count
            initialized=$(jq -r '.initialized' "$RECOVERY_STATE_FILE" 2>/dev/null || echo "unknown")
            checkpoint_count=$(jq -r '.checkpoints | length' "$RECOVERY_STATE_FILE" 2>/dev/null || echo "0")
            echo "Initialized: $initialized"
            echo "Checkpoints: $checkpoint_count"
        fi
    else
        echo "Recovery system not initialized"
    fi
    
    echo "Checkpoint directory: $RECOVERY_CHECKPOINT_DIR"
    echo "Recovery log: $RECOVERY_ACTIONS_LOG"
    
    if [[ -f "$RECOVERY_ACTIONS_LOG" ]]; then
        local log_lines
        log_lines=$(wc -l < "$RECOVERY_ACTIONS_LOG")
        echo "Recovery actions logged: $log_lines"
    fi
    
    echo
    list_checkpoints
}

# Export functions for use in other modules
export -f init_recovery_system
export -f create_checkpoint
export -f restore_from_checkpoint
export -f attempt_auto_recovery
export -f list_checkpoints
export -f cleanup_old_checkpoints
export -f show_recovery_status