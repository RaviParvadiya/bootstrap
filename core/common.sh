#!/usr/bin/env bash

# Common utilities for distribution detection, package management, and system validation

[[ -n "${COMMON_SOURCED:-}" ]] && return 0
readonly COMMON_SOURCED=1

[[ -z "${PATHS_SOURCED:-}" ]] && source "$(dirname "${BASH_SOURCE[0]}")/init-paths.sh"
[[ -z "${LOGGER_SOURCED:-}" ]] && source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"

# Distribution detection cache
DETECTED_DISTRO=""
DISTRO_VERSION=""
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
    DISTRO_COMPATIBLE="false"

    # Primary detection method: /etc/os-release
    if [[ -f /etc/os-release ]]; then
        local id version_id id_like
        
        # Parse /etc/os-release line by line
        while IFS='=' read -r key value; do
            value=${value//\"/}  # Remove quotes from value
            
            case "$key" in
                "ID") id="$value" ;;
                "VERSION_ID") version_id="$value" ;;
                "ID_LIKE") id_like="$value" ;;
            esac
        done < /etc/os-release
        
        if [[ -n "$id" ]]; then
            case "$id" in
                "arch")
                    DETECTED_DISTRO="arch"
                    DISTRO_VERSION="${version_id:-rolling}"
                    DISTRO_COMPATIBLE="true"
                    ;;
                "ubuntu")
                    DETECTED_DISTRO="ubuntu"
                    DISTRO_VERSION="$version_id"
                    DISTRO_COMPATIBLE=$(_is_ubuntu_version_supported "$version_id" && echo "true" || echo "false")
                    ;;
                "manjaro"|"endeavouros"|"garuda")
                    DETECTED_DISTRO="arch"
                    DISTRO_VERSION="${id}-${version_id:-unknown}"
                    DISTRO_COMPATIBLE="true"
                    ;;
                *)
                    # Check ID_LIKE for compatibility
                    if [[ "$id_like" == *"arch"* ]]; then
                        DETECTED_DISTRO="arch"
                        DISTRO_VERSION="${id}-${version_id:-unknown}"
                        DISTRO_COMPATIBLE="true"
                    elif [[ "$id_like" == *"ubuntu"* || "$id_like" == *"debian"* ]]; then
                        DETECTED_DISTRO="ubuntu"
                        DISTRO_VERSION="${id}-${version_id:-unknown}"
                        DISTRO_COMPATIBLE="false"
                    else
                        DETECTED_DISTRO="unsupported"
                        DISTRO_VERSION="${id:-unknown}-${version_id:-unknown}"
                        DISTRO_COMPATIBLE="false"
                    fi
                    ;;
            esac
        fi
    fi

    # Fallback detection methods if /etc/os-release failed
    [[ -z "$DETECTED_DISTRO" || "$DETECTED_DISTRO" == "unsupported" ]] && _fallback_distro_detection

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

# Fallback distribution detection using package managers
_fallback_distro_detection() {
    if command -v pacman >/dev/null 2>&1; then
        DETECTED_DISTRO="arch"
        DISTRO_VERSION="unknown"
        DISTRO_COMPATIBLE="true"
    elif command -v apt >/dev/null 2>&1; then
        DETECTED_DISTRO="ubuntu"
        DISTRO_VERSION="unknown"
        DISTRO_COMPATIBLE="false"
    else
        DETECTED_DISTRO="unsupported"
        DISTRO_VERSION="unknown"
        DISTRO_COMPATIBLE="false"
    fi
}

get_distro() { detect_distro; echo "$DETECTED_DISTRO"; }
get_distro_version() { detect_distro; echo "$DISTRO_VERSION"; }
is_supported_distro() { detect_distro; [[ "$DISTRO_COMPATIBLE" == "true" ]]; }

