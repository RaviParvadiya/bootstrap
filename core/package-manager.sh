#!/usr/bin/env bash

# Package Manager and Dependency Resolution System
# Handles component dependencies and hardware requirements

# Source required modules
[[ -z "${PATHS_SOURCED:-}" ]] && source "$(dirname "${BASH_SOURCE[0]}")/init-paths.sh"
source "$CORE_DIR/logger.sh"
source "$CORE_DIR/common.sh"

# Global variables
COMPONENT_DEPS_FILE="data/component-deps.json"
HARDWARE_PROFILES_FILE="data/hardware-profiles.json"
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

# Get component dependencies
get_component_dependencies() {
    get_json_field ".components.\"$1\".dependencies[]?" "$COMPONENT_DEPS_FILE"
}

# Check if component exists in the dependencies file
component_exists() {
    [[ "$(get_json_field ".components | has(\"$1\")" "$COMPONENT_DEPS_FILE")" == "true" ]]
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

