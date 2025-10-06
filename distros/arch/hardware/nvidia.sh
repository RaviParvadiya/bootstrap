#!/usr/bin/env bash

# NVIDIA GPU Configuration Module for Arch Linux
# Handles NVIDIA driver installation, MUX switch support, and environment configuration
# Extracted from original install.sh and modularized for the framework

# Initialize all project paths
source "$(dirname "${BASH_SOURCE[0]}")/../../../core/init-paths.sh"

# Source core utilities
source "$CORE_DIR/common.sh"
source "$CORE_DIR/logger.sh"

# NVIDIA-specific configuration variables
NVIDIA_PACKAGES_RTX=(
    "nvidia-open-dkms"
    "nvidia-utils"
    "lib32-nvidia-utils"
    "nvidia-settings"
    "opencl-nvidia"
    "egl-wayland"
    "libva-nvidia-driver"
)

NVIDIA_PACKAGES_NON_RTX=(
    "nvidia-dkms"
    "nvidia-utils"
    "lib32-nvidia-utils"
    "nvidia-settings"
    "opencl-nvidia"
    "egl-wayland"
    "libva-nvidia-driver"
)

NVIDIA_SERVICES=(
    "nvidia-suspend.service"
    "nvidia-hibernate.service"
    "nvidia-resume.service"
)

# Check if NVIDIA GPU is present
detect_nvidia_gpu() {
    if lspci | grep -i nvidia &> /dev/null; then
        log_info "NVIDIA GPU detected"
        return 0
    else
        log_info "No NVIDIA GPU detected"
        return 1
    fi
}

# Check if RTX GPU is present
is_rtx_gpu() {
    # First try automatic detection
    if lspci | grep -i nvidia | grep -i rtx &> /dev/null; then
        log_info "RTX GPU detected automatically"
        return 0
    fi
    
    # If automatic detection fails, ask user (preserving original behavior)
    log_info "Could not automatically detect RTX GPU"
    if ask_yes_no "Do you have an RTX GPU?"; then
        log_info "User confirmed RTX GPU"
        return 0
    else
        log_info "User confirmed non-RTX NVIDIA GPU"
        return 1
    fi
}

# Install NVIDIA drivers based on GPU type
install_nvidia_drivers() {
    log_info "Installing NVIDIA GPU drivers..."
    
    # Determine which driver package to install
    local packages_to_install
    if is_rtx_gpu; then
        log_info "Installing RTX-compatible drivers (nvidia-open-dkms)"
        packages_to_install=("${NVIDIA_PACKAGES_RTX[@]}")
    else
        log_info "Installing standard NVIDIA drivers (nvidia-dkms)"
        packages_to_install=("${NVIDIA_PACKAGES_NON_RTX[@]}")
    fi
    
    # Install packages
    for package in "${packages_to_install[@]}"; do
        log_info "Installing $package..."
        if ! install_package "$package"; then
            log_error "Failed to install $package"
            return 1
        fi
    done
    
    return 0
}

# Configure NVIDIA kernel modules
configure_nvidia_modules() {
    log_info "Configuring NVIDIA kernel modules..."
    
    # Edit /etc/mkinitcpio.conf to add NVIDIA modules
    local mkinitcpio_conf="/etc/mkinitcpio.conf"
    local nvidia_modules="nvidia nvidia_modeset nvidia_uvm nvidia_drm"

    log_info "Adding NVIDIA modules to $mkinitcpio_conf..."
    
    # Check if modules are already present
    if grep -q "nvidia" "$mkinitcpio_conf"; then
        log_warn "NVIDIA modules already present in $mkinitcpio_conf"
    else
        # Add NVIDIA modules to MODULES array
        if sudo sed -i "s/^MODULES=(/&$nvidia_modules /" "$mkinitcpio_conf"; then
            log_success "NVIDIA modules added to $mkinitcpio_conf"
        else
            log_error "Failed to modify $mkinitcpio_conf"
            return 1
        fi
    fi
    
    return 0
}

# Configure NVIDIA modprobe settings
configure_nvidia_modprobe() {
    log_info "Configuring NVIDIA modprobe settings..."
    
    local nvidia_conf="/etc/modprobe.d/nvidia.conf"
    local nvidia_options="options nvidia_drm modeset=1 fbdev=1"

    log_info "Creating $nvidia_conf..."
    
    if echo "$nvidia_options" | sudo tee "$nvidia_conf" > /dev/null; then
        log_success "Created $nvidia_conf with NVIDIA options"
    else
        log_error "Failed to create $nvidia_conf"
        return 1
    fi
    
    return 0
}

# Rebuild initramfs
rebuild_initramfs() {
    log_info "Rebuilding initramfs..."

    log_info "Running mkinitcpio -P..."
    
    if sudo mkinitcpio -P; then
        log_success "Initramfs rebuilt successfully"
    else
        log_error "Failed to rebuild initramfs"
        return 1
    fi
    
    return 0
}

# Configure NVIDIA environment variables for Hyprland
configure_nvidia_environment() {
    log_info "Configuring NVIDIA environment variables for Hyprland..."
    
    local hypr_config_dir="$HOME/.config/hypr"
    local env_file="$hypr_config_dir/env_variables.conf"
    
    # NVIDIA environment variables for Wayland/Hyprland
    local nvidia_env_vars="# NVIDIA Environment Variables
env = LIBVA_DRIVER_NAME,nvidia
env = GBM_BACKEND,nvidia_drm
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = NVD_BACKEND,direct

cursor {
    no_hardware_cursors = true
}"

    # Create directory if it doesn't exist
    if ! mkdir -p "$hypr_config_dir"; then
        log_error "Failed to create directory $hypr_config_dir"
        return 1
    fi
    
    # Check if NVIDIA variables already exist
    if [[ -f "$env_file" ]] && grep -q "LIBVA_DRIVER_NAME,nvidia" "$env_file"; then
        log_warn "NVIDIA environment variables already present in $env_file"
    else
        log_info "Adding NVIDIA environment variables to $env_file..."
        
        if echo "$nvidia_env_vars" >> "$env_file"; then
            log_success "NVIDIA environment variables added to $env_file"
        else
            log_error "Failed to write to $env_file"
            return 1
        fi
    fi
    
    return 0
}