# Get detailed distribution information
get_distro_info() {
    detect_distro
    log_info "Distribution: $DETECTED_DISTRO"
    [[ -n "$DISTRO_VERSION" && "$DISTRO_VERSION" != "unknown" ]] && log_info "Version: $DISTRO_VERSION"
    log_info "Fully Supported: $DISTRO_COMPATIBLE"
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
        log_warn "Your Ubuntu version may be too old or could not be verified."
        log_warn "Please ensure you are running Ubuntu 18.04 LTS or newer."
        if ask_yes_no "Would you like to continue anyway? (not recommended)" "n"; then
            log_warn "Continuing with limited support..."
            return 0
        fi
    elif [[ "$distro" != "unsupported" ]]; then
        log_warn "Your distribution might be compatible but is not officially supported."
        log_warn "You may encounter issues during installation."
        if ask_yes_no "Would you like to continue anyway? (not recommended)" "n"; then
            log_warn "Continuing with limited support..."
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

#######################################
# Package Installation Functions
#######################################

# Install package using appropriate package manager
# Arguments: $1 - package name, $2 - package manager (optional, defaults to auto)
install_package() {
    local package="$1" pm="${2:-auto}"

    [[ -z "$package" ]] && { log_error "Package name is required"; return 1; }

    local distro=$(get_distro)
    
    if [[ "$pm" == "auto" ]]; then
        case "$distro" in
            "arch") pm="pacman" ;;
            "ubuntu") pm="apt" ;;
            *) log_error "Unsupported distribution for auto package manager detection"; return 1 ;;
        esac
    fi

    case "$pm" in
        "pacman") sudo pacman -S --noconfirm "$package" ;;
        "yay") yay -S --noconfirm "$package" ;;
        "apt") sudo apt-get update >/dev/null 2>&1 && sudo apt-get install -y "$package" ;;
        *) log_error "Unsupported package manager: $pm"; return 1 ;;
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
        log_warn "Failed to install packages: ${failed_packages[*]}"
        log_info "Successfully installed: $success_count/${#packages[@]} packages"
        return 1
    fi

    log_success "Successfully installed all $success_count packages"
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
        "yay") yay -Qi "$package" >/dev/null 2>&1 ;;
        "apt") dpkg -l "$package" >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

#######################################
# Interactive Confirmation Functions
#######################################

# Interactive yes/no prompt with default option support
# Arguments: $1 - prompt message, $2 - default answer (y/n, optional)
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
            *) log_warn "Please answer yes (y) or no (n)." ;;
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
            log_warn "Invalid choice. Please enter a number between 1 and ${#options[@]}."
        fi
    done
}

#######################################
# File and Symlink Management Functions
#######################################

# Create symlink with automatic backup of existing files
# Arguments: $1 - source file, $2 - target location
create_symlink() {
    local source="$1" target="$2"
    local backup_dir="$HOME/.config/install-backups/$(date +%Y%m%d_%H%M%S)"

    [[ -z "$source" || -z "$target" ]] && { log_error "Source and target are required for symlink creation"; return 1; }
    [[ ! -e "$source" ]] && { log_error "Source file does not exist: $source"; return 1; }

    # Create target directory if it doesn't exist
    local target_dir=$(dirname "$target")
    [[ ! -d "$target_dir" ]] && mkdir -p "$target_dir"

    # Backup existing file if it exists and is not already a symlink to our source
    if [[ -e "$target" ]]; then
        if [[ -L "$target" ]]; then
            local current_target=$(readlink "$target")
            [[ "$current_target" == "$source" ]] && { log_info "Symlink already exists and points to correct target: $target"; return 0; }
        fi

        # Create backup
        mkdir -p "$backup_dir"
        local backup_file="$backup_dir/$(basename "$target")"
        log_info "Backing up existing file: $target -> $backup_file"
        cp -r "$target" "$backup_file"
        rm -rf "$target"
    fi

    # Create the symlink
    ln -s "$source" "$target"
    log_success "Created symlink: $target -> $source"
    return 0
}

# Create multiple symlinks from a directory
# Arguments: $1 - source directory, $2 - target directory
create_symlinks_from_dir() {
    local source_dir="$1" target_dir="$2" failed_count=0

    [[ ! -d "$source_dir" ]] && { log_error "Source directory does not exist: $source_dir"; return 1; }

    # Find all files in source directory (excluding directories)
    while IFS= read -r -d '' file; do
        local relative_path="${file#$source_dir/}"
        local target_file="$target_dir/$relative_path"
        
        create_symlink "$file" "$target_file" || ((failed_count++))
    done < <(find "$source_dir" -type f -print0)

    [[ $failed_count -gt 0 ]] && { log_warn "Failed to create $failed_count symlinks"; return 1; }
    return 0
}

