#!/usr/bin/env bash

# core/error-handler.sh - Comprehensive error handling and recovery system
# Provides categorized error handling, graceful degradation, and rollback capabilities
# Requirements: 10.1, 10.2, 6.2

# Prevent multiple sourcing
if [[ -n "${ERROR_HANDLER_SOURCED:-}" ]]; then
    return 0
fi
readonly ERROR_HANDLER_SOURCED=1

# Initialize all project paths (only if not already initialized)
if [[ -z "${PATHS_SOURCED:-}" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/init-paths.sh"
fi

# Only source if not already sourced
if [[ -z "${COMMON_SOURCED:-}" ]]; then
    source "$CORE_DIR/common.sh"
fi
if [[ -z "${LOGGER_SOURCED:-}" ]]; then
    source "$CORE_DIR/logger.sh"
fi

# Global error handling configuration
ERROR_LOG_FILE=""
ERROR_RECOVERY_MODE="${ERROR_RECOVERY_MODE:-graceful}"  # graceful, strict, interactive
ERROR_ROLLBACK_ENABLED="${ERROR_ROLLBACK_ENABLED:-true}"
ERROR_CONTEXT_STACK=()
FAILED_OPERATIONS=()
RECOVERY_ACTIONS=()
ROLLBACK_STACK=()

# Error categories and their handling policies
declare -gA ERROR_CATEGORIES=(
    ["critical"]="stop"      # Stop execution immediately
    ["package"]="continue"   # Continue with remaining operations
    ["config"]="rollback"    # Attempt rollback and continue
    ["network"]="retry"      # Retry operation with backoff
    ["permission"]="prompt"  # Prompt user for action
    ["validation"]="warn"    # Log warning and continue
)

# Error severity levels
readonly ERROR_FATAL=1
readonly ERROR_CRITICAL=2
readonly ERROR_MAJOR=3
readonly ERROR_MINOR=4
readonly ERROR_WARNING=5

#######################################
# Error Handler Initialization
#######################################

# Initialize error handling system
# Arguments: $1 - error log file path (optional)
init_error_handler() {
    local log_file="${1:-}"
    
    # Set up error log file
    if [[ -n "$log_file" ]]; then
        ERROR_LOG_FILE="$log_file"
    else
        local timestamp
        timestamp=$(date +%Y%m%d_%H%M%S)
        ERROR_LOG_FILE="/tmp/modular-install-errors-$timestamp.log"
    fi
    
    # Create error log file
    touch "$ERROR_LOG_FILE"
    
    # Set up error traps
    set -eE  # Exit on error and inherit ERR trap
    trap 'handle_unexpected_error $? $LINENO "$BASH_COMMAND"' ERR
    trap 'cleanup_error_handler' EXIT
    
    # Initialize error context
    push_error_context "system" "Error handler initialization"
    
    log_debug "Error handler initialized with log file: $ERROR_LOG_FILE"
    log_debug "Error recovery mode: $ERROR_RECOVERY_MODE"
    log_debug "Rollback enabled: $ERROR_ROLLBACK_ENABLED"
}

# Set error recovery mode
# Arguments: $1 - mode (graceful, strict, interactive)
set_error_recovery_mode() {
    local mode="$1"
    
    case "$mode" in
        "graceful"|"strict"|"interactive")
            ERROR_RECOVERY_MODE="$mode"
            log_debug "Error recovery mode set to: $mode"
            ;;
        *)
            log_error "Invalid error recovery mode: $mode"
            return 1
            ;;
    esac
}

# Enable or disable rollback functionality
# Arguments: $1 - true/false
set_rollback_enabled() {
    local enabled="$1"
    
    if [[ "$enabled" == "true" || "$enabled" == "false" ]]; then
        ERROR_ROLLBACK_ENABLED="$enabled"
        log_debug "Rollback functionality set to: $enabled"
    else
        log_error "Invalid rollback setting: $enabled (use true/false)"
        return 1
    fi
}