# Enable NVIDIA services (but don't start them automatically)
configure_nvidia_services() {
    log_info "Configuring NVIDIA services..."
    
    for service in "${NVIDIA_SERVICES[@]}"; do
        log_info "Enabling $service..."
        
        if sudo systemctl enable "$service"; then
            log_success "Enabled $service"
        else
            log_warn "Failed to enable $service (may not be critical)"
        fi
    done
    
    return 0
}

# Configure NVIDIA kernel parameters for refind (MUX switch support)
configure_nvidia_kernel_params() {
    log_info "Configuring NVIDIA kernel parameters for MUX switch support..."
    
    local refind_conf="/boot/refind_linux.conf"
    local nvidia_param="nvidia.NVreg_PreserveVideoMemoryAllocations=1"

    # Check if refind configuration exists
    if [[ ! -f "$refind_conf" ]]; then
        log_warn "Refind configuration not found at $refind_conf, skipping kernel parameter configuration"
        return 0
    fi
    
    # Check if parameter already exists
    if grep -q "$nvidia_param" "$refind_conf"; then
        log_warn "NVIDIA kernel parameter already present in $refind_conf"
    else
        log_info "Adding NVIDIA kernel parameter to $refind_conf..."
        
        # Use the same sed pattern as the original install.sh for consistency
        if sudo sed -i "s/\"Boot using default options\"/&/; s/\(.*\"Boot using default options\".*\)\"/\1 $nvidia_param\"/" "$refind_conf"; then
            log_success "NVIDIA kernel parameter added to $refind_conf"
        else
            log_error "Failed to modify $refind_conf"
            return 1
        fi
    fi
    
    return 0
}

# Main NVIDIA installation function
install_nvidia() {
    log_info "Starting NVIDIA GPU configuration..."
    
    # Check if NVIDIA GPU is present
    if ! detect_nvidia_gpu; then
        log_warn "No NVIDIA GPU detected, skipping NVIDIA configuration"
        return 0
    fi
    
    # Install NVIDIA drivers
    if ! install_nvidia_drivers; then
        log_error "Failed to install NVIDIA drivers"
        return 1
    fi
    
    # Configure kernel modules
    if ! configure_nvidia_modules; then
        log_error "Failed to configure NVIDIA kernel modules"
        return 1
    fi
    
    # Configure modprobe settings
    if ! configure_nvidia_modprobe; then
        log_error "Failed to configure NVIDIA modprobe settings"
        return 1
    fi
    
    # Rebuild initramfs
    if ! rebuild_initramfs; then
        log_error "Failed to rebuild initramfs"
        return 1
    fi
    
    # Configure environment variables
    if ! configure_nvidia_environment; then
        log_error "Failed to configure NVIDIA environment variables"
        return 1
    fi
    
    # Configure services
    if ! configure_nvidia_services; then
        log_error "Failed to configure NVIDIA services"
        return 1
    fi
    
    # Configure kernel parameters for MUX switch support
    if ! configure_nvidia_kernel_params; then
        log_error "Failed to configure NVIDIA kernel parameters"
        return 1
    fi
    
    log_success "NVIDIA GPU configuration completed successfully"
    
    # Inform user about reboot requirement
    log_info "NVIDIA configuration complete. A system reboot is recommended to apply all changes."
    
    return 0
}

# Function to check if NVIDIA is already configured
is_nvidia_configured() {
    # Check if NVIDIA drivers are installed
    if ! pacman -Qi nvidia-dkms &> /dev/null && ! pacman -Qi nvidia-open-dkms &> /dev/null; then
        return 1
    fi
    
    # Check if modules are configured
    if ! grep -q "nvidia" /etc/mkinitcpio.conf; then
        return 1
    fi
    
    # Check if modprobe is configured
    if [[ ! -f /etc/modprobe.d/nvidia.conf ]]; then
        return 1
    fi
    
    return 0
}

# Function to validate NVIDIA installation
validate_nvidia_installation() {
    log_info "Validating NVIDIA installation..."
    
    # Check if NVIDIA drivers are loaded
    if lsmod | grep -q nvidia; then
        log_success "NVIDIA kernel modules are loaded"
    else
        log_warn "NVIDIA kernel modules are not loaded (may require reboot)"
    fi
    
    # Check if nvidia-smi works
    if command -v nvidia-smi &> /dev/null; then
        if nvidia-smi &> /dev/null; then
            log_success "nvidia-smi is working correctly"
        else
            log_warn "nvidia-smi is installed but not working (may require reboot)"
        fi
    else
        log_warn "nvidia-smi not found"
    fi
    
    # Check environment variables
    local env_file="$HOME/.config/hypr/env_variables.conf"
    if [[ -f "$env_file" ]] && grep -q "LIBVA_DRIVER_NAME,nvidia" "$env_file"; then
        log_success "NVIDIA environment variables are configured"
    else
        log_warn "NVIDIA environment variables not found"
    fi
    
    return 0
}

# Export functions for use by other modules
export -f install_nvidia
export -f detect_nvidia_gpu
export -f is_nvidia_configured
export -f validate_nvidia_installation