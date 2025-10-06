#!/usr/bin/env bash

# core/recovery-system.sh - Simple checkpoint system for basic recovery
# Provides minimal checkpoint functionality for package installation and dotfiles

# Prevent multiple sourcing
if [[ -n "${RECOVERY_SYSTEM_SOURCED:-}" ]]; then
    return 0
fi
readonly RECOVERY_SYSTEM_SOURCED=1

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

# Simple checkpoint directory
CHECKPOINT_DIR="/tmp/install-checkpoints"

# Initialize recovery system
init_recovery_system() {
    mkdir -p "$CHECKPOINT_DIR"
    log_debug "Recovery system initialized with checkpoint dir: $CHECKPOINT_DIR"
}

# Create a simple checkpoint
create_checkpoint() {
    local name="$1"
    local description="${2:-Checkpoint: $name}"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    
    local checkpoint_file="$CHECKPOINT_DIR/${name}_${timestamp}.txt"
    
    {
        echo "Checkpoint: $name"
        echo "Description: $description"
        echo "Timestamp: $(date -Iseconds)"
        echo "Working Directory: $(pwd)"
        echo "User: $(whoami)"
        echo "Distribution: $(get_distro 2>/dev/null || echo 'unknown')"
    } > "$checkpoint_file"
    
    log_debug "Created checkpoint: $name ($checkpoint_file)"
}

# Clean up old checkpoints
cleanup_old_checkpoints() {
    local keep_count="${1:-5}"
    
    if [[ -d "$CHECKPOINT_DIR" ]]; then
        # Keep only the most recent checkpoints
        find "$CHECKPOINT_DIR" -name "*.txt" -type f | sort -r | tail -n +$((keep_count + 1)) | xargs rm -f 2>/dev/null || true
        log_debug "Cleaned up old checkpoints, keeping $keep_count most recent"
    fi
}

# Export functions for compatibility
export -f init_recovery_system
export -f create_checkpoint
export -f cleanup_old_checkpoints