#######################################
# Error Context Management
#######################################

# Push error context onto stack
# Arguments: $1 - operation type, $2 - description
push_error_context() {
    local operation="$1"
    local description="$2"
    local timestamp
    timestamp=$(date -Iseconds)
    
    ERROR_CONTEXT_STACK+=("$timestamp|$operation|$description")
    log_debug "Pushed error context: $operation - $description"
}

# Pop error context from stack
pop_error_context() {
    if [[ ${#ERROR_CONTEXT_STACK[@]} -gt 0 ]]; then
        local context="${ERROR_CONTEXT_STACK[-1]}"
        unset 'ERROR_CONTEXT_STACK[-1]'
        log_debug "Popped error context: $context"
        echo "$context"
    fi
}

# Get current error context
get_current_context() {
    if [[ ${#ERROR_CONTEXT_STACK[@]} -gt 0 ]]; then
        echo "${ERROR_CONTEXT_STACK[-1]}"
    else
        echo "$(date -Iseconds)|unknown|No context available"
    fi
}

# Get full error context stack
get_error_context_stack() {
    printf '%s\n' "${ERROR_CONTEXT_STACK[@]}"
}

#######################################
# Core Error Handling Functions
#######################################

# Handle categorized errors with appropriate response
# Arguments: $1 - category, $2 - message, $3 - operation, $4 - severity (optional)
handle_error() {
    local category="$1"
    local message="$2"
    local operation="${3:-unknown}"
    local severity="${4:-$ERROR_MAJOR}"
    local timestamp
    timestamp=$(date -Iseconds)
    
    # Log error to file
    echo "[$timestamp] [$category] [$operation] $message" >> "$ERROR_LOG_FILE"
    
    # Get current context
    local context
    context=$(get_current_context)
    local context_desc="${context##*|}"
    
    # Log error with context
    case "$severity" in
        "$ERROR_FATAL"|"$ERROR_CRITICAL")
            log_error "[$category] $message (in: $context_desc)"
            ;;
        "$ERROR_MAJOR")
            log_error "[$category] $message (in: $context_desc)"
            ;;
        "$ERROR_MINOR")
            log_warn "[$category] $message (in: $context_desc)"
            ;;
        "$ERROR_WARNING")
            log_warn "[$category] $message (in: $context_desc)"
            ;;
    esac
    
    # Record failed operation
    FAILED_OPERATIONS+=("$timestamp|$category|$operation|$message")
    
    # Handle based on category and recovery mode
    local action="${ERROR_CATEGORIES[$category]:-continue}"
    
    case "$action" in
        "stop")
            handle_critical_error "$category" "$message" "$operation"
            ;;
        "continue")
            handle_continuable_error "$category" "$message" "$operation"
            ;;
        "rollback")
            handle_rollback_error "$category" "$message" "$operation"
            ;;
        "retry")
            handle_retry_error "$category" "$message" "$operation"
            ;;
        "prompt")
            handle_interactive_error "$category" "$message" "$operation"
            ;;
        "warn")
            handle_warning_error "$category" "$message" "$operation"
            ;;
        *)
            log_warn "Unknown error handling action: $action"
            handle_continuable_error "$category" "$message" "$operation"
            ;;
    esac
    
    return 1
}

# Handle critical errors that require immediate stop
handle_critical_error() {
    local category="$1"
    local message="$2"
    local operation="$3"
    
    log_error "CRITICAL ERROR: $message"
    log_error "Operation: $operation"
    log_error "Category: $category"
    
    # Show error context
    show_error_context
    
    # Attempt emergency rollback if enabled
    if [[ "$ERROR_ROLLBACK_ENABLED" == "true" ]]; then
        log_info "Attempting emergency rollback..."
        if perform_emergency_rollback; then
            log_success "Emergency rollback completed"
        else
            log_error "Emergency rollback failed"
        fi
    fi
    
    # Show recovery suggestions
    show_recovery_suggestions "$category" "$operation"
    
    # Exit with error code
    cleanup_and_exit 1
}

