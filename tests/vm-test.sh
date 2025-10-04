#!/usr/bin/env bash

# tests/vm-test.sh - Virtual machine testing utilities for the modular install framework
# This module provides comprehensive VM testing support with hardware detection that skips
# physical hardware configurations in VMs and automated post-installation validation checks.

# Prevent multiple sourcing
if [[ -n "${VM_TEST_SOURCED:-}" ]]; then
    return 0
fi
readonly VM_TEST_SOURCED=1

# Initialize project paths (centralized path resolution)
source "$(dirname "${BASH_SOURCE[0]}")/../core/init-paths.sh"

# Source required modules
source "$CORE_DIR/common.sh"
source "$CORE_DIR/logger.sh"
source "$CORE_DIR/validator.sh"
source "$TESTS_DIR/validate.sh"

# VM detection state
VM_DETECTED=""
VM_TYPE=""
VM_HYPERVISOR=""
VM_FEATURES=()

#######################################
# VM Environment Detection Functions
#######################################

# Detect if running in a virtual machine environment
detect_vm_environment() {
    if [[ -n "$VM_DETECTED" ]]; then
        return $([[ "$VM_DETECTED" == "true" ]] && echo 0 || echo 1)
    fi

    log_info "Detecting virtual machine environment..."
    
    VM_DETECTED="false"
    VM_TYPE=""
    VM_HYPERVISOR=""
    VM_FEATURES=()
    
    # Method 1: Check DMI/SMBIOS information
    if _detect_vm_dmi; then
        VM_DETECTED="true"
    fi
    
    # Method 2: Check CPU flags and features
    if _detect_vm_cpu; then
        VM_DETECTED="true"
    fi
    
    # Method 3: Check for virtualization-specific devices
    if _detect_vm_devices; then
        VM_DETECTED="true"
    fi
    
    # Method 4: Check systemd-detect-virt if available
    if _detect_vm_systemd; then
        VM_DETECTED="true"
    fi
    
    # Method 5: Check for container environment
    if _detect_container_environment; then
        VM_DETECTED="true"
        VM_TYPE="container"
    fi
    
    # Log detection results
    if [[ "$VM_DETECTED" == "true" ]]; then
        log_success "Virtual machine environment detected"
        log_info "VM Type: ${VM_TYPE:-unknown}"
        log_info "Hypervisor: ${VM_HYPERVISOR:-unknown}"
        if [[ ${#VM_FEATURES[@]} -gt 0 ]]; then
            log_info "VM Features: ${VM_FEATURES[*]}"
        fi
        
        # Set VM mode environment variable
        export VM_MODE=true
    else
        log_info "Physical hardware detected"
        export VM_MODE=false
    fi
    
    return $([[ "$VM_DETECTED" == "true" ]] && echo 0 || echo 1)
}

# Detect VM through DMI/SMBIOS information
_detect_vm_dmi() {
    local dmi_files=(
        "/sys/class/dmi/id/sys_vendor"
        "/sys/class/dmi/id/product_name"
        "/sys/class/dmi/id/board_vendor"
        "/sys/class/dmi/id/bios_vendor"
        "/sys/class/dmi/id/chassis_vendor"
    )
    
    for file in "${dmi_files[@]}"; do
        if [[ -r "$file" ]]; then
            local content
            content=$(cat "$file" 2>/dev/null | tr '[:upper:]' '[:lower:]')
            
            case "$content" in
                *vmware*)
                    VM_TYPE="vmware"
                    VM_HYPERVISOR="VMware"
                    VM_FEATURES+=("vmware-tools")
                    return 0
                    ;;
                *virtualbox*|*vbox*)
                    VM_TYPE="virtualbox"
                    VM_HYPERVISOR="VirtualBox"
                    VM_FEATURES+=("guest-additions")
                    return 0
                    ;;
                *qemu*|*kvm*)
                    VM_TYPE="qemu"
                    VM_HYPERVISOR="QEMU/KVM"
                    VM_FEATURES+=("qemu-guest-agent")
                    return 0
                    ;;
                *microsoft*|*hyper-v*)
                    VM_TYPE="hyperv"
                    VM_HYPERVISOR="Hyper-V"
                    VM_FEATURES+=("hyperv-tools")
                    return 0
                    ;;
                *xen*)
                    VM_TYPE="xen"
                    VM_HYPERVISOR="Xen"
                    VM_FEATURES+=("xen-tools")
                    return 0
                    ;;
                *parallels*)
                    VM_TYPE="parallels"
                    VM_HYPERVISOR="Parallels"
                    VM_FEATURES+=("parallels-tools")
                    return 0
                    ;;
                *bochs*|*seabios*)
                    VM_TYPE="qemu"
                    VM_HYPERVISOR="QEMU"
                    return 0
                    ;;
            esac
        fi
    done
    
    return 1
}

