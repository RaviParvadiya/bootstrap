#!/usr/bin/env bash

# Package Manager and Dependency Resolution System
# Handles component dependencies, conflicts, and hardware requirements

# Source required modules
[[ -z "${PATHS_SOURCED:-}" ]] && source "$(dirname "${BASH_SOURCE[0]}")/init-paths.sh"
source "$CORE_DIR/logger.sh"
source "$CORE_DIR/common.sh"

# Global variables
COMPONENT_DEPS_FILE="data/component-deps.json"
HARDWARE_PROFILES_FILE="data/hardware-profiles.json"
SELECTED_COMPONENTS=()
RESOLVED_DEPENDENCIES=()
DETECTED_CONFLICTS=()
HARDWARE_PROFILE=""

# Hardware detection cache
GPU_TYPE_CACHE=""
VM_STATUS_CACHE=""

# Load JSON configuration file
load_json_file() {
    local file="$1" description="$2"
    
    if [[ ! -f "$file" ]]; then
        log_error "$description file not found: $file"
        return 1
    fi
    
    log_info "Loaded $description"
    return 0
}

# Detect hardware profile based on system information
detect_hardware_profile() {
    log_info "Detecting hardware profile..."
    
    # Check if running in VM
    if is_virtual_machine; then
        HARDWARE_PROFILE="vm-generic"
        log_info "Virtual machine detected, using profile: $HARDWARE_PROFILE"
        return 0
    fi
    
    # Detect GPU type
    local gpu_type
    gpu_type=$(detect_gpu_type)
    
    # Check for specific hardware models
    local dmi_info
    dmi_info=$(sudo dmidecode -s system-product-name 2>/dev/null || echo "")
    
    if [[ "$dmi_info" =~ "TUF Gaming FX516" ]]; then
        HARDWARE_PROFILE="asus-tuf-dash-f15"
        log_info "ASUS TUF Dash F15 detected, using profile: $HARDWARE_PROFILE"
    elif [[ "$gpu_type" == "nvidia" ]]; then
        HARDWARE_PROFILE="generic-nvidia"
        log_info "NVIDIA GPU detected, using profile: $HARDWARE_PROFILE"
    elif [[ "$gpu_type" == "amd" ]]; then
        HARDWARE_PROFILE="generic-amd"
        log_info "AMD GPU detected, using profile: $HARDWARE_PROFILE"
    elif [[ "$gpu_type" == "intel" ]]; then
        HARDWARE_PROFILE="generic-intel"
        log_info "Intel GPU detected, using profile: $HARDWARE_PROFILE"
    else
        HARDWARE_PROFILE="generic-intel"
        log_warn "Could not detect specific hardware, using fallback profile: $HARDWARE_PROFILE"
    fi
    
    return 0
}

# Detect GPU type from lspci output (cached)
detect_gpu_type() {
    [[ -n "$GPU_TYPE_CACHE" ]] && { echo "$GPU_TYPE_CACHE"; return 0; }
    
    local lspci_output
    lspci_output=$(lspci | grep -i vga)
    
    if echo "$lspci_output" | grep -qi "nvidia\|geforce\|quadro\|tesla"; then
        GPU_TYPE_CACHE="nvidia"
    elif echo "$lspci_output" | grep -qi "amd\|radeon\|rx "; then
        GPU_TYPE_CACHE="amd"
    elif echo "$lspci_output" | grep -qi "intel.*graphics\|intel.*hd\|intel.*iris"; then
        GPU_TYPE_CACHE="intel"
    else
        GPU_TYPE_CACHE="unknown"
    fi
    
    echo "$GPU_TYPE_CACHE"
}

# Check if system is running in a virtual machine (cached)
is_virtual_machine() {
    [[ -n "$VM_STATUS_CACHE" ]] && [[ "$VM_STATUS_CACHE" == "true" ]] && return 0
    [[ -n "$VM_STATUS_CACHE" ]] && [[ "$VM_STATUS_CACHE" == "false" ]] && return 1
    
    # Check for virtualization indicators first (fastest)
    if [[ -d /proc/vz ]] || [[ -f /proc/xen/capabilities ]] || [[ -d /sys/bus/vmbus ]]; then
        VM_STATUS_CACHE="true"
        return 0
    fi
    
    # Check lscpu output
    if lscpu | grep -qi "hypervisor\|virtualization"; then
        VM_STATUS_CACHE="true"
        return 0
    fi
    
    # Check DMI information (slowest, do last)
    local dmi_info
    dmi_info=$(sudo dmidecode -s system-manufacturer 2>/dev/null || echo "")
    if echo "$dmi_info" | grep -qi "virtualbox\|vmware\|qemu\|kvm\|xen\|microsoft corporation"; then
        VM_STATUS_CACHE="true"
        return 0
    fi
    
    VM_STATUS_CACHE="false"
    return 1
}

