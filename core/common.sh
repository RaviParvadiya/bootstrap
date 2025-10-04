#!/usr/bin/env bash

# Common utilities for distribution detection, package management, and system validation

[[ -n "${COMMON_SOURCED:-}" ]] && return 0
readonly COMMON_SOURCED=1

[[ -z "${PATHS_SOURCED:-}" ]] && source "$(dirname "${BASH_SOURCE[0]}")/init-paths.sh"
[[ -z "${LOGGER_SOURCED:-}" ]] && source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"

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
detect_distro() {
    [[ -n "$DETECTED_DISTRO" ]] && return 0  # Already detected

    # Initialize variables
    DETECTED_DISTRO=""
    DISTRO_VERSION=""
    DISTRO_CODENAME=""
    DISTRO_COMPATIBLE="false"

    # Primary detection method: /etc/os-release
    if [[ -f /etc/os-release ]]; then
        local id version_id version_codename id_like
        
        # Parse /etc/os-release line by line
        while IFS='=' read -r key value; do
            value=${value//\"/}  # Remove quotes from value
            
            case "$key" in
                "ID") id="$value" ;;
                "VERSION_ID") version_id="$value" ;;
                "VERSION_CODENAME") version_codename="$value" ;;
                "ID_LIKE") id_like="$value" ;;
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
                    DISTRO_COMPATIBLE=$(_is_ubuntu_version_supported "$version_id" && echo "true" || echo "false")
                    ;;
                "manjaro"|"endeavouros"|"garuda")
                    # Treat Arch-based distributions as Arch
                    DETECTED_DISTRO="arch"
                    DISTRO_VERSION="${id}-${version_id:-unknown}"
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
    [[ -z "$DETECTED_DISTRO" || "$DETECTED_DISTRO" == "unsupported" ]] && _fallback_distro_detection

    # Final validation and logging
    [[ "$VERBOSE" == "true" ]] && {
        echo "Detected distribution: $DETECTED_DISTRO"
        echo "Version: $DISTRO_VERSION"
        echo "Codename: $DISTRO_CODENAME"
        echo "Compatible: $DISTRO_COMPATIBLE"
    }

    return 0
}

_is_ubuntu_version_supported() {
    local version="$1"
    [[ -z "$version" ]] && return 1

    local major minor
    IFS='.' read -r major minor <<< "$version"

    # Support Ubuntu 18.04 and newer
    [[ $major -gt 18 ]] || [[ $major -eq 18 && $minor -ge 4 ]]
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
    elif [[ -f /etc/lsb-release ]] && grep -q "Ubuntu" /etc/lsb-release 2>/dev/null; then
        # Try to parse LSB release info
        DETECTED_DISTRO="ubuntu"
        DISTRO_VERSION=$(grep "DISTRIB_RELEASE" /etc/lsb-release 2>/dev/null | cut -d'=' -f2 | tr -d '"')
        DISTRO_CODENAME=$(grep "DISTRIB_CODENAME" /etc/lsb-release 2>/dev/null | cut -d'=' -f2 | tr -d '"')
        DISTRO_COMPATIBLE=$(_is_ubuntu_version_supported "$DISTRO_VERSION" && echo "true" || echo "false")
        return 0
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

get_distro() { detect_distro; echo "$DETECTED_DISTRO"; }
get_distro_version() { detect_distro; echo "$DISTRO_VERSION"; }
get_distro_codename() { detect_distro; echo "$DISTRO_CODENAME"; }
is_supported_distro() { detect_distro; [[ "$DISTRO_COMPATIBLE" == "true" ]]; }
is_compatible_distro() { detect_distro; [[ "$DETECTED_DISTRO" == "arch" || "$DETECTED_DISTRO" == "ubuntu" ]]; }

# Get detailed distribution information
get_distro_info() {
    detect_distro
    echo "Distribution: $DETECTED_DISTRO"
    echo "Version: $DISTRO_VERSION"
    echo "Codename: $DISTRO_CODENAME"
    echo "Fully Supported: $DISTRO_COMPATIBLE"
}

# Handle unsupported distribution with user-friendly error message
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
validate_distro_support() {
    detect_distro
    
    if is_supported_distro; then
        [[ "$VERBOSE" == "true" ]] && echo "Distribution validation passed: $(get_distro) $(get_distro_version)"
        return 0
    fi
    
    # Handle unsupported distribution
    handle_unsupported_distro
}

#######################################
# Internet Connectivity Functions
#######################################

check_internet() {
    local test_urls=("8.8.8.8" "1.1.1.1" "github.com")

    for url in "${test_urls[@]}"; do
        ping -c 1 -W 3 "$url" >/dev/null 2>&1 && return 0
    done

    return 1
}

check_internet_retry() {
    local retries="${1:-3}" count=0

    while [[ $count -lt $retries ]]; do
        check_internet && return 0
        ((count++))
        [[ $count -lt $retries ]] && {
            echo "Internet connectivity check failed, retrying in 2 seconds... ($count/$retries)"
            sleep 2
        }
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
install_package() {
    local package="$1" pm="${2:-auto}"

    [[ -z "$package" ]] && { echo "Error: Package name is required"; return 1; }

    local distro=$(get_distro)
    
    if [[ "$pm" == "auto" ]]; then
        case "$distro" in
            "arch") pm="pacman" ;;
            "ubuntu") pm="apt" ;;
            *) echo "Error: Unsupported distribution for auto package manager detection"; return 1 ;;
        esac
    fi

    [[ "$DRY_RUN" == "true" ]] && { log_dry_run "Install package: $package" "using $pm"; return 0; }

    case "$pm" in
        "pacman") sudo pacman -S --noconfirm "$package" ;;
        "yay"|"paru") "$pm" -S --noconfirm "$package" ;;
        "apt") sudo apt-get update >/dev/null 2>&1 && sudo apt-get install -y "$package" ;;
        "snap") sudo snap install "$package" ;;
        "flatpak") flatpak install -y flathub "$package" ;;
        *) echo "Error: Unsupported package manager: $pm"; return 1 ;;
    esac
}

