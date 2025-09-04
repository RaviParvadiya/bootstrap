#!/usr/bin/env bash

#######################################
# Path Initialization Helper
# 
# Simple one-liner to initialize project paths from any script.
# This is the recommended way to initialize paths in all project scripts.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/../core/init-paths.sh"  # From subdirectory
#   source "$(dirname "${BASH_SOURCE[0]}")/core/init-paths.sh"     # From project root
#######################################

# Find and source the paths module
_find_and_source_paths() {
    local current_script="${BASH_SOURCE[1]:-$0}"
    local current_dir="$(cd "$(dirname "$current_script")" && pwd)"
    
    # Look for paths.sh in common locations
    local paths_locations=(
        "$current_dir/core/paths.sh"           # Same directory has core/
        "$current_dir/../core/paths.sh"        # Parent directory has core/
        "$current_dir/../../core/paths.sh"     # Grandparent has core/
    )
    
    for paths_file in "${paths_locations[@]}"; do
        if [[ -f "$paths_file" ]]; then
            source "$paths_file"
            return 0
        fi
    done
    
    echo "ERROR: Could not find core/paths.sh from $current_script" >&2
    exit 1
}

# Initialize paths if not already done
if [[ -z "${PATHS_SOURCED:-}" ]]; then
    _find_and_source_paths
fi