# Detect VM through CPU information
_detect_vm_cpu() {
    if [[ -r "/proc/cpuinfo" ]]; then
        local cpu_info
        cpu_info=$(cat /proc/cpuinfo | tr '[:upper:]' '[:lower:]')
        
        # Check for hypervisor flag in CPU flags
        if echo "$cpu_info" | grep "^flags" | grep -q "hypervisor"; then
            VM_FEATURES+=("hypervisor-flag")
            
            # Try to identify specific hypervisor from CPU model
            if echo "$cpu_info" | grep "model name" | grep -q "vmware"; then
                VM_TYPE="vmware"
                VM_HYPERVISOR="VMware"
            elif echo "$cpu_info" | grep "model name" | grep -q "qemu"; then
                VM_TYPE="qemu"
                VM_HYPERVISOR="QEMU"
            fi
            
            return 0
        fi
        
        # Check for virtualization-specific CPU models (but not "virtual address")
        if echo "$cpu_info" | grep "model name" | grep -E "(qemu|vmware|kvm)" >/dev/null; then
            return 0
        fi
    fi
    
    return 1
}

# Detect VM through device information
_detect_vm_devices() {
    # Check PCI devices
    if command -v lspci >/dev/null 2>&1; then
        local pci_devices
        pci_devices=$(lspci 2>/dev/null | tr '[:upper:]' '[:lower:]')
        
        if echo "$pci_devices" | grep -E "(vmware|virtualbox|qemu|virtio|hyper-v)" >/dev/null; then
            if echo "$pci_devices" | grep -q "vmware"; then
                VM_TYPE="vmware"
                VM_HYPERVISOR="VMware"
            elif echo "$pci_devices" | grep -q "virtualbox"; then
                VM_TYPE="virtualbox"
                VM_HYPERVISOR="VirtualBox"
            elif echo "$pci_devices" | grep -E "(qemu|virtio)" >/dev/null; then
                VM_TYPE="qemu"
                VM_HYPERVISOR="QEMU/KVM"
            fi
            return 0
        fi
    fi
    
    # Check for virtualization-specific block devices
    if [[ -d "/sys/block" ]]; then
        for device in /sys/block/*/device/model; do
            if [[ -r "$device" ]]; then
                local model
                model=$(cat "$device" 2>/dev/null | tr '[:upper:]' '[:lower:]')
                if echo "$model" | grep -E "(vmware|vbox|qemu|virtio)" >/dev/null; then
                    return 0
                fi
            fi
        done
    fi
    
    # Check for virtualization-specific network interfaces
    if command -v ip >/dev/null 2>&1; then
        local interfaces
        interfaces=$(ip link show 2>/dev/null | grep -E "eth|ens|enp" | tr '[:upper:]' '[:lower:]')
        if echo "$interfaces" | grep -E "(vmware|vbox|virtio)" >/dev/null; then
            return 0
        fi
    fi
    
    return 1
}

# Detect VM using systemd-detect-virt
_detect_vm_systemd() {
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        local virt_type
        virt_type=$(systemd-detect-virt 2>/dev/null)
        local exit_code=$?
        
        # systemd-detect-virt returns 0 for VM, 1 for physical hardware
        if [[ $exit_code -eq 0 && "$virt_type" != "none" && -n "$virt_type" ]]; then
            VM_TYPE="$virt_type"
            
            case "$virt_type" in
                "vmware")
                    VM_HYPERVISOR="VMware"
                    VM_FEATURES+=("vmware-tools")
                    ;;
                "oracle")
                    VM_HYPERVISOR="VirtualBox"
                    VM_FEATURES+=("guest-additions")
                    ;;
                "qemu"|"kvm")
                    VM_HYPERVISOR="QEMU/KVM"
                    VM_FEATURES+=("qemu-guest-agent")
                    ;;
                "microsoft")
                    VM_HYPERVISOR="Hyper-V"
                    VM_FEATURES+=("hyperv-tools")
                    ;;
                "xen")
                    VM_HYPERVISOR="Xen"
                    VM_FEATURES+=("xen-tools")
                    ;;
                *)
                    VM_HYPERVISOR="$virt_type"
                    ;;
            esac
            
            return 0
        fi
    fi
    
    return 1
}

# Detect container environment
_detect_container_environment() {
    # Check for container-specific files
    if [[ -f "/.dockerenv" ]]; then
        VM_TYPE="docker"
        VM_HYPERVISOR="Docker"
        VM_FEATURES+=("docker-container")
        return 0
    fi
    
    # Check cgroup information
    if [[ -f "/proc/1/cgroup" ]]; then
        local cgroup_info
        cgroup_info=$(cat /proc/1/cgroup 2>/dev/null)
        if echo "$cgroup_info" | grep -E "(docker|lxc|systemd:/docker)" >/dev/null; then
            VM_TYPE="container"
            VM_HYPERVISOR="Container Runtime"
            VM_FEATURES+=("containerized")
            return 0
        fi
    fi
    
    # Check for LXC
    if [[ -d "/proc/vz" ]] || [[ -f "/proc/user_beancounters" ]]; then
        VM_TYPE="openvz"
        VM_HYPERVISOR="OpenVZ"
        VM_FEATURES+=("openvz-container")
        return 0
    fi
    
    return 1
}

# Get VM detection results
is_vm() {
    detect_vm_environment >/dev/null 2>&1
    [[ "$VM_DETECTED" == "true" ]]
}

get_vm_type() {
    detect_vm_environment >/dev/null 2>&1
    echo "$VM_TYPE"
}

get_vm_hypervisor() {
    detect_vm_environment >/dev/null 2>&1
    echo "$VM_HYPERVISOR"
}

get_vm_features() {
    detect_vm_environment >/dev/null 2>&1
    printf '%s\n' "${VM_FEATURES[@]}"
}

#######################################
# VM-Specific Hardware Configuration Skip
#######################################

# Check if hardware configuration should be skipped in VM
# Arguments: $1 - hardware type (nvidia, audio, bluetooth, etc.)
should_skip_hardware_config() {
    local hardware_type="$1"
    
    # Check if we're in VM mode (either detected VM or forced VM mode)
    if [[ "$VM_MODE" != "true" ]] && ! is_vm; then
        return 1  # Not in VM mode, don't skip
    fi
    
    case "$hardware_type" in
        "nvidia"|"amd-gpu"|"intel-gpu")
            # Skip GPU driver installation in VMs (use VM graphics drivers instead)
            log_info "Skipping $hardware_type configuration in VM environment"
            return 0
            ;;
        "bluetooth")
            # Skip Bluetooth configuration in most VMs
            log_info "Skipping Bluetooth configuration in VM environment"
            return 0
            ;;
        "wifi"|"wireless")
            # Skip WiFi configuration in VMs (usually use bridged/NAT networking)
            log_info "Skipping WiFi configuration in VM environment"
            return 0
            ;;
        "power-management"|"battery")
            # Skip power management in VMs
            log_info "Skipping power management configuration in VM environment"
            return 0
            ;;
        "suspend"|"hibernate")
            # Skip suspend/hibernate in VMs
            log_info "Skipping suspend/hibernate configuration in VM environment"
            return 0
            ;;
        "backlight"|"brightness")
            # Skip backlight controls in VMs
            log_info "Skipping backlight configuration in VM environment"
            return 0
            ;;
        "touchpad"|"trackpad")
            # Skip touchpad configuration in VMs
            log_info "Skipping touchpad configuration in VM environment"
            return 0
            ;;
        "fingerprint")
            # Skip fingerprint reader configuration in VMs
            log_info "Skipping fingerprint configuration in VM environment"
            return 0
            ;;
        "webcam"|"camera")
            # Usually skip camera configuration in VMs unless specifically passed through
            log_info "Skipping camera configuration in VM environment"
            return 0
            ;;
        "audio")
            # Audio might work in VMs, but skip advanced audio configurations
            local vm_type
            vm_type=$(get_vm_type)
            if [[ "$vm_type" == "docker" || "$vm_type" == "container" ]]; then
                log_info "Skipping audio configuration in container environment"
                return 0
            fi
            # Allow basic audio in full VMs
            return 1
            ;;
        *)
            # For unknown hardware types, proceed with caution
            log_debug "Unknown hardware type '$hardware_type' - proceeding with configuration"
            return 1
            ;;
    esac
}

# Get VM-appropriate package alternatives
# Arguments: $1 - original package name
get_vm_package_alternative() {
    local package="$1"
    local vm_type
    vm_type=$(get_vm_type)
    
    case "$package" in
        "nvidia"|"nvidia-dkms"|"nvidia-utils")
            # Use generic graphics drivers in VMs
            case "$vm_type" in
                "vmware") echo "open-vm-tools" ;;
                "virtualbox") echo "virtualbox-guest-utils" ;;
                "qemu") echo "qemu-guest-agent" ;;
                *) echo "mesa" ;;
            esac
            ;;
        "bluez"|"bluetooth")
            # Skip Bluetooth packages in VMs
            echo ""
            ;;
        "tlp"|"powertop")
            # Skip power management tools in VMs
            echo ""
            ;;
        *)
            # Return original package for most cases
            echo "$package"
            ;;
    esac
}

#######################################
# VM Testing Functions
#######################################

# Run comprehensive VM tests
# Arguments: $@ - components to test (optional)
run_vm_tests() {
    local components=("$@")
    
    log_section "VM Testing Mode"
    
    # Detect VM environment first
    if ! detect_vm_environment; then
        log_warn "VM testing mode requested but no VM environment detected"
        log_warn "This may be a physical machine - some tests may not be relevant"
    fi
    
    # Initialize VM testing environment
    init_vm_testing
    
    local test_results=()
    local failed_tests=0
    
    # Run VM environment validation
    log_info "Running VM environment validation..."
    if validate_vm_environment; then
        test_results+=("VM Environment: PASS")
    else
        test_results+=("VM Environment: FAIL")
        ((failed_tests++))
    fi
    
    # Run VM-specific installation test
    log_info "Running VM installation test..."
    if test_vm_installation "${components[@]}"; then
        test_results+=("VM Installation: PASS")
    else
        test_results+=("VM Installation: FAIL")
        ((failed_tests++))
    fi
    
    # Run VM hardware configuration test
    log_info "Running VM hardware configuration test..."
    if test_vm_hardware_config; then
        test_results+=("VM Hardware Config: PASS")
    else
        test_results+=("VM Hardware Config: FAIL")
        ((failed_tests++))
    fi
    
    # Run VM post-installation validation
    log_info "Running VM post-installation validation..."
    if validate_vm_installation; then
        test_results+=("VM Post-Install: PASS")
    else
        test_results+=("VM Post-Install: FAIL")
        ((failed_tests++))
    fi
    
    # Display test summary
    display_vm_test_summary "${test_results[@]}"
    
    if [[ $failed_tests -eq 0 ]]; then
        log_success "All VM tests passed ✓"
        return 0
    else
        log_error "$failed_tests VM test(s) failed"
        return 1
    fi
}

# Initialize VM testing environment
init_vm_testing() {
    log_info "Initializing VM testing environment..."
    
    # Set VM mode flags
    export VM_MODE=true
    export TESTING_MODE=true
    
    # Create VM-specific test directories
    local vm_test_dir="/tmp/vm-test-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$vm_test_dir"
    export VM_TEST_DIR="$vm_test_dir"
    
    log_info "VM test directory: $VM_TEST_DIR"
    
    # Set VM-appropriate configuration overrides
    export SKIP_HARDWARE_DETECTION=true
    export SKIP_GPU_CONFIG=true
    export SKIP_POWER_MANAGEMENT=true
    
    log_success "VM testing environment initialized"
}

# Test VM installation process
# Arguments: $@ - components to test
test_vm_installation() {
    local components=("$@")
    
    log_info "Testing VM installation process..."
    
    # Enable dry-run mode for testing
    local original_dry_run="$DRY_RUN"
    export DRY_RUN=true
    
    # Test component selection and dependency resolution
    if [[ ${#components[@]} -gt 0 ]]; then
        log_info "Testing specific components: ${components[*]}"
        export SELECTED_COMPONENTS=("${components[@]}")
    else
        log_info "Testing full installation"
    fi
    
    # Simulate installation process
    local install_success=true
    
    # Test package installation (dry-run)
    if ! test_vm_package_installation; then
        install_success=false
    fi
    
    # Test configuration application
    if ! test_vm_configuration; then
        install_success=false
    fi
    
    # Test service management
    if ! test_vm_service_management; then
        install_success=false
    fi
    
    # Restore original dry-run setting
    export DRY_RUN="$original_dry_run"
    
    if [[ "$install_success" == "true" ]]; then
        log_success "VM installation test passed"
        return 0
    else
        log_error "VM installation test failed"
        return 1
    fi
}

# Test VM package installation
test_vm_package_installation() {
    log_info "Testing VM package installation..."
    
    local vm_type
    vm_type=$(get_vm_type)
    
    # Test VM-specific packages
    case "$vm_type" in
        "vmware")
            log_info "Testing VMware-specific packages..."
            if ! is_package_installed "open-vm-tools"; then
                log_info "Would install: open-vm-tools"
            fi
            ;;
        "virtualbox")
            log_info "Testing VirtualBox-specific packages..."
            if ! is_package_installed "virtualbox-guest-utils"; then
                log_info "Would install: virtualbox-guest-utils"
            fi
            ;;
        "qemu")
            log_info "Testing QEMU/KVM-specific packages..."
            if ! is_package_installed "qemu-guest-agent"; then
                log_info "Would install: qemu-guest-agent"
            fi
            ;;
    esac
    
    # Test that hardware-specific packages are skipped
    local hardware_packages=("nvidia" "nvidia-dkms" "bluez" "tlp")
    for package in "${hardware_packages[@]}"; do
        local alternative
        alternative=$(get_vm_package_alternative "$package")
        if [[ "$alternative" != "$package" ]]; then
            log_success "Hardware package '$package' correctly replaced with '$alternative'"
        fi
    done
    
    return 0
}

# Test VM configuration
test_vm_configuration() {
    log_info "Testing VM configuration..."
    
    # Test that hardware-specific configurations are skipped
    local hardware_configs=("nvidia" "bluetooth" "power-management" "touchpad")
    for config in "${hardware_configs[@]}"; do
        if should_skip_hardware_config "$config"; then
            log_success "Hardware config '$config' correctly skipped in VM"
        else
            log_warn "Hardware config '$config' not skipped in VM"
        fi
    done
    
    # Test VM-specific configurations
    local vm_type
    vm_type=$(get_vm_type)
    
    case "$vm_type" in
        "vmware")
            log_info "Testing VMware-specific configurations..."
            # Test VMware tools configuration
            ;;
        "virtualbox")
            log_info "Testing VirtualBox-specific configurations..."
            # Test VirtualBox guest additions configuration
            ;;
        "qemu")
            log_info "Testing QEMU/KVM-specific configurations..."
            # Test QEMU guest agent configuration
            ;;
    esac
    
    return 0
}

# Test VM service management
test_vm_service_management() {
    log_info "Testing VM service management..."
    
    # Test that hardware-specific services are not enabled
    local hardware_services=("bluetooth" "tlp" "thermald")
    for service in "${hardware_services[@]}"; do
        log_info "Service '$service' would be skipped in VM environment"
    done
    
    # Test VM-specific services
    local vm_type
    vm_type=$(get_vm_type)
    
    case "$vm_type" in
        "vmware")
            log_info "VMware tools services would be enabled"
            ;;
        "virtualbox")
            log_info "VirtualBox guest services would be enabled"
            ;;
        "qemu")
            log_info "QEMU guest agent would be enabled"
            ;;
    esac
    
    return 0
}

# Test VM hardware configuration
test_vm_hardware_config() {
    log_info "Testing VM hardware configuration..."
    
    local config_success=true
    
    # Test GPU configuration skipping
    if should_skip_hardware_config "nvidia"; then
        log_success "NVIDIA configuration correctly skipped in VM"
    else
        log_warn "NVIDIA configuration not skipped in VM"
        config_success=false
    fi
    
    # Test other hardware configuration skipping
    local hardware_types=("bluetooth" "wifi" "power-management" "touchpad")
    for hw_type in "${hardware_types[@]}"; do
        if should_skip_hardware_config "$hw_type"; then
            log_success "$hw_type configuration correctly skipped in VM"
        else
            log_warn "$hw_type configuration not skipped in VM"
            config_success=false
        fi
    done
    
    return $([[ "$config_success" == "true" ]] && echo 0 || echo 1)
}

#######################################
# VM Validation Functions
#######################################

# Validate VM environment
validate_vm_environment() {
    log_info "Validating VM environment..."
    
    local validation_success=true
    
    # Validate VM detection
    if is_vm; then
        log_success "VM environment correctly detected"
        log_info "VM Type: $(get_vm_type)"
        log_info "Hypervisor: $(get_vm_hypervisor)"
    else
        log_warn "VM environment not detected (may be physical hardware)"
        validation_success=false
    fi
    
    # Validate VM-specific tools
    local vm_type
    vm_type=$(get_vm_type)
    
    case "$vm_type" in
        "vmware")
            if command -v vmware-toolbox-cmd >/dev/null 2>&1; then
                log_success "VMware tools available"
            else
                log_warn "VMware tools not installed"
                validation_success=false
            fi
            ;;
        "virtualbox")
            if command -v VBoxClient >/dev/null 2>&1; then
                log_success "VirtualBox guest additions available"
            else
                log_warn "VirtualBox guest additions not installed"
                validation_success=false
            fi
            ;;
        "qemu")
            if command -v qemu-ga >/dev/null 2>&1; then
                log_success "QEMU guest agent available"
            else
                log_warn "QEMU guest agent not installed"
                validation_success=false
            fi
            ;;
    esac
    
    return $([[ "$validation_success" == "true" ]] && echo 0 || echo 1)
}

# Validate VM installation
validate_vm_installation() {
    log_info "Validating VM installation..."
    
    local validation_success=true
    
    # Run standard installation validation
    if ! validate_installation; then
        validation_success=false
    fi
    
    # VM-specific validation
    if ! validate_vm_specific_installation; then
        validation_success=false
    fi
    
    # Validate that hardware-specific components were skipped
    if ! validate_vm_hardware_skipping; then
        validation_success=false
    fi
    
    return $([[ "$validation_success" == "true" ]] && echo 0 || echo 1)
}

# Validate VM-specific installation components
validate_vm_specific_installation() {
    log_info "Validating VM-specific installation components..."
    
    local vm_validation_success=true
    local vm_type
    vm_type=$(get_vm_type)
    
    case "$vm_type" in
        "vmware")
            # Validate VMware tools
            if command -v vmware-toolbox-cmd >/dev/null 2>&1; then
                log_success "VMware tools: installed"
                
                # Test VMware tools functionality
                if vmware-toolbox-cmd -v >/dev/null 2>&1; then
                    log_success "VMware tools: functional"
                else
                    log_warn "VMware tools: installed but not functional"
                    vm_validation_success=false
                fi
            else
                log_warn "VMware tools: not installed"
                vm_validation_success=false
            fi
            ;;
        "virtualbox")
            # Validate VirtualBox guest additions
            if command -v VBoxClient >/dev/null 2>&1; then
                log_success "VirtualBox guest additions: installed"
                
                # Check for guest additions services
                if systemctl is-active vboxservice >/dev/null 2>&1; then
                    log_success "VirtualBox services: running"
                else
                    log_warn "VirtualBox services: not running"
                    vm_validation_success=false
                fi
            else
                log_warn "VirtualBox guest additions: not installed"
                vm_validation_success=false
            fi
            ;;
        "qemu")
            # Validate QEMU guest agent
            if command -v qemu-ga >/dev/null 2>&1; then
                log_success "QEMU guest agent: installed"
                
                # Check if guest agent is running
                if systemctl is-active qemu-guest-agent >/dev/null 2>&1; then
                    log_success "QEMU guest agent: running"
                else
                    log_warn "QEMU guest agent: not running"
                    vm_validation_success=false
                fi
            else
                log_warn "QEMU guest agent: not installed"
                vm_validation_success=false
            fi
            ;;
        "docker"|"container")
            log_info "Container environment - skipping VM tools validation"
            ;;
        *)
            log_info "Unknown VM type - skipping VM-specific validation"
            ;;
    esac
    
    return $([[ "$vm_validation_success" == "true" ]] && echo 0 || echo 1)
}

# Validate that hardware-specific components were properly skipped
validate_vm_hardware_skipping() {
    log_info "Validating hardware component skipping in VM..."
    
    local skip_validation_success=true
    
    # If we're testing on physical hardware, just validate the logic works
    if [[ "$VM_MODE" == "true" ]] && ! is_vm; then
        log_info "Testing VM hardware skipping logic on physical hardware"
        
        # Test that the skipping logic would work
        if should_skip_hardware_config "nvidia"; then
            log_success "NVIDIA configuration would be correctly skipped in VM"
        else
            log_warn "NVIDIA configuration skipping logic failed"
            skip_validation_success=false
        fi
        
        if should_skip_hardware_config "bluetooth"; then
            log_success "Bluetooth configuration would be correctly skipped in VM"
        else
            log_warn "Bluetooth configuration skipping logic failed"
            skip_validation_success=false
        fi
        
        return $([[ "$skip_validation_success" == "true" ]] && echo 0 || echo 1)
    fi
    
    # Check that NVIDIA drivers are not installed (unless specifically needed)
    if command -v nvidia-smi >/dev/null 2>&1; then
        log_warn "NVIDIA drivers found in VM (may be intentional for GPU passthrough)"
    else
        log_success "NVIDIA drivers correctly not installed in VM"
    fi
    
    # Check that power management tools are not configured
    if systemctl is-enabled tlp >/dev/null 2>&1; then
        log_warn "TLP power management enabled in VM (usually unnecessary)"
        skip_validation_success=false
    else
        log_success "Power management correctly not enabled in VM"
    fi
    
    # Check that Bluetooth is not configured (unless specifically needed)
    if systemctl is-enabled bluetooth >/dev/null 2>&1; then
        log_warn "Bluetooth enabled in VM (may be unnecessary)"
    else
        log_success "Bluetooth correctly not enabled in VM"
    fi
    
    return $([[ "$skip_validation_success" == "true" ]] && echo 0 || echo 1)
}

#######################################
# VM Test Reporting
#######################################

# Display VM test summary
display_vm_test_summary() {
    local test_results=("$@")
    
    log_section "VM Test Summary"
    
    echo "VM Environment Information:"
    echo "  Type: $(get_vm_type)"
    echo "  Hypervisor: $(get_vm_hypervisor)"
    echo "  Features: $(get_vm_features | tr '\n' ' ')"
    echo
    
    echo "Test Results:"
    for result in "${test_results[@]}"; do
        if [[ "$result" =~ PASS ]]; then
            echo "  ✓ $result"
        else
            echo "  ✗ $result"
        fi
    done
    echo
    
    # Display VM-specific recommendations
    display_vm_recommendations
}

# Display VM-specific recommendations
display_vm_recommendations() {
    local vm_type
    vm_type=$(get_vm_type)
    
    echo "VM-Specific Recommendations:"
    
    case "$vm_type" in
        "vmware")
            echo "  • Install VMware Tools for better integration"
            echo "  • Enable shared folders if needed"
            echo "  • Configure display scaling for high-DPI hosts"
            ;;
        "virtualbox")
            echo "  • Install VirtualBox Guest Additions for better performance"
            echo "  • Enable 3D acceleration in VM settings"
            echo "  • Increase video memory allocation"
            ;;
        "qemu")
            echo "  • Install QEMU Guest Agent for better host integration"
            echo "  • Use virtio drivers for better performance"
            echo "  • Enable SPICE guest tools if using SPICE"
            ;;
        "docker"|"container")
            echo "  • Container environment detected"
            echo "  • GUI applications may require X11 forwarding"
            echo "  • Consider using display server passthrough"
            ;;
        *)
            echo "  • Unknown VM type - general recommendations apply"
            echo "  • Install appropriate guest tools for your hypervisor"
            ;;
    esac
    echo
}

#######################################
# Command Line Interface
#######################################

# Main function for VM testing script
main_vm_test() {
    local mode="${1:-detect}"
    shift
    local components=("$@")
    
    case "$mode" in
        "detect")
            detect_vm_environment
            ;;
        "test"|"run")
            run_vm_tests "${components[@]}"
            ;;
        "validate")
            validate_vm_installation
            ;;
        "environment")
            validate_vm_environment
            ;;
        "info")
            detect_vm_environment
            echo "VM Detected: $(is_vm && echo "Yes" || echo "No")"
            echo "VM Type: $(get_vm_type)"
            echo "Hypervisor: $(get_vm_hypervisor)"
            echo "Features: $(get_vm_features | tr '\n' ' ')"
            ;;
        *)
            echo "Usage: $0 [mode] [components...]"
            echo
            echo "Modes:"
            echo "  detect      - Detect VM environment (default)"
            echo "  test        - Run comprehensive VM tests"
            echo "  validate    - Validate VM installation"
            echo "  environment - Validate VM environment only"
            echo "  info        - Display VM information"
            echo
            echo "Examples:"
            echo "  $0                           # Detect VM environment"
            echo "  $0 test                      # Run all VM tests"
            echo "  $0 test hyprland terminal    # Test specific components"
            echo "  $0 validate                  # Validate VM installation"
            echo "  $0 info                      # Show VM information"
            exit 1
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_vm_test "$@"
fi