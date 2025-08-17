#!/bin/bash

# core/common.sh - Common utility functions for the modular install framework
# This module provides shared functions used across all components including
# distribution detection, internet connectivity checks, package installation,
# interactive prompts, and system validation.

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"

# Distribution detection cache
DETECTED_DISTRO=""
DISTRO_VERSION=""

#######################################
# Distribution Detection Functions
#######################################

# Detect the current Linux distribution
# Returns: Sets DETECTED_DISTRO and DISTRO_VERSION global variables
# Requirements: 1.1 - Auto-detect Arch Linux vs Ubuntu
detect_distro() {
    if [[ -n "$DETECTED_DISTRO" ]]; then
        return 0  # Already detected
    fi

    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        
        case "$ID" in
            "arch")
                DETECTED_DISTRO="arch"
                DISTRO_VERSION="$VERSION_ID"
                ;;
            "ubuntu")
                DETECTED_DISTRO="ubuntu"
                DISTRO_VERSION="$VERSION_ID"
                ;;
            "manjaro")
                DETECTED_DISTRO="arch"  # Treat Manjaro as Arch-based
                DISTRO_VERSION="manjaro-$VERSION_ID"
                ;;
            *)
                DETECTED_DISTRO="unsupported"
                DISTRO_VERSION="$VERSION_ID"
                ;;
        esac
    else
        # Fallback detection methods
        if command -v pacman >/dev/null 2>&1; then
            DETECTED_DISTRO="arch"
            DISTRO_VERSION="unknown"
        elif command -v apt >/dev/null 2>&1; then
            DETECTED_DISTRO="ubuntu"
            DISTRO_VERSION="unknown"
        else
            DETECTED_DISTRO="unsupported"
            DISTRO_VERSION="unknown"
        fi
    fi

    if [[ "$VERBOSE" == "true" ]]; then
        echo "Detected distribution: $DETECTED_DISTRO ($DISTRO_VERSION)"
    fi
}

# Get the detected distribution
# Returns: Echoes the distribution name (arch, ubuntu, or unsupported)
get_distro() {
    detect_distro
    echo "$DETECTED_DISTRO"
}

# Get the distribution version
# Returns: Echoes the distribution version
get_distro_version() {
    detect_distro
    echo "$DISTRO_VERSION"
}

# Check if current distribution is supported
# Returns: 0 if supported, 1 if unsupported
is_supported_distro() {
    local distro
    distro=$(get_distro)
    [[ "$distro" == "arch" || "$distro" == "ubuntu" ]]
}

#######################################
# Internet Connectivity Functions
#######################################

# Check internet connectivity
# Returns: 0 if connected, 1 if not connected
# Requirements: 10.4 - System validation functions
check_internet() {
    local test_urls=(
        "8.8.8.8"           # Google DNS
        "1.1.1.1"           # Cloudflare DNS
        "github.com"        # GitHub
    )

    for url in "${test_urls[@]}"; do
        if ping -c 1 -W 3 "$url" >/dev/null 2>&1; then
            return 0
        fi
    done

    return 1
}

# Check internet connectivity with retry
# Arguments: $1 - number of retries (default: 3)
# Returns: 0 if connected, 1 if failed after retries
check_internet_retry() {
    local retries="${1:-3}"
    local count=0

    while [[ $count -lt $retries ]]; do
        if check_internet; then
            return 0
        fi
        ((count++))
        if [[ $count -lt $retries ]]; then
            echo "Internet connectivity check failed, retrying in 2 seconds... ($count/$retries)"
            sleep 2
        fi
    done

    return 1
}

#######################################
# Package Installation Functions
#######################################

# Universal package installation wrapper
# Arguments: $1 - package name, $2 - package manager (optional)
# Returns: 0 if successful, 1 if failed
# Requirements: 1.1 - Universal package installation
install_package() {
    local package="$1"
    local pm="${2:-auto}"
    local distro

    if [[ -z "$package" ]]; then
        echo "Error: Package name is required"
        return 1
    fi

    distro=$(get_distro)
    
    if [[ "$pm" == "auto" ]]; then
        case "$distro" in
            "arch")
                pm="pacman"
                ;;
            "ubuntu")
                pm="apt"
                ;;
            *)
                echo "Error: Unsupported distribution for auto package manager detection"
                return 1
                ;;
        esac
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would install package: $package using $pm"
        return 0
    fi

    case "$pm" in
        "pacman")
            sudo pacman -S --noconfirm "$package"
            ;;
        "yay"|"paru")
            "$pm" -S --noconfirm "$package"
            ;;
        "apt")
            sudo apt-get update >/dev/null 2>&1
            sudo apt-get install -y "$package"
            ;;
        "snap")
            sudo snap install "$package"
            ;;
        "flatpak")
            flatpak install -y flathub "$package"
            ;;
        *)
            echo "Error: Unsupported package manager: $pm"
            return 1
            ;;
    esac
}

