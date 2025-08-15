#!/bin/bash

# NVIDIA GPU configuration for Arch Linux
# Handles NVIDIA driver installation and MUX switch support

# Install NVIDIA drivers
install_nvidia_drivers() {
    log_info "Installing NVIDIA drivers..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install NVIDIA drivers"
        return 0
    fi
    
    # Install NVIDIA packages
    local nvidia_packages=(
        "nvidia-dkms"
        "nvidia-utils"
        "lib32-nvidia-utils"
        "nvidia-settings"
        "vulkan-icd-loader"
        "lib32-vulkan-icd-loader"
    )
    
    install_pacman_packages "${nvidia_packages[@]}"
    
    # Configure NVIDIA
    configure_nvidia_settings
    configure_nvidia_modules
    configure_nvidia_environment
    
    log_success "NVIDIA drivers installed and configured"
}

# Configure NVIDIA settings
configure_nvidia_settings() {
    log_info "Configuring NVIDIA settings..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would configure NVIDIA settings"
        return 0
    fi
    
    # Create nvidia configuration directory
    sudo mkdir -p /etc/X11/xorg.conf.d
    
    # Create basic NVIDIA X11 configuration
    sudo tee /etc/X11/xorg.conf.d/20-nvidia.conf > /dev/null << 'EOF'
Section "Device"
    Identifier "NVIDIA Card"
    Driver "nvidia"
    VendorName "NVIDIA Corporation"
    Option "NoLogo" "true"
EndSection
EOF
    
    log_success "NVIDIA X11 configuration created"
}

# Configure NVIDIA kernel modules
configure_nvidia_modules() {
    log_info "Configuring NVIDIA kernel modules..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would configure NVIDIA kernel modules"
        return 0
    fi
    
    # Add NVIDIA modules to mkinitcpio
    sudo sed -i 's/^MODULES=(/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm /' /etc/mkinitcpio.conf
    
    # Rebuild initramfs
    sudo mkinitcpio -P
    
    # Configure modprobe settings
    sudo tee /etc/modprobe.d/nvidia.conf > /dev/null << 'EOF'
# Enable NVIDIA DRM kernel mode setting
options nvidia-drm modeset=1

# Enable NVIDIA framebuffer device
options nvidia_drm fbdev=1
EOF
    
    log_success "NVIDIA kernel modules configured"
}

# Configure NVIDIA environment variables
configure_nvidia_environment() {
    log_info "Configuring NVIDIA environment variables..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would configure NVIDIA environment variables"
        return 0
    fi
    
    # Create environment file for NVIDIA
    sudo tee /etc/environment.d/nvidia.conf > /dev/null << 'EOF'
# NVIDIA environment variables
GBM_BACKEND=nvidia-drm
__GLX_VENDOR_LIBRARY_NAME=nvidia
LIBVA_DRIVER_NAME=nvidia
__GL_GSYNC_ALLOWED=1
__GL_VRR_ALLOWED=1
WLR_NO_HARDWARE_CURSORS=1
EOF
    
    log_success "NVIDIA environment variables configured"
}

# Configure MUX switch support for ASUS TUF
configure_mux_switch() {
    log_info "Configuring MUX switch support for ASUS TUF..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would configure MUX switch support"
        return 0
    fi
    
    # Install optimus-manager for GPU switching
    if command_exists yay; then
        yay -S --noconfirm optimus-manager optimus-manager-qt
    else
        log_warn "AUR helper not available, skipping optimus-manager installation"
        return 1
    fi
    
    # Configure optimus-manager
    sudo tee /etc/optimus-manager/optimus-manager.conf > /dev/null << 'EOF'
[optimus]
switching=bbswitch
pci_power_control=no
pci_remove=no
pci_reset=no

[intel]
driver=modesetting
accel=
tearfree=

[nvidia]
modeset=yes
PAT=yes
DPI=96
options=overclocking
EOF
    
    # Enable optimus-manager service (but don't start it)
    log_info "Optimus-manager service available but not auto-started"
    log_info "Enable with: sudo systemctl enable optimus-manager"
    
    log_success "MUX switch support configured"
}

# Check NVIDIA GPU status
check_nvidia_status() {
    log_info "Checking NVIDIA GPU status..."
    
    if command_exists nvidia-smi; then
        nvidia-smi
    else
        log_warn "nvidia-smi not available"
    fi
    
    # Check if NVIDIA modules are loaded
    if lsmod | grep -q nvidia; then
        log_success "NVIDIA modules are loaded"
    else
        log_warn "NVIDIA modules not loaded"
    fi
}

# Install CUDA support (optional)
install_cuda_support() {
    if ask_yes_no "Install CUDA support for development?"; then
        log_info "Installing CUDA support..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY-RUN] Would install CUDA support"
            return 0
        fi
        
        local cuda_packages=(
            "cuda"
            "cudnn"
            "python-pycuda"
        )
        
        install_pacman_packages "${cuda_packages[@]}"
        
        log_success "CUDA support installed"
    fi
}