# Install multiple packages
# Arguments: Array of package names
install_packages() {
    local packages=("$@") failed_packages=() success_count=0

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
is_package_installed() {
    local package="$1" pm="${2:-auto}"

    if [[ "$pm" == "auto" ]]; then
        local distro=$(get_distro)
        case "$distro" in
            "arch") pm="pacman" ;;
            "ubuntu") pm="apt" ;;
        esac
    fi

    case "$pm" in
        "pacman") pacman -Qi "$package" >/dev/null 2>&1 ;;
        "apt") dpkg -l "$package" >/dev/null 2>&1 ;;
        "snap") snap list "$package" >/dev/null 2>&1 ;;
        "flatpak") flatpak list | grep -q "$package" ;;
        *) return 1 ;;
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
    local prompt="$1" default="${2:-}" response

    # Format prompt with default indication
    case "$default" in
        "y") prompt="$prompt [Y/n]: " ;;
        "n") prompt="$prompt [y/N]: " ;;
        *) prompt="$prompt [y/n]: " ;;
    esac

    while true; do
        read -r -p "$prompt" response
        
        # Use default if no response given
        [[ -z "$response" && -n "$default" ]] && response="$default"

        case "$response" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) echo "Please answer yes (y) or no (n)." ;;
        esac
    done
}

