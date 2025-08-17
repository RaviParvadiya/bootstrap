#!/bin/bash

# Package List Management System
# Handles parsing and processing of structured package lists
# Supports comments, sections, and conditional installation

# Global variables for package management
declare -A PACKAGE_CACHE
declare -A CONDITION_CACHE
PACKAGE_LISTS_LOADED=false

# Set script directory if not already set
# When sourced from core/, BASH_SOURCE[0] points to this file in core/
# So we need to go up one level to get the project root
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    # Get the directory containing this script (core/)
    local core_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # Get the parent directory (project root)
    SCRIPT_DIR="$(dirname "$core_dir")"
fi

# Note: logger.sh and common.sh should be sourced before this file

# Initialize package management system
init_package_manager() {
    log_debug "Initializing package management system"
    
    # Clear caches
    PACKAGE_CACHE=()
    CONDITION_CACHE=()
    PACKAGE_LISTS_LOADED=false
    
    # Validate data directory exists
    if [[ ! -d "$SCRIPT_DIR/data" ]]; then
        log_error "Data directory not found: $SCRIPT_DIR/data"
        return 1
    fi
    
    log_debug "Package management system initialized"
    return 0
}

# Parse a package list file
# Usage: parse_package_list <file_path> [condition_filter]
parse_package_list() {
    local file_path="$1"
    local condition_filter="${2:-}"
    local -a packages=()
    
    if [[ ! -f "$file_path" ]]; then
        log_error "Package list file not found: $file_path"
        return 1
    fi
    
    log_debug "Parsing package list: $file_path"
    
    local line_number=0
    local current_section=""
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_number++))
        
        # Skip empty lines
        [[ -z "${line// }" ]] && continue
        
        # Skip comments, but capture section headers
        if [[ "$line" =~ ^[[:space:]]*# ]]; then
            # Check if it's a section header (format: # --- Section Name ---)
            if [[ "$line" =~ ^[[:space:]]*#[[:space:]]*---[[:space:]]*(.+)[[:space:]]*---[[:space:]]*$ ]]; then
                current_section="${BASH_REMATCH[1]}"
                log_debug "Found section: $current_section"
            fi
            continue
        fi
        
        # Remove leading/trailing whitespace
        line="${line// /}"
        
        # Parse package entry
        local package_name=""
        local package_condition=""
        local package_source="apt"  # Default source for Ubuntu
        
        # Check for source prefix (e.g., snap:package, flatpak:package)
        if [[ "$line" =~ ^([^:]+):(.+)$ ]]; then
            package_source="${BASH_REMATCH[1]}"
            line="${BASH_REMATCH[2]}"
        fi
        
        # Check for condition suffix (e.g., package|condition)
        if [[ "$line" =~ ^([^|]+)\|(.+)$ ]]; then
            package_name="${BASH_REMATCH[1]}"
            package_condition="${BASH_REMATCH[2]}"
        else
            package_name="$line"
        fi
        
        # Validate package name
        if [[ -z "$package_name" ]]; then
            log_warn "Empty package name at line $line_number in $file_path"
            continue
        fi
        
        # Apply condition filter if specified
        if [[ -n "$condition_filter" && -n "$package_condition" ]]; then
            if [[ "$package_condition" != "$condition_filter" ]]; then
                log_debug "Skipping $package_name (condition: $package_condition, filter: $condition_filter)"
                continue
            fi
        fi
        
        # Check if condition is met (if no filter specified)
        if [[ -n "$package_condition" && -z "$condition_filter" ]]; then
            if ! check_package_condition "$package_condition"; then
                log_debug "Skipping $package_name (condition not met: $package_condition)"
                continue
            fi
        fi
        
        # Add package to list with metadata
        local package_entry="$package_source:$package_name"
        if [[ -n "$current_section" ]]; then
            package_entry="$package_entry:$current_section"
        fi
        
        packages+=("$package_entry")
        log_debug "Added package: $package_name (source: $package_source, section: $current_section)"
        
    done < "$file_path"
    
    log_info "Parsed ${#packages[@]} packages from $file_path"
    
    # Output packages (one per line)
    printf '%s\n' "${packages[@]}"
    
    return 0
}

# Check if a package condition is met
# Usage: check_package_condition <condition>
check_package_condition() {
    local condition="$1"
    
    # Check cache first
    if [[ -n "${CONDITION_CACHE[$condition]:-}" ]]; then
        [[ "${CONDITION_CACHE[$condition]}" == "true" ]]
        return $?
    fi
    
    local result=false
    
    case "$condition" in
        "nvidia")
            # Check for NVIDIA GPU
            if command -v lspci >/dev/null 2>&1; then
                if lspci | grep -i nvidia >/dev/null 2>&1; then
                    result=true
                fi
            fi
            ;;
        "amd")
            # Check for AMD GPU
            if command -v lspci >/dev/null 2>&1; then
                if lspci | grep -i amd >/dev/null 2>&1; then
                    result=true
                fi
            fi
            ;;
        "gaming")
            # Check if gaming packages should be installed
            # This could be based on user selection or system capabilities
            if [[ "$DRY_RUN" == "true" ]]; then
                # In dry-run mode, default to false for gaming packages
                result=false
            elif ask_yes_no "Install gaming packages?"; then
                result=true
            fi
            ;;
        "laptop")
            # Check if running on laptop
            if [[ -d "/sys/class/power_supply" ]]; then
                if ls /sys/class/power_supply/ | grep -q "BAT"; then
                    result=true
                fi
            fi
            ;;
        "vm")
            # Check if running in virtual machine
            if [[ "$VM_MODE" == "true" ]]; then
                result=true
            elif command -v systemd-detect-virt >/dev/null 2>&1; then
                if systemd-detect-virt --quiet; then
                    result=true
                fi
            fi
            ;;
        "asus")
            # Check for ASUS hardware
            if [[ -f "/sys/class/dmi/id/board_vendor" ]]; then
                if grep -qi "asus" /sys/class/dmi/id/board_vendor 2>/dev/null; then
                    result=true
                fi
            fi
            ;;
        *)
            log_warn "Unknown condition: $condition"
            result=false
            ;;
    esac
    
    # Cache result
    CONDITION_CACHE[$condition]="$result"
    
    log_debug "Condition '$condition' evaluated to: $result"
    [[ "$result" == "true" ]]
    return $?
}