# Generic JSON field getter
get_json_field() {
    local path="$1" file="$2"
    jq -r "$path // empty" "$file" 2>/dev/null
}

# Get component information from JSON
get_component_info() {
    get_json_field ".components.\"$1\".\"$2\"" "$COMPONENT_DEPS_FILE"
}

# Get component packages for current distribution
get_component_packages() {
    get_json_field ".components.\"$1\".packages.\"$2\"[]?" "$COMPONENT_DEPS_FILE"
}

# Get component dependencies
get_component_dependencies() {
    get_json_field ".components.\"$1\".dependencies[]?" "$COMPONENT_DEPS_FILE"
}

# Get component conflicts
get_component_conflicts() {
    get_json_field ".components.\"$1\".conflicts[]?" "$COMPONENT_DEPS_FILE"
}

# Resolve dependencies for a list of components
resolve_dependencies() {
    local components=("$@")
    local resolved=()
    local processing=()
    
    log_info "Resolving dependencies for components: ${components[*]}"
    
    # Clear previous results
    RESOLVED_DEPENDENCIES=()
    DETECTED_CONFLICTS=()
    
    # Process each component
    for component in "${components[@]}"; do
        if ! resolve_component_dependencies "$component" resolved processing; then
            log_error "Failed to resolve dependencies for component: $component"
            return 1
        fi
    done
    
    # Remove duplicates and store final result
    RESOLVED_DEPENDENCIES=($(printf '%s\n' "${resolved[@]}" | sort -u))
    
    log_success "Dependency resolution complete. Final component list: ${RESOLVED_DEPENDENCIES[*]}"
    return 0
}

# Recursively resolve dependencies for a single component
resolve_component_dependencies() {
    local component="$1"
    local resolved_var="$2"
    local processing_var="$3"
    local -n resolved_ref=$resolved_var
    local -n processing_ref=$processing_var
    
    # Check if component exists
    if ! component_exists "$component"; then
        log_error "Component '$component' not found in dependencies file"
        return 1
    fi
    
    # Check for circular dependencies
    if [[ " ${processing_ref[*]} " =~ " $component " ]]; then
        log_error "Circular dependency detected: $component"
        return 1
    fi
    
    # Skip if already resolved
    if [[ " ${resolved_ref[*]} " =~ " $component " ]]; then
        return 0
    fi
    
    # Add to processing list
    processing_ref+=("$component")
    
    # Get dependencies for this component
    local deps
    mapfile -t deps < <(get_component_dependencies "$component")
    
    # Resolve each dependency first
    for dep in "${deps[@]}"; do
        if [[ -n "$dep" ]]; then
            if ! resolve_component_dependencies "$dep" "$resolved_var" "$processing_var"; then
                return 1
            fi
        fi
    done
    
    # Add current component to resolved list
    resolved_ref+=("$component")
    
    # Remove from processing list
    local temp_processing=()
    for item in "${processing_ref[@]}"; do
        if [[ "$item" != "$component" ]]; then
            temp_processing+=("$item")
        fi
    done
    processing_ref=("${temp_processing[@]}")
    
    return 0
}