# Install multiple packages
# Arguments: Array of package names
# Returns: 0 if all successful, 1 if any failed
install_packages() {
    local packages=("$@")
    local failed_packages=()
    local success_count=0

    for package in "${packages[@]}"; do
        if install_package "$package"; then
            ((success_count++))
        else
            failed_packages+=("$package")
        fi
    done

    if [[ ${#failed_packages[@]} -gt 0 ]]; then
        echo "Warning: Failed to install packages: ${failed_packages[*]}"
        echo "Successfully installed: $success_count/${#packages[@]} packages"
        return 1
    fi

    echo "Successfully installed all $success_count packages"
    return 0
}

# Check if a package is installed
# Arguments: $1 - package name, $2 - package manager (optional)
# Returns: 0 if installed, 1 if not installed
is_package_installed() {
    local package="$1"
    local pm="${2:-auto}"
    local distro

    distro=$(get_distro)
    
    if [[ "$pm" == "auto" ]]; then
        case "$distro" in
            "arch")
                pm="pacman"
                ;;
            "ubuntu")
                pm="apt"
                ;;
        esac
    fi

    case "$pm" in
        "pacman")
            pacman -Qi "$package" >/dev/null 2>&1
            ;;
        "apt")
            dpkg -l "$package" >/dev/null 2>&1
            ;;
        "snap")
            snap list "$package" >/dev/null 2>&1
            ;;
        "flatpak")
            flatpak list | grep -q "$package"
            ;;
        *)
            return 1
            ;;
    esac
}

#######################################
# Interactive Confirmation Functions
#######################################

# Interactive yes/no confirmation prompt
# Arguments: $1 - prompt message, $2 - default answer (y/n, optional)
# Returns: 0 for yes, 1 for no
# Requirements: 1.1 - Interactive confirmation prompts
ask_yes_no() {
    local prompt="$1"
    local default="${2:-}"
    local response

    # Format prompt with default indication
    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    elif [[ "$default" == "n" ]]; then
        prompt="$prompt [y/N]: "
    else
        prompt="$prompt [y/n]: "
    fi

    while true; do
        read -r -p "$prompt" response
        
        # Use default if no response given
        if [[ -z "$response" && -n "$default" ]]; then
            response="$default"
        fi

        case "$response" in
            [Yy]|[Yy][Ee][Ss])
                return 0
                ;;
            [Nn]|[Nn][Oo])
                return 1
                ;;
            *)
                echo "Please answer yes (y) or no (n)."
                ;;
        esac
    done
}

# Multi-choice selection prompt
# Arguments: $1 - prompt message, $2+ - options
# Returns: Echoes the selected option
ask_choice() {
    local prompt="$1"
    shift
    local options=("$@")
    local choice

    echo "$prompt"
    for i in "${!options[@]}"; do
        echo "$((i + 1)). ${options[i]}"
    done

    while true; do
        read -r -p "Enter your choice (1-${#options[@]}): " choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#options[@]} ]]; then
            echo "${options[$((choice - 1))]}"
            return 0
        else
            echo "Invalid choice. Please enter a number between 1 and ${#options[@]}."
        fi
    done
}

#######################################
# File and Symlink Management Functions
#######################################

# Create safe symlink with backup
# Arguments: $1 - source file, $2 - target location
# Returns: 0 if successful, 1 if failed
# Requirements: 1.1 - Safe symlink creation functions
create_symlink() {
    local source="$1"
    local target="$2"
    local backup_dir="$HOME/.config/install-backups/$(date +%Y%m%d_%H%M%S)"

    if [[ -z "$source" || -z "$target" ]]; then
        echo "Error: Source and target are required for symlink creation"
        return 1
    fi

    if [[ ! -e "$source" ]]; then
        echo "Error: Source file does not exist: $source"
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would create symlink: $target -> $source"
        if [[ -e "$target" ]]; then
            echo "[DRY RUN] Would backup existing file: $target"
        fi
        return 0
    fi

    # Create target directory if it doesn't exist
    local target_dir
    target_dir=$(dirname "$target")
    if [[ ! -d "$target_dir" ]]; then
        mkdir -p "$target_dir"
    fi

    # Backup existing file if it exists and is not already a symlink to our source
    if [[ -e "$target" ]]; then
        if [[ -L "$target" ]]; then
            local current_target
            current_target=$(readlink "$target")
            if [[ "$current_target" == "$source" ]]; then
                echo "Symlink already exists and points to correct target: $target"
                return 0
            fi
        fi

        # Create backup
        mkdir -p "$backup_dir"
        local backup_file="$backup_dir/$(basename "$target")"
        echo "Backing up existing file: $target -> $backup_file"
        cp -r "$target" "$backup_file"
        rm -rf "$target"
    fi

    # Create the symlink
    ln -s "$source" "$target"
    echo "Created symlink: $target -> $source"
    return 0
}