# Get packages for a specific distribution
# Usage: get_packages_for_distro <distro> [condition_filter]
get_packages_for_distro() {
    local distro="$1"
    local condition_filter="${2:-}"
    local -a all_packages=()
    
    case "$distro" in
        "arch")
            # Parse Arch packages
            if [[ -f "$SCRIPT_DIR/data/arch-packages.lst" ]]; then
                mapfile -t arch_packages < <(parse_package_list "$SCRIPT_DIR/data/arch-packages.lst" "$condition_filter")
                all_packages+=("${arch_packages[@]}")
            fi
            
            # Parse AUR packages
            if [[ -f "$SCRIPT_DIR/data/aur-packages.lst" ]]; then
                mapfile -t aur_packages < <(parse_package_list "$SCRIPT_DIR/data/aur-packages.lst" "$condition_filter")
                # Prefix AUR packages with source
                for pkg in "${aur_packages[@]}"; do
                    all_packages+=("aur:${pkg#*:}")
                done
            fi
            ;;
        "ubuntu")
            # Parse Ubuntu packages
            if [[ -f "$SCRIPT_DIR/data/ubuntu-packages.lst" ]]; then
                mapfile -t ubuntu_packages < <(parse_package_list "$SCRIPT_DIR/data/ubuntu-packages.lst" "$condition_filter")
                all_packages+=("${ubuntu_packages[@]}")
            fi
            ;;
        *)
            log_error "Unsupported distribution: $distro"
            return 1
            ;;
    esac
    
    # Output packages
    printf '%s\n' "${all_packages[@]}"
    
    return 0
}

# Get packages by source (apt, snap, flatpak, aur, etc.)
# Usage: get_packages_by_source <distro> <source> [condition_filter]
get_packages_by_source() {
    local distro="$1"
    local source="$2"
    local condition_filter="${3:-}"
    local -a filtered_packages=()
    
    # Get all packages for distro
    mapfile -t all_packages < <(get_packages_for_distro "$distro" "$condition_filter")
    
    # Filter by source
    for package_entry in "${all_packages[@]}"; do
        local pkg_source="${package_entry%%:*}"
        local pkg_name="${package_entry#*:}"
        pkg_name="${pkg_name%%:*}"  # Remove section if present
        
        if [[ "$pkg_source" == "$source" ]]; then
            filtered_packages+=("$pkg_name")
        fi
    done
    
    # Output packages
    printf '%s\n' "${filtered_packages[@]}"
    
    return 0
}