# Handle errors that allow continuation
handle_continuable_error() {
    local category="$1"
    local message="$2"
    local operation="$3"
    
    log_warn "Continuing after error: $message"
    
    # Add to recovery actions for later review
    RECOVERY_ACTIONS+=("continue|$category|$operation|$message")
    
    # In strict mode, treat as critical
    if [[ "$ERROR_RECOVERY_MODE" == "strict" ]]; then
        handle_critical_error "$category" "$message" "$operation"
        return 1
    fi
    
    return 0
}

# Handle errors that require rollback
handle_rollback_error() {
    local category="$1"
    local message="$2"
    local operation="$3"
    
    if [[ "$ERROR_ROLLBACK_ENABLED" == "true" ]]; then
        log_info "Attempting rollback for operation: $operation"
        
        if perform_operation_rollback "$operation"; then
            log_success "Rollback successful for: $operation"
            RECOVERY_ACTIONS+=("rollback_success|$category|$operation|$message")
            return 0
        else
            log_error "Rollback failed for: $operation"
            RECOVERY_ACTIONS+=("rollback_failed|$category|$operation|$message")
            
            # Escalate to critical if rollback fails
            handle_critical_error "$category" "Rollback failed: $message" "$operation"
            return 1
        fi
    else
        log_warn "Rollback disabled, continuing with error: $message"
        handle_continuable_error "$category" "$message" "$operation"
        return 0
    fi
}

# Handle errors that should be retried
handle_retry_error() {
    local category="$1"
    local message="$2"
    local operation="$3"
    local max_retries=3
    local retry_delay=2
    
    # Check if we have retry context
    local retry_count=0
    local retry_key="retry_$operation"
    
    # Get retry count from environment (simple retry tracking)
    if [[ -n "${!retry_key:-}" ]]; then
        retry_count="${!retry_key}"
    fi
    
    if [[ $retry_count -lt $max_retries ]]; then
        ((retry_count++))
        export "$retry_key=$retry_count"
        
        log_info "Retrying operation ($retry_count/$max_retries): $operation"
        log_info "Waiting $retry_delay seconds before retry..."
        
        if [[ "$DRY_RUN" != "true" ]]; then
            sleep $retry_delay
        fi
        
        RECOVERY_ACTIONS+=("retry|$category|$operation|$message|attempt_$retry_count")
        return 2  # Special return code indicating retry
    else
        log_error "Max retries exceeded for operation: $operation"
        unset "$retry_key"
        handle_critical_error "$category" "Max retries exceeded: $message" "$operation"
        return 1
    fi
}

# Handle errors requiring user interaction
handle_interactive_error() {
    local category="$1"
    local message="$2"
    local operation="$3"
    
    if [[ "$ERROR_RECOVERY_MODE" == "interactive" ]]; then
        log_error "Interactive error resolution required"
        log_error "Error: $message"
        log_error "Operation: $operation"
        
        echo
        echo "How would you like to proceed?"
        echo "1. Continue (ignore error)"
        echo "2. Retry operation"
        echo "3. Skip this operation"
        echo "4. Abort installation"
        
        if [[ "$ERROR_ROLLBACK_ENABLED" == "true" ]]; then
            echo "5. Rollback and continue"
        fi
        
        local choice
        read -r -p "Enter your choice (1-5): " choice
        
        case "$choice" in
            1)
                log_info "User chose to continue"
                RECOVERY_ACTIONS+=("user_continue|$category|$operation|$message")
                return 0
                ;;
            2)
                log_info "User chose to retry"
                RECOVERY_ACTIONS+=("user_retry|$category|$operation|$message")
                return 2
                ;;
            3)
                log_info "User chose to skip"
                RECOVERY_ACTIONS+=("user_skip|$category|$operation|$message")
                return 0
                ;;
            4)
                log_info "User chose to abort"
                handle_critical_error "$category" "User aborted: $message" "$operation"
                return 1
                ;;
            5)
                if [[ "$ERROR_ROLLBACK_ENABLED" == "true" ]]; then
                    log_info "User chose rollback"
                    handle_rollback_error "$category" "$message" "$operation"
                    return $?
                else
                    log_error "Invalid choice: $choice"
                    handle_interactive_error "$category" "$message" "$operation"
                    return $?
                fi
                ;;
            *)
                log_error "Invalid choice: $choice"
                handle_interactive_error "$category" "$message" "$operation"
                return $?
                ;;
        esac
    else
        # Non-interactive mode, treat as continuable
        log_warn "Interactive error in non-interactive mode, continuing"
        handle_continuable_error "$category" "$message" "$operation"
        return 0
    fi
}

