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

init_logger() {
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local prefix="modular-install"
    [[ "$DRY_RUN" == "true" ]] && prefix="dry-run-$prefix"
    
    LOG_FILE="/tmp/$prefix-$timestamp.log"
    LOG_TO_FILE=true
    touch "$LOG_FILE"
    
    [[ "$VERBOSE" == "true" ]] && LOG_LEVEL=$LOG_DEBUG
    [[ "$DRY_RUN" == "true" ]] && log_info "Dry-run mode enabled"
    
    # Set up cleanup trap now that logging is initialized
    trap cleanup_logger EXIT
}

_log() {
    local level="$1" color="$2" prefix="$3" message="$4"
    
    [[ $level -gt $LOG_LEVEL ]] && return 0
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Output to console with color
    echo -e "${color}[$prefix]${NC} $message" >&2
    
    # Output to file without color
    [[ "$LOG_TO_FILE" == "true" ]] && echo "[$timestamp] [$prefix] $message" >> "$LOG_FILE"
}

log_error() { _log $LOG_ERROR "$RED" "ERROR" "$1"; }
log_warn() { _log $LOG_WARN "$YELLOW" "WARN" "$1"; }
log_info() { _log $LOG_INFO "$BLUE" "INFO" "$1"; }
log_success() { _log $LOG_SUCCESS "$GREEN" "SUCCESS" "$1"; }
log_debug() { _log $LOG_DEBUG "$PURPLE" "DEBUG" "$1"; }
log_custom() { _log $LOG_INFO "$1" "$2" "$3"; }

log_dry_run() {
    [[ "$DRY_RUN" != "true" ]] && return 0
    local operation="$1" details="${2:-}"
    local message="$operation"
    [[ -n "$details" ]] && message="$operation ($details)"
    _log $LOG_INFO "$CYAN" "DRY-RUN" "$message"
}

# Progress indicator for long-running operations
show_progress() {
    local message="$1" pid="$2"
    
    [[ "$DRY_RUN" == "true" ]] && { log_info "[DRY-RUN] $message"; return 0; }
    
    local spin='-\|/' i=0
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
    local current="$1" total="$2" message="${3:-Progress}" width=50
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total)) empty=$((width - filled))
    
    printf "\r$message: [%*s%*s] %d%%" $filled $empty $percentage
    printf "%*s" $filled | tr ' ' '='
    printf "%*s" $empty | tr ' ' '-'
    [[ $current -eq $total ]] && echo
}

log_section() {
    local title="$1" width=60
    local padding=$(( (width - ${#title} - 2) / 2 ))
    
    echo
    echo -e "${CYAN}$(printf '=%.0s' $(seq 1 $width))${NC}"
    echo -e "${CYAN}$(printf '%*s' $padding)$title$(printf '%*s' $padding)${NC}"
    echo -e "${CYAN}$(printf '=%.0s' $(seq 1 $width))${NC}"
    echo
}

# Simple error handling
FAILED_OPERATIONS=()

die() {
    log_error "$1"
    exit "${2:-1}"
}

fail() {
    log_error "$2"
    FAILED_OPERATIONS+=("$1: $2")
    return 1
}

show_failures() {
    [[ ${#FAILED_OPERATIONS[@]} -eq 0 ]] && return 0
    
    log_section "Failed Operations"
    printf '  - %s\n' "${FAILED_OPERATIONS[@]}"
    echo
}

# Simple compatibility stubs for the deleted error-handler functions
handle_error() {
    case "$1" in
        "critical") die "$2" ;;
        *) fail "${3:-unknown}" "$2" ;;
    esac
}

push_error_context() { log_debug "Context: $1 - $2"; }
pop_error_context() { return 0; }

# Error handler stubs
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

cleanup_logger() {
    show_failures
    [[ "$LOG_TO_FILE" == "true" && -n "$LOG_FILE" ]] && log_info "Log saved: $LOG_FILE"
}