# Create multiple symlinks from a directory
# Arguments: $1 - source directory, $2 - target directory
# Returns: 0 if all successful, 1 if any failed
create_symlinks_from_dir() {
    local source_dir="$1"
    local target_dir="$2"
    local failed_count=0

    if [[ ! -d "$source_dir" ]]; then
        echo "Error: Source directory does not exist: $source_dir"
        return 1
    fi

    # Find all files in source directory (excluding directories)
    while IFS= read -r -d '' file; do
        local relative_path="${file#$source_dir/}"
        local target_file="$target_dir/$relative_path"
        
        if ! create_symlink "$file" "$target_file"; then
            ((failed_count++))
        fi
    done < <(find "$source_dir" -type f -print0)

    if [[ $failed_count -gt 0 ]]; then
        echo "Warning: Failed to create $failed_count symlinks"
        return 1
    fi

    return 0
}

#######################################
# System Validation Functions
#######################################

# Check if running as root
# Returns: 0 if root, 1 if not root
is_root() {
    [[ $EUID -eq 0 ]]
}

# Check if user has sudo privileges
# Returns: 0 if has sudo, 1 if no sudo
# Requirements: 10.4 - Permission validation
has_sudo() {
    sudo -n true 2>/dev/null
}

# Validate user permissions
# Returns: 0 if valid, 1 if invalid
validate_permissions() {
    if is_root; then
        echo "Warning: Running as root is not recommended"
        if ! ask_yes_no "Continue anyway?" "n"; then
            return 1
        fi
    fi

    if ! has_sudo; then
        echo "Error: This script requires sudo privileges"
        echo "Please run: sudo -v"
        return 1
    fi

    return 0
}

# Check system prerequisites
# Returns: 0 if all prerequisites met, 1 if missing prerequisites
# Requirements: 10.4 - System requirements checking
validate_system() {
    local missing_tools=()
    local required_tools=("curl" "wget" "git")

    # Check for required tools
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done

    # Check distribution support
    if ! is_supported_distro; then
        echo "Error: Unsupported distribution: $(get_distro)"
        echo "Supported distributions: Arch Linux, Ubuntu"
        return 1
    fi

    # Check internet connectivity
    if ! check_internet_retry 3; then
        echo "Error: No internet connectivity detected"
        echo "Internet access is required for package installation"
        return 1
    fi

    # Check disk space (require at least 2GB free)
    local available_space
    available_space=$(df / | awk 'NR==2 {print $4}')
    local required_space=$((2 * 1024 * 1024))  # 2GB in KB

    if [[ $available_space -lt $required_space ]]; then
        echo "Error: Insufficient disk space"
        echo "Available: $(($available_space / 1024 / 1024))GB, Required: 2GB"
        return 1
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo "Error: Missing required tools: ${missing_tools[*]}"
        echo "Please install these tools before running the script"
        return 1
    fi

    return 0
}

# Validate specific component prerequisites
# Arguments: $1 - component name
# Returns: 0 if valid, 1 if invalid
validate_component_prereqs() {
    local component="$1"
    
    case "$component" in
        "hyprland")
            # Check for Wayland support
            if [[ -z "$WAYLAND_DISPLAY" && -z "$XDG_SESSION_TYPE" ]]; then
                echo "Warning: Wayland session not detected"
                echo "Hyprland requires Wayland support"
            fi
            ;;
        "nvidia")
            # Check for NVIDIA GPU
            if ! lspci | grep -i nvidia >/dev/null 2>&1; then
                echo "Warning: No NVIDIA GPU detected"
                return 1
            fi
            ;;
    esac

    return 0
}

#######################################
# Utility Helper Functions
#######################################

# Get script directory
get_script_dir() {
    echo "$SCRIPT_DIR"
}

# Get project root directory
get_project_root() {
    echo "$PROJECT_ROOT"
}

# Check if running in dry-run mode
is_dry_run() {
    [[ "$DRY_RUN" == "true" ]]
}

# Enable verbose output
enable_verbose() {
    VERBOSE="true"
}

# Disable verbose output
disable_verbose() {
    VERBOSE="false"
}

# Print debug message if verbose mode is enabled
debug_print() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[DEBUG] $*"
    fi
}

# Source this file to make functions available
# This allows other scripts to use: source "$(dirname "$0")/core/common.sh"
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This file should be sourced, not executed directly"
    echo "Usage: source core/common.sh"
    exit 1
fi