# Handle warning-level errors
handle_warning_error() {
    local category="$1"
    local message="$2"
    local operation="$3"
    
    log_warn "Warning: $message (operation: $operation)"
    RECOVERY_ACTIONS+=("warning|$category|$operation|$message")
    return 0
}

#######################################
# Specific Error Type Handlers
#######################################

# Handle package installation errors
# Arguments: $1 - package name, $2 - error message, $3 - package manager
handle_package_error() {
    local package="$1"
    local error_msg="$2"
    local package_manager="${3:-unknown}"
    
    push_error_context "package" "Installing package: $package"
    
    local full_message="Failed to install package '$package' using $package_manager: $error_msg"
    handle_error "package" "$full_message" "install_package_$package"
    
    pop_error_context
}

# Handle configuration file errors
# Arguments: $1 - config file, $2 - error message, $3 - operation type
handle_config_error() {
    local config_file="$1"
    local error_msg="$2"
    local operation="${3:-config}"
    
    push_error_context "config" "Processing config: $config_file"
    
    local full_message="Configuration error for '$config_file': $error_msg"
    handle_error "config" "$full_message" "${operation}_config_$(basename "$config_file")"
    
    pop_error_context
}

# Handle network-related errors
# Arguments: $1 - operation, $2 - error message, $3 - url/resource (optional)
handle_network_error() {
    local operation="$1"
    local error_msg="$2"
    local resource="${3:-unknown}"
    
    push_error_context "network" "Network operation: $operation"
    
    local full_message="Network error during '$operation' (resource: $resource): $error_msg"
    handle_error "network" "$full_message" "network_$operation"
    
    pop_error_context
}

# Handle permission-related errors
# Arguments: $1 - operation, $2 - path/resource, $3 - error message
handle_permission_error() {
    local operation="$1"
    local resource="$2"
    local error_msg="$3"
    
    push_error_context "permission" "Permission operation: $operation"
    
    local full_message="Permission error for '$operation' on '$resource': $error_msg"
    handle_error "permission" "$full_message" "permission_$operation"
    
    pop_error_context
}

# Handle validation errors
# Arguments: $1 - validation type, $2 - error message, $3 - component (optional)
handle_validation_error() {
    local validation_type="$1"
    local error_msg="$2"
    local component="${3:-system}"
    
    push_error_context "validation" "Validating: $validation_type"
    
    local full_message="Validation error for '$validation_type' in '$component': $error_msg"
    handle_error "validation" "$full_message" "validate_${validation_type}_$component"
    
    pop_error_context
}

#######################################
# Rollback System
#######################################

# Register rollback action
# Arguments: $1 - operation name, $2 - rollback command, $3 - description
register_rollback_action() {
    local operation="$1"
    local rollback_cmd="$2"
    local description="$3"
    local timestamp
    timestamp=$(date -Iseconds)
    
    ROLLBACK_STACK+=("$timestamp|$operation|$rollback_cmd|$description")
    log_debug "Registered rollback action for: $operation"
}

