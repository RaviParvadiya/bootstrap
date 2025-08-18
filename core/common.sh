#!/bin/bash

# core/common.sh - Common utility functions for the modular install framework
# This module provides shared functions used across all components including
# distribution detection, internet connectivity checks, package installation,
# interactive prompts, and system validation.

# Prevent multiple sourcing
if [[ -n "${COMMON_SOURCED:-}" ]]; then
    return 0
fi
readonly COMMON_SOURCED=1

# Global variables
# Set SCRIPT_DIR to project root if not already set
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    # When sourced from core/, get the parent directory (project root)
    core_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SCRIPT_DIR="$(dirname "$core_dir")"
fi
PROJECT_ROOT="$SCRIPT_DIR"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"

# Distribution detection cache
DETECTED_DISTRO=""
DISTRO_VERSION=""
DISTRO_CODENAME=""
DISTRO_COMPATIBLE=""

#######################################
# Distribution Detection Functions
#######################################

# Detect the current Linux distribution
# Returns: Sets DETECTED_DISTRO, DISTRO_VERSION, DISTRO_CODENAME, and DISTRO_COMPATIBLE global variables
# Requirements: 1.1 - Auto-detect Arch Linux vs Ubuntu, 1.5 - Fallback handling for unsupported distributions
detect_distro() {
    if [[ -n "$DETECTED_DISTRO" ]]; then
        return 0  # Already detected
    fi

    # Initialize variables
    DETECTED_DISTRO=""
    DISTRO_VERSION=""
    DISTRO_CODENAME=""
    DISTRO_COMPATIBLE="false"

    # Primary detection method: /etc/os-release
    if [[ -f /etc/os-release ]]; then
        # Read os-release variables safely
        local id version_id version_codename id_like name
        
        # Parse /etc/os-release line by line
        while IFS='=' read -r key value; do
            # Remove quotes from value
            value=$(echo "$value" | sed 's/^"//;s/"$//')
            
            case "$key" in
                "ID") id="$value" ;;
                "VERSION_ID") version_id="$value" ;;
                "VERSION_CODENAME") version_codename="$value" ;;
                "ID_LIKE") id_like="$value" ;;
                "NAME") name="$value" ;;
            esac
        done < /etc/os-release
        
        if [[ -n "$id" ]]; then
            
            case "$id" in
                "arch")
                    DETECTED_DISTRO="arch"
                    DISTRO_VERSION="${version_id:-rolling}"
                    DISTRO_CODENAME="${version_codename:-rolling}"
                    DISTRO_COMPATIBLE="true"
                    ;;
                "ubuntu")
                    DETECTED_DISTRO="ubuntu"
                    DISTRO_VERSION="$version_id"
                    DISTRO_CODENAME="$version_codename"
                    # Check Ubuntu version compatibility (18.04+)
                    if _is_ubuntu_version_supported "$version_id"; then
                        DISTRO_COMPATIBLE="true"
                    else
                        DISTRO_COMPATIBLE="false"
                    fi
                    ;;
                "manjaro")
                    DETECTED_DISTRO="arch"  # Treat Manjaro as Arch-based
                    DISTRO_VERSION="manjaro-${version_id:-unknown}"
                    DISTRO_CODENAME="$version_codename"
                    DISTRO_COMPATIBLE="true"
                    ;;
                "endeavouros")
                    DETECTED_DISTRO="arch"  # Treat EndeavourOS as Arch-based
                    DISTRO_VERSION="endeavouros-${version_id:-unknown}"
                    DISTRO_CODENAME="$version_codename"
                    DISTRO_COMPATIBLE="true"
                    ;;
                "garuda")
                    DETECTED_DISTRO="arch"  # Treat Garuda as Arch-based
                    DISTRO_VERSION="garuda-${version_id:-unknown}"
                    DISTRO_CODENAME="$version_codename"
                    DISTRO_COMPATIBLE="true"
                    ;;
                *)
                    # Check ID_LIKE for compatibility
                    if [[ "$id_like" == *"arch"* ]]; then
                        DETECTED_DISTRO="arch"
                        DISTRO_VERSION="${id}-${version_id:-unknown}"
                        DISTRO_CODENAME="$version_codename"
                        DISTRO_COMPATIBLE="true"
                    elif [[ "$id_like" == *"ubuntu"* || "$id_like" == *"debian"* ]]; then
                        DETECTED_DISTRO="ubuntu"
                        DISTRO_VERSION="${id}-${version_id:-unknown}"
                        DISTRO_CODENAME="$version_codename"
                        DISTRO_COMPATIBLE="false"  # Only pure Ubuntu is fully supported
                    else
                        DETECTED_DISTRO="unsupported"
                        DISTRO_VERSION="${id:-unknown}-${version_id:-unknown}"
                        DISTRO_CODENAME="$version_codename"
                        DISTRO_COMPATIBLE="false"
                    fi
                    ;;
            esac
        fi
    fi

    # Fallback detection methods if /etc/os-release failed
    if [[ -z "$DETECTED_DISTRO" || "$DETECTED_DISTRO" == "unsupported" ]]; then
        _fallback_distro_detection
    fi

    # Final validation and logging
    if [[ "$VERBOSE" == "true" ]]; then
        echo "Detected distribution: $DETECTED_DISTRO"
        echo "Version: $DISTRO_VERSION"
        echo "Codename: $DISTRO_CODENAME"
        echo "Compatible: $DISTRO_COMPATIBLE"
    fi

    return 0
}