# Get packages by section
# Usage: get_packages_by_section <distro> <section> [condition_filter]
get_packages_by_section() {
    local distro="$1"
    local section="$2"
    local condition_filter="${3:-}"
    local -a filtered_packages=()
    
    # Get all packages for distro
    mapfile -t all_packages < <(get_packages_for_distro "$distro" "$condition_filter")
    
    # Filter by section
    for package_entry in "${all_packages[@]}"; do
        if [[ "$package_entry" =~ :.*:(.+)$ ]]; then
            local pkg_section="${BASH_REMATCH[1]}"
            local pkg_source="${package_entry%%:*}"
            local pkg_name="${package_entry#*:}"
            pkg_name="${pkg_name%%:*}"
            
            if [[ "$pkg_section" == "$section" ]]; then
                filtered_packages+=("$pkg_source:$pkg_name")
            fi
        fi
    done
    
    # Output packages
    printf '%s\n' "${filtered_packages[@]}"
    
    return 0
}

# Install packages using appropriate package manager
# Usage: install_packages_from_list <distro> <source> <package_list>
install_packages_from_list() {
    local distro="$1"
    local source="$2"
    shift 2
    local -a packages=("$@")
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        log_debug "No packages to install for source: $source"
        return 0
    fi
    
    log_info "Installing ${#packages[@]} packages from $source..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install packages: ${packages[*]}"
        return 0
    fi
    
    case "$distro" in
        "arch")
            case "$source" in
                "apt"|"")
                    # Use pacman for regular packages
                    sudo pacman -S --needed --noconfirm "${packages[@]}" || {
                        log_error "Failed to install some packages with pacman"
                        return 1
                    }
                    ;;
                "aur")
                    # Use AUR helper (yay or paru)
                    local aur_helper=""
                    if command -v yay >/dev/null 2>&1; then
                        aur_helper="yay"
                    elif command -v paru >/dev/null 2>&1; then
                        aur_helper="paru"
                    else
                        log_error "No AUR helper found (yay or paru required)"
                        return 1
                    fi
                    
                    $aur_helper -S --needed --noconfirm "${packages[@]}" || {
                        log_error "Failed to install some AUR packages"
                        return 1
                    }
                    ;;
                *)
                    log_error "Unsupported package source for Arch: $source"
                    return 1
                    ;;
            esac
            ;;
        "ubuntu")
            case "$source" in
                "apt"|"")
                    # Use apt for regular packages
                    sudo apt update
                    sudo apt install -y "${packages[@]}" || {
                        log_error "Failed to install some packages with apt"
                        return 1
                    }
                    ;;
                "snap")
                    # Use snap
                    for package in "${packages[@]}"; do
                        sudo snap install "$package" || {
                            log_warn "Failed to install snap package: $package"
                        }
                    done
                    ;;
                "flatpak")
                    # Use flatpak
                    for package in "${packages[@]}"; do
                        flatpak install -y flathub "$package" || {
                            log_warn "Failed to install flatpak package: $package"
                        }
                    done
                    ;;
                *)
                    log_error "Unsupported package source for Ubuntu: $source"
                    return 1
                    ;;
            esac
            ;;
        *)
            log_error "Unsupported distribution: $distro"
            return 1
            ;;
    esac
    
    log_success "Successfully installed packages from $source"
    return 0
}