# Perform rollback for specific operation
# Arguments: $1 - operation name
perform_operation_rollback() {
    local target_operation="$1"
    local rollback_performed=false
    
    log_info "Performing rollback for operation: $target_operation"
    
    # Find and execute rollback actions in reverse order
    for ((i=${#ROLLBACK_STACK[@]}-1; i>=0; i--)); do
        local entry="${ROLLBACK_STACK[i]}"
        local operation="${entry#*|}"
        operation="${operation%%|*}"
        
        if [[ "$operation" == "$target_operation" ]]; then
            local rollback_cmd="${entry#*|*|}"
            rollback_cmd="${rollback_cmd%%|*}"
            local description="${entry##*|}"
            
            log_info "Executing rollback: $description"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would execute rollback: $rollback_cmd"
                rollback_performed=true
            else
                if eval "$rollback_cmd"; then
                    log_success "Rollback successful: $description"
                    rollback_performed=true
                else
                    log_error "Rollback failed: $description"
                    return 1
                fi
            fi
            
            # Remove executed rollback action
            unset 'ROLLBACK_STACK[i]'
        fi
    done
    
    if [[ "$rollback_performed" == "true" ]]; then
        return 0
    else
        log_warn "No rollback actions found for operation: $target_operation"
        return 1
    fi
}

# Perform emergency rollback of all operations
perform_emergency_rollback() {
    log_info "Performing emergency rollback of all operations..."
    
    local rollback_count=0
    local failed_rollbacks=0
    
    # Execute all rollback actions in reverse order
    for ((i=${#ROLLBACK_STACK[@]}-1; i>=0; i--)); do
        local entry="${ROLLBACK_STACK[i]}"
        local rollback_cmd="${entry#*|*|}"
        rollback_cmd="${rollback_cmd%%|*}"
        local description="${entry##*|}"
        
        log_info "Emergency rollback: $description"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would execute emergency rollback: $rollback_cmd"
            ((rollback_count++))
        else
            if eval "$rollback_cmd"; then
                log_success "Emergency rollback successful: $description"
                ((rollback_count++))
            else
                log_error "Emergency rollback failed: $description"
                ((failed_rollbacks++))
            fi
        fi
    done
    
    if [[ $failed_rollbacks -eq 0 ]]; then
        log_success "Emergency rollback completed successfully ($rollback_count actions)"
        return 0
    else
        log_error "Emergency rollback completed with $failed_rollbacks failures ($rollback_count successful)"
        return 1
    fi
}

# Clear rollback stack
clear_rollback_stack() {
    ROLLBACK_STACK=()
    log_debug "Rollback stack cleared"
}

#######################################
# Error Reporting and Recovery
#######################################

# Show current error context
show_error_context() {
    if [[ ${#ERROR_CONTEXT_STACK[@]} -gt 0 ]]; then
        log_info "Error context stack:"
        for ((i=${#ERROR_CONTEXT_STACK[@]}-1; i>=0; i--)); do
            local context="${ERROR_CONTEXT_STACK[i]}"
            local timestamp="${context%%|*}"
            local operation="${context#*|}"
            operation="${operation%%|*}"
            local description="${context##*|}"
            
            echo "  [$timestamp] $operation: $description"
        done
    else
        log_info "No error context available"
    fi
}

# Show recovery suggestions based on error category
# Arguments: $1 - error category, $2 - operation
show_recovery_suggestions() {
    local category="$1"
    local operation="$2"
    
    log_info "Recovery suggestions for $category error in $operation:"
    
    case "$category" in
        "critical")
            echo "  - Check system logs: journalctl -xe"
            echo "  - Verify system integrity: sudo fsck -f /"
            echo "  - Restart the installation with --dry-run first"
            echo "  - Contact support with error log: $ERROR_LOG_FILE"
            ;;
        "package")
            echo "  - Update package databases: sudo pacman -Sy (Arch) or sudo apt update (Ubuntu)"
            echo "  - Check available disk space: df -h"
            echo "  - Verify internet connectivity: ping google.com"
            echo "  - Try installing packages manually"
            ;;
        "config")
            echo "  - Check file permissions: ls -la <config_file>"
            echo "  - Verify configuration syntax"
            echo "  - Restore from backup if available"
            echo "  - Reset to default configuration"
            ;;
        "network")
            echo "  - Check internet connectivity: ping google.com"
            echo "  - Verify DNS resolution: nslookup google.com"
            echo "  - Check firewall settings"
            echo "  - Try using different mirror/repository"
            ;;
        "permission")
            echo "  - Check user permissions: id"
            echo "  - Verify sudo access: sudo -v"
            echo "  - Check file/directory ownership: ls -la"
            echo "  - Run with appropriate privileges"
            ;;
        *)
            echo "  - Check the error log for details: $ERROR_LOG_FILE"
            echo "  - Try running with --verbose for more information"
            echo "  - Use --dry-run to preview operations"
            ;;
    esac
    
    echo
}

# Generate error report
generate_error_report() {
    local report_file="${1:-/tmp/modular-install-error-report-$(date +%Y%m%d_%H%M%S).txt}"
    
    log_info "Generating error report: $report_file"
    
    cat > "$report_file" << EOF
# Modular Install Framework - Error Report
# Generated: $(date -Iseconds)
# System: $(uname -a)
# Distribution: $(get_distro) $(get_distro_version)

## Error Summary
Total failed operations: ${#FAILED_OPERATIONS[@]}
Recovery actions taken: ${#RECOVERY_ACTIONS[@]}
Rollback actions available: ${#ROLLBACK_STACK[@]}

## Failed Operations
EOF
    
    if [[ ${#FAILED_OPERATIONS[@]} -gt 0 ]]; then
        printf '%s\n' "${FAILED_OPERATIONS[@]}" >> "$report_file"
    else
        echo "None" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

## Recovery Actions
EOF
    
    if [[ ${#RECOVERY_ACTIONS[@]} -gt 0 ]]; then
        printf '%s\n' "${RECOVERY_ACTIONS[@]}" >> "$report_file"
    else
        echo "None" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

## Error Context Stack
EOF
    
    if [[ ${#ERROR_CONTEXT_STACK[@]} -gt 0 ]]; then
        printf '%s\n' "${ERROR_CONTEXT_STACK[@]}" >> "$report_file"
    else
        echo "None" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

## Available Rollback Actions
EOF
    
    if [[ ${#ROLLBACK_STACK[@]} -gt 0 ]]; then
        printf '%s\n' "${ROLLBACK_STACK[@]}" >> "$report_file"
    else
        echo "None" >> "$report_file"
    fi
    
    # Append error log if it exists
    if [[ -f "$ERROR_LOG_FILE" ]]; then
        cat >> "$report_file" << EOF

## Detailed Error Log
EOF
        cat "$ERROR_LOG_FILE" >> "$report_file"
    fi
    
    log_success "Error report generated: $report_file"
    echo "$report_file"
}

# Show error summary
show_error_summary() {
    log_info "=== Error Handling Summary ==="
    echo
    echo "Failed operations: ${#FAILED_OPERATIONS[@]}"
    echo "Recovery actions: ${#RECOVERY_ACTIONS[@]}"
    echo "Available rollbacks: ${#ROLLBACK_STACK[@]}"
    echo "Error log: $ERROR_LOG_FILE"
    echo
    
    if [[ ${#FAILED_OPERATIONS[@]} -gt 0 ]]; then
        echo "Recent failures:"
        for ((i=${#FAILED_OPERATIONS[@]}-1; i>=0 && i>=${#FAILED_OPERATIONS[@]}-5; i--)); do
            local entry="${FAILED_OPERATIONS[i]}"
            local timestamp="${entry%%|*}"
            local category="${entry#*|}"
            category="${category%%|*}"
            local operation="${entry#*|*|}"
            operation="${operation%%|*}"
            local message="${entry##*|}"
            
            echo "  [$timestamp] [$category] $operation: $message"
        done
        echo
    fi
    
    if [[ ${#RECOVERY_ACTIONS[@]} -gt 0 ]]; then
        echo "Recent recovery actions:"
        for ((i=${#RECOVERY_ACTIONS[@]}-1; i>=0 && i>=${#RECOVERY_ACTIONS[@]}-5; i--)); do
            echo "  - ${RECOVERY_ACTIONS[i]}"
        done
        echo
    fi
}

#######################################
# Unexpected Error Handler
#######################################

# Handle unexpected errors (trap handler)
# Arguments: $1 - exit code, $2 - line number, $3 - command
handle_unexpected_error() {
    local exit_code="$1"
    local line_number="$2"
    local command="$3"
    
    # Disable error trap to prevent recursion
    set +eE
    trap - ERR
    
    log_error "Unexpected error occurred!"
    log_error "Exit code: $exit_code"
    log_error "Line: $line_number"
    log_error "Command: $command"
    
    # Get current context
    local context
    context=$(get_current_context)
    log_error "Context: ${context##*|}"
    
    # Show error context
    show_error_context
    
    # Handle as critical error
    handle_critical_error "critical" "Unexpected error: $command (exit code: $exit_code)" "unexpected_error_line_$line_number"
}

#######################################
# Cleanup and Finalization
#######################################

# Cleanup error handler resources
cleanup_error_handler() {
    # Generate final error report if there were errors
    if [[ ${#FAILED_OPERATIONS[@]} -gt 0 || ${#RECOVERY_ACTIONS[@]} -gt 0 ]]; then
        show_error_summary
        
        if ask_yes_no "Generate detailed error report?" "y"; then
            generate_error_report
        fi
    fi
    
    # Clear error context
    ERROR_CONTEXT_STACK=()
    
    log_debug "Error handler cleanup completed"
}

# Clean exit with error code
# Arguments: $1 - exit code
cleanup_and_exit() {
    local exit_code="${1:-1}"
    
    log_info "Cleaning up and exiting with code: $exit_code"
    
    # Manual cleanup call removed because EXIT trap already runs cleanup_error_handler
    # cleanup_error_handler
    
    # Exit with specified code
    exit "$exit_code"
}

#######################################
# Utility Functions
#######################################

# Check if operation has failed before
# Arguments: $1 - operation name
has_operation_failed() {
    local operation="$1"
    
    for failed_op in "${FAILED_OPERATIONS[@]}"; do
        if [[ "$failed_op" =~ \|$operation\| ]]; then
            return 0
        fi
    done
    
    return 1
}

# Get failure count for operation
# Arguments: $1 - operation name
get_operation_failure_count() {
    local operation="$1"
    local count=0
    
    for failed_op in "${FAILED_OPERATIONS[@]}"; do
        if [[ "$failed_op" =~ \|$operation\| ]]; then
            ((count++))
        fi
    done
    
    echo "$count"
}

# Reset error state for operation
# Arguments: $1 - operation name
reset_operation_errors() {
    local operation="$1"
    local temp_failed=()
    
    for failed_op in "${FAILED_OPERATIONS[@]}"; do
        if [[ ! "$failed_op" =~ \|$operation\| ]]; then
            temp_failed+=("$failed_op")
        fi
    done
    
    FAILED_OPERATIONS=("${temp_failed[@]}")
    log_debug "Reset error state for operation: $operation"
}

# Export functions for use in other modules
export -f init_error_handler
export -f set_error_recovery_mode
export -f set_rollback_enabled
export -f push_error_context
export -f pop_error_context
export -f handle_error
export -f handle_package_error
export -f handle_config_error
export -f handle_network_error
export -f handle_permission_error
export -f handle_validation_error
export -f register_rollback_action
export -f perform_operation_rollback
export -f perform_emergency_rollback
export -f show_error_summary
export -f generate_error_report
export -f cleanup_and_exit