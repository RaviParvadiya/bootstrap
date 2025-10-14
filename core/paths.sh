#!/usr/bin/env bash

#######################################
# Path Resolution Module
# 
# Centralized path resolution for the modular install framework.
# This module provides consistent path resolution regardless of where
# scripts are called from, following DRY principles.
#
# Usage:
#   source "path/to/core/paths.sh"
#   # All path variables are now available
#######################################

# Prevent multiple sourcing
if [[ -n "${PATHS_SOURCED:-}" ]]; then
    return 0
fi
readonly PATHS_SOURCED=1

#######################################
# Core Path Resolution Function
#######################################

# Resolve project root directory from any script location
# This works by finding the directory containing the main install.sh
resolve_project_root() {
    local current_script="${BASH_SOURCE[1]:-$0}"
    local current_dir="$(cd "$(dirname "$current_script")" && pwd)"
    
    # Walk up the directory tree to find install.sh
    while [[ "$current_dir" != "/" ]]; do
        if [[ -f "$current_dir/install.sh" ]]; then
            echo "$current_dir"
            return 0
        fi
        current_dir="$(dirname "$current_dir")"
    done
    
    # Fallback: if install.sh not found, assume we're in project root
    echo "$(cd "$(dirname "${BASH_SOURCE[1]:-$0}")" && pwd)"
}

#######################################
# Initialize All Project Paths
#######################################

# Get project root
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(resolve_project_root)"
fi

# Define all project paths
CORE_DIR="$SCRIPT_DIR/core"
DISTROS_DIR="$SCRIPT_DIR/distros"
COMPONENTS_DIR="$SCRIPT_DIR/components"
CONFIGS_DIR="$SCRIPT_DIR/configs"
DATA_DIR="$SCRIPT_DIR/data"
TESTS_DIR="$SCRIPT_DIR/tests"
DOCS_DIR="$SCRIPT_DIR/docs"
DOTFILES_DIR="$HOME/dotfiles"

# Export all paths for use in child processes
export SCRIPT_DIR CORE_DIR DISTROS_DIR COMPONENTS_DIR CONFIGS_DIR DATA_DIR TESTS_DIR DOCS_DIR DOTFILES_DIR

#######################################
# Path Validation
#######################################

# Validate that all required directories exist
validate_project_paths() {
    local required_dirs=("$CORE_DIR" "$CONFIGS_DIR" "$DATA_DIR")
    local missing_dirs=()
    
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            missing_dirs+=("$dir")
        fi
    done
    
    if [[ ${#missing_dirs[@]} -gt 0 ]]; then
        echo "ERROR: Missing required directories:" >&2
        printf '  %s\n' "${missing_dirs[@]}" >&2
        echo "Current SCRIPT_DIR: $SCRIPT_DIR" >&2
        return 1
    fi
    
    return 0
}

# Validate paths on source
if ! validate_project_paths; then
    echo "ERROR: Path validation failed in paths.sh" >&2
    exit 1
fi