#######################################
# System Validation Functions
#######################################

is_root() { [[ $EUID -eq 0 ]]; }
has_sudo() { sudo -n true 2>/dev/null; }

validate_permissions() {
    if is_root; then
        log_warn "Running as root is not recommended"
        ask_yes_no "Continue anyway?" "n" || return 1
    fi

    if ! has_sudo; then
        log_error "This script requires sudo privileges"
        log_error "Please run: sudo -v"
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
                log_error "pacman not found on Arch-based system"
                return 1
            fi
            ;;
        "ubuntu")
            if command -v apt-get >/dev/null 2>&1; then
                package_manager="apt-get"
                install_cmd="sudo apt-get install -y"
            else
                log_error "apt-get not found on Ubuntu/Debian system"
                return 1
            fi
            ;;
        *)
            log_error "No supported package manager found for distribution: $distro"
            echo "This script supports:"
            echo "  • Arch Linux (pacman/yay)"
            echo "  • Ubuntu/Debian (apt)"
            return 1
            ;;
    esac

    log_info "Installing missing tools: ${missing_tools[*]}"

    # Update package database
    if [[ "$package_manager" == "apt-get" ]]; then
        log_info "Updating package database..."
        sudo apt-get update >/dev/null 2>&1
    elif [[ "$package_manager" == "pacman" ]]; then
        log_info "Updating package database..."
        sudo pacman -Sy >/dev/null 2>&1
    fi

    # Install each missing tool
    local failed_tools=()
    for tool in "${missing_tools[@]}"; do
        log_info "Installing $tool..."
        
        if eval "$install_cmd \"$tool\"" >/dev/null 2>&1; then
            log_success "Successfully installed $tool"
        else
            log_error "Failed to install $tool"
            failed_tools+=("$tool")
        fi
    done

    # Report results
    if [[ ${#failed_tools[@]} -gt 0 ]]; then
        log_error "Failed to install the following tools: ${failed_tools[*]}"
        log_error "Please install them manually and run the script again"
        return 1
    fi

    log_success "All required tools installed successfully"
    return 0
}

# Check system prerequisites
validate_system() {
    # Check if we're running as root (we shouldn't be)
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root"
        return 1
    fi
    
    # Check if we have sudo access
    if ! sudo -n true 2>/dev/null && ! sudo -v; then
        log_error "Sudo access is required but not available"
        return 1
    fi

    local missing_tools=() required_tools=("curl" "wget" "jq" "bc")

    # Check for required tools
    for tool in "${required_tools[@]}"; do
        command -v "$tool" >/dev/null 2>&1 || missing_tools+=("$tool")
    done

    # Check distribution support
    validate_distro_support || return 1

    # Check internet connectivity with retry
    local retries=3 count=0
    while [[ $count -lt $retries ]]; do
        check_internet && break
        ((count++))
        [[ $count -lt $retries ]] && {
            log_warn "Internet connectivity check failed, retrying in 2 seconds... ($count/$retries)"
            sleep 2
        }
    done
    
    if [[ $count -eq $retries ]]; then
        log_error "No internet connectivity detected"
        log_error "Internet access is required for package installation"
        return 1
    fi

    # Check disk space (require at least 2GB free)
    local available_space=$(df / | awk 'NR==2 {print $4}')
    local required_space=$((2 * 1024 * 1024))  # 2GB in KB

    if [[ $available_space -lt $required_space ]]; then
        log_error "Insufficient disk space"
        log_error "Available: $(($available_space / 1024 / 1024))GB, Required: 2GB"
        return 1
    fi

    # Install missing tools automatically
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        install_missing_tools "${missing_tools[@]}" || return 1
    fi
}

#######################################
# Utility Helper Functions
#######################################

# Source this file to make functions available
# This allows other scripts to use: source "$(dirname "$0")/core/common.sh"
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    log_error "This file should be sourced, not executed directly"
    log_error "Usage: source core/common.sh"
    exit 1
fi