# Check if Ubuntu version is supported (18.04 LTS and newer)
# Arguments: $1 - Ubuntu version (e.g., "20.04", "22.04")
# Returns: 0 if supported, 1 if not supported
_is_ubuntu_version_supported() {
    local version="$1"
    
    if [[ -z "$version" ]]; then
        return 1
    fi

    # Extract major and minor version numbers
    local major minor
    IFS='.' read -r major minor <<< "$version"
    
    # Support Ubuntu 18.04 and newer
    if [[ $major -gt 18 ]] || [[ $major -eq 18 && $minor -ge 4 ]]; then
        return 0
    fi
    
    return 1
}

# Fallback distribution detection using various system indicators
# Sets global variables if detection is successful
_fallback_distro_detection() {
    # Method 1: Check for package managers
    if command -v pacman >/dev/null 2>&1; then
        DETECTED_DISTRO="arch"
        DISTRO_VERSION="unknown"
        DISTRO_CODENAME="unknown"
        DISTRO_COMPATIBLE="true"
        return 0
    elif command -v apt >/dev/null 2>&1; then
        DETECTED_DISTRO="ubuntu"
        DISTRO_VERSION="unknown"
        DISTRO_CODENAME="unknown"
        DISTRO_COMPATIBLE="false"  # Can't verify version compatibility
        return 0
    fi

    # Method 2: Check for distribution-specific files
    if [[ -f /etc/arch-release ]]; then
        DETECTED_DISTRO="arch"
        DISTRO_VERSION="unknown"
        DISTRO_CODENAME="unknown"
        DISTRO_COMPATIBLE="true"
        return 0
    elif [[ -f /etc/lsb-release ]]; then
        # Try to parse LSB release info
        if grep -q "Ubuntu" /etc/lsb-release 2>/dev/null; then
            DETECTED_DISTRO="ubuntu"
            DISTRO_VERSION=$(grep "DISTRIB_RELEASE" /etc/lsb-release 2>/dev/null | cut -d'=' -f2 | tr -d '"')
            DISTRO_CODENAME=$(grep "DISTRIB_CODENAME" /etc/lsb-release 2>/dev/null | cut -d'=' -f2 | tr -d '"')
            
            if _is_ubuntu_version_supported "$DISTRO_VERSION"; then
                DISTRO_COMPATIBLE="true"
            else
                DISTRO_COMPATIBLE="false"
            fi
            return 0
        fi
    fi

    # Method 3: Check /proc/version
    if [[ -f /proc/version ]]; then
        if grep -qi "arch" /proc/version; then
            DETECTED_DISTRO="arch"
            DISTRO_VERSION="unknown"
            DISTRO_CODENAME="unknown"
            DISTRO_COMPATIBLE="true"
            return 0
        elif grep -qi "ubuntu" /proc/version; then
            DETECTED_DISTRO="ubuntu"
            DISTRO_VERSION="unknown"
            DISTRO_CODENAME="unknown"
            DISTRO_COMPATIBLE="false"
            return 0
        fi
    fi

    # If all methods fail, mark as unsupported
    DETECTED_DISTRO="unsupported"
    DISTRO_VERSION="unknown"
    DISTRO_CODENAME="unknown"
    DISTRO_COMPATIBLE="false"
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

# Get the distribution codename
# Returns: Echoes the distribution codename
get_distro_codename() {
    detect_distro
    echo "$DISTRO_CODENAME"
}

# Check if current distribution is supported
# Returns: 0 if supported, 1 if unsupported
is_supported_distro() {
    detect_distro
    [[ "$DISTRO_COMPATIBLE" == "true" ]]
}

# Check if current distribution is compatible (may work but not fully tested)
# Returns: 0 if compatible, 1 if incompatible
is_compatible_distro() {
    local distro
    distro=$(get_distro)
    [[ "$distro" == "arch" || "$distro" == "ubuntu" ]]
}

# Get detailed distribution information
# Returns: Echoes formatted distribution information
get_distro_info() {
    detect_distro
    echo "Distribution: $DETECTED_DISTRO"
    echo "Version: $DISTRO_VERSION"
    echo "Codename: $DISTRO_CODENAME"
    echo "Fully Supported: $DISTRO_COMPATIBLE"
}

# Handle unsupported distribution with user-friendly error message
# Requirements: 1.5 - Display error message and exit gracefully for unsupported distributions
handle_unsupported_distro() {
    local distro version
    distro=$(get_distro)
    version=$(get_distro_version)
    
    echo "=============================================="
    echo "UNSUPPORTED DISTRIBUTION DETECTED"
    echo "=============================================="
    echo
    echo "Distribution: $distro"
    echo "Version: $version"
    echo
    echo "This installation framework currently supports:"
    echo "  • Arch Linux (and Arch-based distributions)"
    echo "  • Ubuntu 18.04 LTS and newer"
    echo
    echo "Detected system information:"
    get_distro_info
    echo
    
    if [[ "$distro" == "ubuntu" && "$DISTRO_COMPATIBLE" == "false" ]]; then
        echo "Your Ubuntu version may be too old or could not be verified."
        echo "Please ensure you are running Ubuntu 18.04 LTS or newer."
        echo
        if ask_yes_no "Would you like to continue anyway? (not recommended)" "n"; then
            echo "Continuing with limited support..."
            return 0
        fi
    elif [[ "$distro" != "unsupported" ]]; then
        echo "Your distribution might be compatible but is not officially supported."
        echo "You may encounter issues during installation."
        echo
        if ask_yes_no "Would you like to continue anyway? (not recommended)" "n"; then
            echo "Continuing with limited support..."
            return 0
        fi
    fi
    
    echo "Installation aborted."
    echo
    echo "For support with additional distributions, please:"
    echo "  • Check the project documentation"
    echo "  • Submit a feature request on GitHub"
    echo "  • Consider using a supported distribution"
    echo
    return 1
}

# Validate distribution compatibility and handle unsupported cases
# Returns: 0 if can proceed, 1 if should abort
# Requirements: 1.1, 1.5 - Auto-detect and handle unsupported distributions
validate_distro_support() {
    detect_distro
    
    if is_supported_distro; then
        if [[ "$VERBOSE" == "true" ]]; then
            echo "Distribution validation passed: $(get_distro) $(get_distro_version)"
        fi
        return 0
    fi
    
    # Handle unsupported distribution
    if ! handle_unsupported_distro; then
        return 1
    fi
    
    return 0
}

#######################################
# Internet Connectivity Functions
#######################################

# Check internet connectivity by testing multiple endpoints
# This function tests connectivity to multiple reliable endpoints to ensure
# internet access is available for package downloads and repository updates.
# 
# Arguments: None
# Returns: 0 if connected, 1 if not connected
# Global Variables: None modified
# Requirements: 10.4 - System validation functions
# 
# Usage Examples:
#   if check_internet; then
#       echo "Internet connection available"
#   else
#       echo "No internet connection"
#   fi
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

# Universal package installation wrapper that works across distributions
# This function provides a unified interface for package installation across
# different Linux distributions, automatically detecting the appropriate package
# manager and handling distribution-specific installation procedures.
# 
# Arguments: 
#   $1 - package name (required): Name of the package to install
#   $2 - package manager (optional): Specific package manager to use
#        Valid values: "auto" (default), "pacman", "apt", "yay", "paru"
#        "auto" will detect the appropriate package manager automatically
# 
# Returns: 
#   0 if package installation successful
#   1 if package installation failed
# 
# Global Variables: 
#   DRY_RUN - If "true", only shows what would be installed
#   VERBOSE - If "true", shows detailed installation output
# 
# Requirements: 1.1 - Universal package installation
# 
# Usage Examples:
#   install_package "git"                    # Auto-detect package manager
#   install_package "firefox" "apt"         # Force APT usage
#   install_package "yay-bin" "yay"         # Install AUR package
#   
#   # Check if installation was successful
#   if install_package "neovim"; then
#       echo "Neovim installed successfully"
#   else
#       echo "Failed to install Neovim"
#   fi
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
        log_dry_run "Install package: $package" "using $pm"
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

# Interactive yes/no confirmation prompt with default option support
# This function displays a user-friendly prompt and waits for user input.
# It supports default values and handles various input formats gracefully.
# In dry-run mode, it automatically returns the default or assumes "yes".
# 
# Arguments:
#   $1 - prompt message (required): The question to ask the user
#   $2 - default answer (optional): Default response if user presses Enter
#        Valid values: "y", "yes", "n", "no" (case insensitive)
#        If not provided, user must explicitly choose
# 
# Returns:
#   0 for yes/y/Y responses
#   1 for no/n/N responses
# 
# Global Variables:
#   DRY_RUN - If "true", automatically returns the default or 0 if no default
# 
# Requirements: 1.1 - Interactive confirmation prompts
# 
# Usage Examples:
#   # Simple yes/no question
#   if ask_yes_no "Do you want to continue?"; then
#       echo "User chose yes"
#   fi
#   
#   # With default value
#   if ask_yes_no "Install NVIDIA drivers?" "y"; then
#       install_nvidia_drivers
#   fi
#   
#   # With default no
#   if ask_yes_no "Delete existing config?" "n"; then
#       rm -rf ~/.config/app
#   fi
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

# Create safe symlink with automatic backup of existing files
# This function creates symbolic links while safely handling existing files
# by creating timestamped backups. It ensures no data loss during configuration
# deployment and provides rollback capabilities.
# 
# Arguments:
#   $1 - source file (required): Path to the source file/directory to link from
#        Must be an absolute path or relative to current directory
#   $2 - target location (required): Path where the symlink should be created
#        Parent directories will be created automatically if needed
# 
# Returns:
#   0 if symlink creation successful
#   1 if symlink creation failed (missing args, source doesn't exist, etc.)
# 
# Global Variables:
#   DRY_RUN - If "true", only shows what would be done
#   HOME - Used for backup directory location
# 
# Side Effects:
#   - Creates backup directory: ~/.config/install-backups/YYYYMMDD_HHMMSS/
#   - Backs up existing target file/directory before creating symlink
#   - Creates parent directories for target if they don't exist
# 
# Requirements: 1.1 - Safe symlink creation functions
# 
# Usage Examples:
#   # Link dotfile configuration
#   create_symlink "$HOME/dotfiles/kitty" "$HOME/.config/kitty"
#   
#   # Link single configuration file
#   create_symlink "$PWD/configs/zshrc" "$HOME/.zshrc"
#   
#   # Check if symlink creation was successful
#   if create_symlink "$source" "$target"; then
#       echo "Configuration linked successfully"
#   else
#       echo "Failed to create symlink"
#   fi
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
        log_dry_run "Create symlink: $target -> $source"
        if [[ -e "$target" ]]; then
            log_dry_run "Backup existing file: $target"
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
    if ! validate_distro_support; then
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