# Check if component exists in the dependencies file
component_exists() {
    [[ "$(get_json_field ".components | has(\"$1\")" "$COMPONENT_DEPS_FILE")" == "true" ]]
}

# Detect conflicts between selected components
detect_conflicts() {
    local components=("$@")
    local conflicts=()
    
    log_info "Detecting conflicts between components..."
    
    # Clear previous conflicts
    DETECTED_CONFLICTS=()
    
    # Check each component against all others
    for component in "${components[@]}"; do
        local component_conflicts
        mapfile -t component_conflicts < <(get_component_conflicts "$component")
        
        for conflict in "${component_conflicts[@]}"; do
            if [[ -n "$conflict" ]] && [[ " ${components[*]} " =~ " $conflict " ]]; then
                # Avoid duplicate conflict entries
                local conflict_pair="$component <-> $conflict"
                local reverse_pair="$conflict <-> $component"
                if [[ ! " ${conflicts[*]} " =~ " $conflict_pair " ]] && [[ ! " ${conflicts[*]} " =~ " $reverse_pair " ]]; then
                    conflicts+=("$conflict_pair")
                    log_warn "Conflict detected: $component conflicts with $conflict"
                fi
            fi
        done
        
        # Check category-based conflicts
        local category
        category=$(get_component_info "$component" "category")
        if [[ -n "$category" ]]; then
            check_category_conflicts "$component" "$category" "${components[@]}"
        fi
    done
    
    DETECTED_CONFLICTS=("${conflicts[@]}")
    
    if [[ ${#DETECTED_CONFLICTS[@]} -gt 0 ]]; then
        log_warn "Found ${#DETECTED_CONFLICTS[@]} conflict(s)"
        return 1
    else
        log_success "No conflicts detected"
        return 0
    fi
}

# Check for category-based conflicts (mutually exclusive categories)
check_category_conflicts() {
    local component="$1" category="$2"
    shift 2
    local all_components=("$@")
    
    # Check if category is mutually exclusive
    local is_exclusive
    is_exclusive=$(get_json_field ".categories.\"$category\".mutually_exclusive // false" "$COMPONENT_DEPS_FILE")
    
    if [[ "$is_exclusive" == "true" ]]; then
        # Find other components in the same category
        for other_component in "${all_components[@]}"; do
            if [[ "$other_component" != "$component" ]]; then
                local other_category
                other_category=$(get_component_info "$other_component" "category")
                if [[ "$other_category" == "$category" ]]; then
                    DETECTED_CONFLICTS+=("$component <-> $other_component (category: $category)")
                    log_warn "Category conflict: $component and $other_component are both in mutually exclusive category '$category'"
                fi
            fi
        done
    fi
}

# Get hardware profile packages for current distribution
get_hardware_packages() {
    get_json_field ".profiles.\"$1\".packages.\"$2\"[]?" "$HARDWARE_PROFILES_FILE"
}

# Get hardware profile environment variables
get_hardware_env_vars() {
    get_json_field ".profiles.\"$1\".environment_vars // {} | to_entries[] | \"\(.key)=\(.value)\"" "$HARDWARE_PROFILES_FILE"
}

# Check hardware requirements for components
check_hardware_requirements() {
    local components=("$@")
    local missing_requirements=()
    
    log_info "Checking hardware requirements..."
    
    for component in "${components[@]}"; do
        local requirements
        mapfile -t requirements < <(jq -r ".components.\"$component\".hardware_requirements[]? // empty" "$COMPONENT_DEPS_FILE" 2>/dev/null)
        
        for requirement in "${requirements[@]}"; do
            if [[ -n "$requirement" ]] && ! check_hardware_requirement "$requirement"; then
                missing_requirements+=("$component: $requirement")
                log_warn "Hardware requirement not met for $component: $requirement"
            fi
        done
    done
    
    if [[ ${#missing_requirements[@]} -gt 0 ]]; then
        log_error "Missing hardware requirements:"
        printf '%s\n' "${missing_requirements[@]}" | while read -r req; do
            log_error "  - $req"
        done
        return 1
    else
        log_success "All hardware requirements satisfied"
        return 0
    fi
}

# Check individual hardware requirement
check_hardware_requirement() {
    local requirement="$1"
    
    case "$requirement" in
        "gpu_acceleration")
            # Check for hardware acceleration support
            if command -v glxinfo >/dev/null 2>&1; then
                glxinfo | grep -qi "direct rendering: yes"
            else
                # Fallback check
                [[ -d /dev/dri ]]
            fi
            ;;
        "wayland_support")
            [[ "$XDG_SESSION_TYPE" == "wayland" || -n "$(command -v wayland-scanner)" ]]
            ;;
        "vulkan_support")
            # Check for Vulkan support
            command -v vulkaninfo >/dev/null 2>&1 && vulkaninfo --summary >/dev/null 2>&1
            ;;
        *)
            log_warn "Unknown hardware requirement: $requirement"
            return 0
            ;;
    esac
}

# Display dependency resolution summary
show_dependency_summary() {
    local selected=("$@")
    
    log_info "=== Dependency Resolution Summary ==="
    
    log_info "Selected components:"
    for component in "${selected[@]}"; do
        local name
        name=$(get_component_info "$component" "name")
        log_info "  - $component${name:+ ($name)}"
    done
    
    log_info "Resolved dependencies (final install list):"
    for component in "${RESOLVED_DEPENDENCIES[@]}"; do
        local name
        name=$(get_component_info "$component" "name")
        local is_selected=""
        if [[ " ${selected[*]} " =~ " $component " ]]; then
            is_selected=" [SELECTED]"
        else
            is_selected=" [DEPENDENCY]"
        fi
        log_info "  - $component${name:+ ($name)}$is_selected"
    done
    
    if [[ ${#DETECTED_CONFLICTS[@]} -gt 0 ]]; then
        log_warn "Detected conflicts:"
        for conflict in "${DETECTED_CONFLICTS[@]}"; do
            log_warn "  - $conflict"
        done
    fi
    
    if [[ -n "$HARDWARE_PROFILE" ]]; then
        local profile_name
        profile_name=$(get_json_field ".profiles.\"$HARDWARE_PROFILE\".name // \"$HARDWARE_PROFILE\"" "$HARDWARE_PROFILES_FILE")
        log_info "Hardware profile: $HARDWARE_PROFILE ($profile_name)"
    fi
}

# Get preset components
get_preset_components() {
    get_json_field ".presets.\"$1\".components[]?" "$COMPONENT_DEPS_FILE"
}

# List available presets
list_presets() {
    log_info "Available presets:"
    get_json_field '.presets | to_entries[] | "  - \(.key): \(.value.name) - \(.value.description)"' "$COMPONENT_DEPS_FILE"
}

# List available components
list_components() {
    log_info "Available components:"
    get_json_field '.components | to_entries[] | "  - \(.key): \(.value.name) - \(.value.description)"' "$COMPONENT_DEPS_FILE"
}

# Validate component dependency structure
validate_component_structure() {
    log_info "Validating component dependency structure..."
    
    local validation_errors=0
    
    # Get all component names
    local all_components
    mapfile -t all_components < <(get_json_field '.components | keys[]' "$COMPONENT_DEPS_FILE")
    
    # Validate each component
    for component in "${all_components[@]}"; do
        # Check dependencies exist
        local deps
        mapfile -t deps < <(get_component_dependencies "$component")
        for dep in "${deps[@]}"; do
            if [[ -n "$dep" ]] && ! component_exists "$dep"; then
                log_error "Component '$component' has invalid dependency: '$dep'"
                ((validation_errors++))
            fi
        done
        
        # Check conflicts exist (optional - conflicts might be external)
        local conflicts
        mapfile -t conflicts < <(get_component_conflicts "$component")
        for conflict in "${conflicts[@]}"; do
            if [[ -n "$conflict" ]] && component_exists "$conflict"; then
                # Check if the conflict is mutual
                local reverse_conflicts
                mapfile -t reverse_conflicts < <(get_component_conflicts "$conflict")
                if [[ ! " ${reverse_conflicts[*]} " =~ " $component " ]]; then
                    log_warn "Component '$component' conflicts with '$conflict', but '$conflict' doesn't list '$component' as a conflict"
                fi
            fi
        done
    done
    
    if [[ $validation_errors -eq 0 ]]; then
        log_success "Component dependency structure validation passed"
        return 0
    else
        log_error "Component dependency structure validation failed with $validation_errors errors"
        return 1
    fi
}

# Initialize package manager system
init_package_manager() {
    log_info "Initializing package manager system..."
    
    # Check for required tools
    if ! command -v jq >/dev/null 2>&1; then
        log_error "jq is required for JSON parsing but not installed"
        log_info "Please install jq first: sudo pacman -S jq (Arch) or sudo apt install jq (Ubuntu)"
        return 1
    fi
    
    # Load configuration files
    load_json_file "$COMPONENT_DEPS_FILE" "component dependencies" || return 1
    load_json_file "$HARDWARE_PROFILES_FILE" "hardware profiles" || return 1
    
    # Detect hardware profile
    if ! detect_hardware_profile; then
        log_warn "Hardware detection failed, using fallback profile"
        HARDWARE_PROFILE="generic-intel"
    fi
    
    # Validate component structure
    if ! validate_component_structure; then
        log_warn "Component structure validation failed, but continuing..."
    fi
    
    log_success "Package manager system initialized successfully"
    return 0
}

# Safe command execution with error handling and dry-run support
exec_safe() {
    local command="$1"
    local description="${2:-$command}"
    
    if [[ -z "$command" ]]; then
        log_error "Command is required"
        return 1
    fi
    
    log_info "Executing: $description"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would execute: $command"
        return 0
    fi
    
    if eval "$command"; then
        log_success "Command executed successfully: $description"
        return 0
    else
        local exit_code=$?
        log_error "Command failed: $description (exit code: $exit_code)"
        return $exit_code
    fi
}