# Install all packages for a distribution with optional filtering
# Usage: install_all_packages <distro> [condition_filter]
install_all_packages() {
    local distro="$1"
    local condition_filter="${2:-}"
    
    log_info "Installing all packages for $distro..."
    
    case "$distro" in
        "arch")
            # Install regular packages first
            mapfile -t regular_packages < <(get_packages_by_source "$distro" "apt" "$condition_filter")
            if [[ ${#regular_packages[@]} -gt 0 ]]; then
                install_packages_from_list "$distro" "apt" "${regular_packages[@]}"
            fi
            
            # Install AUR packages
            mapfile -t aur_packages < <(get_packages_by_source "$distro" "aur" "$condition_filter")
            if [[ ${#aur_packages[@]} -gt 0 ]]; then
                install_packages_from_list "$distro" "aur" "${aur_packages[@]}"
            fi
            ;;
        "ubuntu")
            # Install apt packages first
            mapfile -t apt_packages < <(get_packages_by_source "$distro" "apt" "$condition_filter")
            if [[ ${#apt_packages[@]} -gt 0 ]]; then
                install_packages_from_list "$distro" "apt" "${apt_packages[@]}"
            fi
            
            # Install snap packages
            mapfile -t snap_packages < <(get_packages_by_source "$distro" "snap" "$condition_filter")
            if [[ ${#snap_packages[@]} -gt 0 ]]; then
                install_packages_from_list "$distro" "snap" "${snap_packages[@]}"
            fi
            
            # Install flatpak packages
            mapfile -t flatpak_packages < <(get_packages_by_source "$distro" "flatpak" "$condition_filter")
            if [[ ${#flatpak_packages[@]} -gt 0 ]]; then
                install_packages_from_list "$distro" "flatpak" "${flatpak_packages[@]}"
            fi
            ;;
        *)
            log_error "Unsupported distribution: $distro"
            return 1
            ;;
    esac
    
    log_success "Package installation completed for $distro"
    return 0
}

# List available packages with filtering options
# Usage: list_packages <distro> [source] [section] [condition_filter]
list_packages() {
    local distro="$1"
    local source_filter="${2:-}"
    local section_filter="${3:-}"
    local condition_filter="${4:-}"
    
    echo "=== Available Packages for $distro ==="
    echo
    
    # Get all packages
    mapfile -t all_packages < <(get_packages_for_distro "$distro" "$condition_filter")
    
    # Group by source and section
    declare -A sources
    declare -A sections
    
    for package_entry in "${all_packages[@]}"; do
        local pkg_source="${package_entry%%:*}"
        local remaining="${package_entry#*:}"
        local pkg_name="${remaining%%:*}"
        local pkg_section=""
        
        if [[ "$remaining" =~ :(.+)$ ]]; then
            pkg_section="${BASH_REMATCH[1]}"
        fi
        
        # Apply filters
        if [[ -n "$source_filter" && "$pkg_source" != "$source_filter" ]]; then
            continue
        fi
        
        if [[ -n "$section_filter" && "$pkg_section" != "$section_filter" ]]; then
            continue
        fi
        
        # Group packages
        sources["$pkg_source"]+="$pkg_name "
        if [[ -n "$pkg_section" ]]; then
            sections["$pkg_section"]+="$pkg_name "
        fi
    done
    
    # Display by source
    for source in $(printf '%s\n' "${!sources[@]}" | sort); do
        echo "--- $source packages ---"
        echo "${sources[$source]}" | tr ' ' '\n' | sort | sed 's/^/  /'
        echo
    done
    
    # Display by section if no source filter
    if [[ -z "$source_filter" && ${#sections[@]} -gt 0 ]]; then
        echo "=== By Section ==="
        for section in $(printf '%s\n' "${!sections[@]}" | sort); do
            echo "--- $section ---"
            echo "${sections[$section]}" | tr ' ' '\n' | sort | sed 's/^/  /'
            echo
        done
    fi
}

# Validate package lists
# Usage: validate_package_lists
validate_package_lists() {
    local -i errors=0
    
    log_info "Validating package lists..."
    
    # Check if data directory exists
    if [[ ! -d "$SCRIPT_DIR/data" ]]; then
        log_error "Data directory not found: $SCRIPT_DIR/data"
        return 1
    fi
    
    # Validate each package list file
    for file in "$SCRIPT_DIR/data"/*.lst; do
        if [[ -f "$file" ]]; then
            log_debug "Validating $file..."
            
            # Check file is readable
            if [[ ! -r "$file" ]]; then
                log_error "Cannot read file: $file"
                ((errors++))
                continue
            fi
            
            # Parse file and check for errors
            if ! parse_package_list "$file" >/dev/null; then
                log_error "Failed to parse package list: $file"
                ((errors++))
            else
                log_debug "Package list valid: $file"
            fi
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        log_success "All package lists are valid"
        return 0
    else
        log_error "Found $errors errors in package lists"
        return 1
    fi
}

# Export functions for use in other scripts
export -f init_package_manager
export -f parse_package_list
export -f check_package_condition
export -f get_packages_for_distro
export -f get_packages_by_source
export -f get_packages_by_section
export -f install_packages_from_list
export -f install_all_packages
export -f list_packages
export -f validate_package_lists