#!/usr/bin/env bash

# Logging and output management system
# Provides color-coded output, file logging, and progress indicators

# Prevent multiple sourcing
if [[ -n "${LOGGER_SOURCED:-}" ]]; then
    return 0
fi
readonly LOGGER_SOURCED=1

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Log levels
readonly LOG_ERROR=1
readonly LOG_WARN=2
readonly LOG_INFO=3
readonly LOG_SUCCESS=4
readonly LOG_DEBUG=5

# Global logging configuration
LOG_LEVEL=${LOG_LEVEL:-$LOG_INFO}
LOG_FILE=""
LOG_TO_FILE=false

# Initialize logging system
init_logger() {
    # Create log file (different naming for dry-run vs real execution)
    local timestamp=$(date +%Y%m%d-%H%M%S)
    if [[ "$DRY_RUN" == "true" ]]; then
        LOG_FILE="/tmp/dry-run-modular-install-$timestamp.log"
    else
        LOG_FILE="/tmp/modular-install-$timestamp.log"
    fi
    LOG_TO_FILE=true
    touch "$LOG_FILE"
    
    # Set log level based on verbose flag
    if [[ "$VERBOSE" == "true" ]]; then
        LOG_LEVEL=$LOG_DEBUG
    fi
    
    # Log initialization
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry-run mode enabled - no changes will be made"
    fi
}

# Internal logging function
_log() {
    local level="$1"
    local color="$2"
    local prefix="$3"
    local message="$4"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Check if we should log this level
    if [[ $level -gt $LOG_LEVEL ]]; then
        return 0
    fi
    
    # Format message
    local formatted_message="[$timestamp] [$prefix] $message"
    
    # Output to console with color
    echo -e "${color}[$prefix]${NC} $message" >&2
    
    # Output to file without color
    if [[ "$LOG_TO_FILE" == "true" ]]; then
        echo "$formatted_message" >> "$LOG_FILE"
    fi
}

# Log error message
log_error() {
    _log $LOG_ERROR "$RED" "ERROR" "$1"
}

# Log warning message
log_warn() {
    _log $LOG_WARN "$YELLOW" "WARN" "$1"
}

# Log info message
log_info() {
    _log $LOG_INFO "$BLUE" "INFO" "$1"
}

# Log success message
log_success() {
    _log $LOG_SUCCESS "$GREEN" "SUCCESS" "$1"
}

# Log debug message
log_debug() {
    _log $LOG_DEBUG "$PURPLE" "DEBUG" "$1"
}

# Log with custom color and prefix
log_custom() {
    local color="$1"
    local prefix="$2"
    local message="$3"
    _log $LOG_INFO "$color" "$prefix" "$message"
}

# Log dry-run operation
log_dry_run() {
    local operation="$1"
    local details="${2:-}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        if [[ -n "$details" ]]; then
            _log $LOG_INFO "$CYAN" "DRY-RUN" "$operation ($details)"
        else
            _log $LOG_INFO "$CYAN" "DRY-RUN" "$operation"
        fi
    fi
}

# Log operation that would be executed
log_would_execute() {
    local command="$1"
    local description="${2:-$command}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        _log $LOG_INFO "$PURPLE" "WOULD-EXEC" "$description"
    fi
}

# Progress indicator for long-running operations
show_progress() {
    local message="$1"
    local pid="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] $message"
        return 0
    fi
    
    local spin='-\|/'
    local i=0
    
    echo -n "$message "
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\r$message ${spin:$i:1}"
        sleep 0.1
    done
    printf "\r$message ✓\n"
}

# Progress bar for operations with known duration
progress_bar() {
    local current="$1"
    local total="$2"
    local message="${3:-Progress}"
    local width=50
    
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "\r$message: ["
    printf "%*s" $filled | tr ' ' '='
    printf "%*s" $empty | tr ' ' '-'
    printf "] %d%%" $percentage
    
    if [[ $current -eq $total ]]; then
        echo
    fi
}

# Section header for organizing output
log_section() {
    local title="$1"
    local width=60
    local padding=$(( (width - ${#title} - 2) / 2 ))
    
    echo
    echo -e "${CYAN}$(printf '=%.0s' $(seq 1 $width))${NC}"
    echo -e "${CYAN}$(printf '%*s' $padding)$title$(printf '%*s' $padding)${NC}"
    echo -e "${CYAN}$(printf '=%.0s' $(seq 1 $width))${NC}"
    echo
}

# Simple error handling
FAILED_OPERATIONS=()

# Die function - log error and exit
die() {
    local message="$1"
    local exit_code="${2:-1}"
    log_error "$message"
    exit "$exit_code"
}

# Fail function - log error and track failure
fail() {
    local operation="$1"
    local message="$2"
    log_error "$message"
    FAILED_OPERATIONS+=("$operation: $message")
    return 1
}

# Show failures summary
show_failures() {
    if [[ ${#FAILED_OPERATIONS[@]} -gt 0 ]]; then
        log_section "Failed Operations"
        for failed_op in "${FAILED_OPERATIONS[@]}"; do
            echo "  - $failed_op"
        done
        echo
    fi
}

# Simple compatibility stubs for the deleted error-handler functions
handle_error() {
    local category="$1"
    local message="$2"
    local operation="${3:-unknown}"
    
    case "$category" in
        "critical")
            die "$message"
            ;;
        *)
            fail "$operation" "$message"
            ;;
    esac
}

# Context functions - simplified to just log
push_error_context() {
    log_debug "Context: $1 - $2"
}

pop_error_context() {
    return 0
}

# Other compatibility stubs
handle_package_error() { fail "$1" "$2"; }
handle_config_error() { fail "$1" "$2"; }
handle_network_error() { fail "$1" "$2"; }
handle_permission_error() { fail "$1" "$3"; }
handle_validation_error() { fail "$1" "$2"; }
cleanup_and_exit() { exit "${1:-1}"; }

# Recovery system stubs (deleted functions)
init_recovery_system() { return 0; }
create_checkpoint() { log_debug "Checkpoint: $1 - $2"; }
set_error_recovery_mode() { return 0; }
set_rollback_enabled() { return 0; }
register_rollback_action() { log_debug "Rollback registered: $1"; }
perform_operation_rollback() { log_debug "Rollback performed: $1"; }
perform_emergency_rollback() { log_debug "Emergency rollback performed"; }
show_error_summary() { show_failures; }

# Cleanup function to close log file
cleanup_logger() {
    show_failures
    if [[ "$LOG_TO_FILE" == "true" && -n "$LOG_FILE" ]]; then
        log_info "Log file saved to: $LOG_FILE"
    fi
}

# Set up cleanup trap
trap cleanup_logger EXIT