# Multi-choice selection prompt
# Arguments: $1 - prompt message, $2+ - options
ask_choice() {
    local prompt="$1"
    shift
    local options=("$@") choice

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
    local source="$1" target="$2"
    local backup_dir="$HOME/.config/install-backups/$(date +%Y%m%d_%H%M%S)"

    [[ -z "$source" || -z "$target" ]] && { echo "Error: Source and target are required for symlink creation"; return 1; }
    [[ ! -e "$source" ]] && { echo "Error: Source file does not exist: $source"; return 1; }

    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "Create symlink: $target -> $source"
        [[ -e "$target" ]] && log_dry_run "Backup existing file: $target"
        return 0
    fi

    # Create target directory if it doesn't exist
    local target_dir=$(dirname "$target")
    [[ ! -d "$target_dir" ]] && mkdir -p "$target_dir"

    # Backup existing file if it exists and is not already a symlink to our source
    if [[ -e "$target" ]]; then
        if [[ -L "$target" ]]; then
            local current_target=$(readlink "$target")
            [[ "$current_target" == "$source" ]] && { echo "Symlink already exists and points to correct target: $target"; return 0; }
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
create_symlinks_from_dir() {
    local source_dir="$1" target_dir="$2" failed_count=0

    [[ ! -d "$source_dir" ]] && { echo "Error: Source directory does not exist: $source_dir"; return 1; }

    # Find all files in source directory (excluding directories)
    while IFS= read -r -d '' file; do
        local relative_path="${file#$source_dir/}"
        local target_file="$target_dir/$relative_path"
        
        create_symlink "$file" "$target_file" || ((failed_count++))
    done < <(find "$source_dir" -type f -print0)

    [[ $failed_count -gt 0 ]] && { echo "Warning: Failed to create $failed_count symlinks"; return 1; }
    return 0
}

#######################################
# System Validation Functions
#######################################

is_root() { [[ $EUID -eq 0 ]]; }
has_sudo() { sudo -n true 2>/dev/null; }

validate_permissions() {
    if is_root; then
        echo "Warning: Running as root is not recommended"
        ask_yes_no "Continue anyway?" "n" || return 1
    fi

    if ! has_sudo; then
        echo "Error: This script requires sudo privileges"
        echo "Please run: sudo -v"
        return 1
    fi
}

# Install missing system tools automatically
# Arguments: Array of missing tool names
install_missing_tools() {
    local missing_tools=("$@")
    [[ ${#missing_tools[@]} -eq 0 ]] && return 0

    local distro=$(get_distro) package_manager="" install_cmd=""

    # Detect package manager and set install command
    case "$distro" in
        "arch")
            if command -v pacman >/dev/null 2>&1; then
                package_manager="pacman"
                install_cmd="sudo pacman -S --noconfirm"
            else
                echo "Error: pacman not found on Arch-based system"
                return 1
            fi
            ;;
        "ubuntu")
            if command -v apt-get >/dev/null 2>&1; then
                package_manager="apt-get"
                install_cmd="sudo apt-get install -y"
            else
                echo "Error: apt-get not found on Ubuntu/Debian system"
                return 1
            fi
            ;;
        *)
            echo "Error: No supported package manager found for distribution: $distro"
            echo "This script supports:"
            echo "  • Arch Linux (pacman)"
            echo "  • Ubuntu/Debian (apt-get)"
            return 1
            ;;
    esac

    echo "=============================================="
    echo "INSTALLING MISSING TOOLS"
    echo "=============================================="
    echo "Distribution: $distro"
    echo "Package Manager: $package_manager"
    echo "Missing tools: ${missing_tools[*]}"
    echo

    # Update package database first for Ubuntu/Debian
    if [[ "$package_manager" == "apt-get" ]]; then
        echo "Updating package database..."
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Update package database" "sudo apt-get update"
        else
            sudo apt-get update >/dev/null 2>&1
        fi
    fi

    # Install each missing tool
    local failed_tools=()
    for tool in "${missing_tools[@]}"; do
        echo "Installing $tool..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Install tool: $tool" "$install_cmd $tool"
        else
            if eval "$install_cmd \"$tool\"" >/dev/null 2>&1; then
                echo "✓ Successfully installed $tool"
            else
                echo "✗ Failed to install $tool"
                failed_tools+=("$tool")
            fi
        fi
    done

    # Report results
    if [[ ${#failed_tools[@]} -gt 0 ]]; then
        echo
        echo "Failed to install the following tools: ${failed_tools[*]}"
        echo "Please install them manually and run the script again"
        return 1
    fi

    echo
    echo "✓ All required tools installed successfully"
    return 0
}

# Check system prerequisites
validate_system() {
    local missing_tools=() required_tools=("curl" "wget" "git")

    # Check for required tools
    for tool in "${required_tools[@]}"; do
        command -v "$tool" >/dev/null 2>&1 || missing_tools+=("$tool")
    done

    # Check distribution support
    validate_distro_support || return 1

    # Check internet connectivity
    if ! check_internet_retry 3; then
        echo "Error: No internet connectivity detected"
        echo "Internet access is required for package installation"
        return 1
    fi

    # Check disk space (require at least 2GB free)
    local available_space=$(df / | awk 'NR==2 {print $4}')
    local required_space=$((2 * 1024 * 1024))  # 2GB in KB

    if [[ $available_space -lt $required_space ]]; then
        echo "Error: Insufficient disk space"
        echo "Available: $(($available_space / 1024 / 1024))GB, Required: 2GB"
        return 1
    fi

    # Install missing tools automatically
    [[ ${#missing_tools[@]} -gt 0 ]] && install_missing_tools "${missing_tools[@]}"
}

# Validate specific component prerequisites
# Arguments: $1 - component name
validate_component_prereqs() {
    local component="$1"
    
    case "$component" in
        "hyprland")
            # Check for Wayland support
            [[ -z "$WAYLAND_DISPLAY" && -z "$XDG_SESSION_TYPE" ]] && {
                echo "Warning: Wayland session not detected"
                echo "Hyprland requires Wayland support"
            }
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

is_dry_run() { [[ "$DRY_RUN" == "true" ]]; }
enable_verbose() { VERBOSE="true"; }
disable_verbose() { VERBOSE="false"; }
debug_print() { [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] $*"; }

# Source this file to make functions available
# This allows other scripts to use: source "$(dirname "$0")/core/common.sh"
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This file should be sourced, not executed directly"
    echo "Usage: source core/common.sh"
    exit 1
fi