#!/usr/bin/env bash

# core/service-manager.sh - Minimal service management for compatibility
# Provides basic service management functions if needed

# Prevent multiple sourcing
if [[ -n "${SERVICE_MANAGER_SOURCED:-}" ]]; then
    return 0
fi
readonly SERVICE_MANAGER_SOURCED=1

# Initialize paths if needed
if [[ -z "${PATHS_SOURCED:-}" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/init-paths.sh"
fi

# Source dependencies
if [[ -z "${COMMON_SOURCED:-}" ]]; then
    source "$CORE_DIR/common.sh"
fi
if [[ -z "${LOGGER_SOURCED:-}" ]]; then
    source "$CORE_DIR/logger.sh"
fi

# Simple service enable function
enable_service() {
    local service_name="$1"
    
    if [[ -z "$service_name" ]]; then
        log_error "Service name is required"
        return 1
    fi
    
    log_info "Enabling service: $service_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would enable service: $service_name"
        return 0
    fi
    
    if systemctl --user enable "$service_name" 2>/dev/null || sudo systemctl enable "$service_name" 2>/dev/null; then
        log_success "Service enabled: $service_name"
        return 0
    else
        log_error "Failed to enable service: $service_name"
        return 1
    fi
}

# Simple service start function
start_service() {
    local service_name="$1"
    
    if [[ -z "$service_name" ]]; then
        log_error "Service name is required"
        return 1
    fi
    
    log_info "Starting service: $service_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would start service: $service_name"
        return 0
    fi
    
    if systemctl --user start "$service_name" 2>/dev/null || sudo systemctl start "$service_name" 2>/dev/null; then
        log_success "Service started: $service_name"
        return 0
    else
        log_error "Failed to start service: $service_name"
        return 1
    fi
}

# Export functions
export -f enable_service
export -f start_service