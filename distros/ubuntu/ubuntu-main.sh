#!/bin/bash

# Ubuntu main orchestrator
# Handles Ubuntu-specific installation process

# Run Ubuntu installation
run_ubuntu_installation() {
    log_section "Ubuntu Installation"
    
    # Source Ubuntu-specific modules
    source "$DISTROS_DIR/ubuntu/packages.sh"
    source "$DISTROS_DIR/ubuntu/repositories.sh"
    source "$DISTROS_DIR/ubuntu/hyprland.sh"
    
    # Update system first
    update_ubuntu_system
    
    # Setup repositories
    setup_ubuntu_repositories
    
    # Install Hyprland if window manager is selected
    if [[ " ${SELECTED_COMPONENTS[*]} " =~ " wm " ]]; then
        install_hyprland_ubuntu
    fi
    
    # Install selected components
    for component in "${SELECTED_COMPONENTS[@]}"; do
        install_ubuntu_component "$component"
    done
    
    log_success "Ubuntu installation completed"
}

# Update Ubuntu system
update_ubuntu_system() {
    log_info "Updating Ubuntu system..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would update system packages"
        return 0
    fi
    
    sudo apt-get update
    sudo apt-get upgrade -y
}

# Install component for Ubuntu
install_ubuntu_component() {
    local component="$1"
    
    log_info "Installing component: $component"
    
    case "$component" in
        "terminal")
            install_ubuntu_terminal_components
            ;;
        "shell")
            install_ubuntu_shell_components
            ;;
        "editor")
            install_ubuntu_editor_components
            ;;
        "wm")
            install_ubuntu_wm_components
            ;;
        "dev-tools")
            install_ubuntu_dev_tools
            ;;
        "hardware")
            install_ubuntu_hardware_components
            ;;
        *)
            log_warn "Unknown component: $component"
            ;;
    esac
}

# Install hardware-specific components for Ubuntu
install_ubuntu_hardware_components() {
    log_info "Installing hardware-specific components for Ubuntu..."
    
    # NVIDIA GPU support
    if lspci | grep -i nvidia >/dev/null 2>&1; then
        if ask_yes_no "NVIDIA GPU detected. Install NVIDIA drivers?"; then
            install_ubuntu_nvidia_drivers
        fi
    fi
}

# Install NVIDIA drivers for Ubuntu
install_ubuntu_nvidia_drivers() {
    log_info "Installing NVIDIA drivers for Ubuntu..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install NVIDIA drivers"
        return 0
    fi
    
    # Install NVIDIA drivers
    sudo apt-get install -y nvidia-driver-535 nvidia-settings
    
    # Configure NVIDIA for Wayland
    sudo tee /etc/modprobe.d/nvidia.conf > /dev/null << 'EOF'
options nvidia-drm modeset=1
options nvidia_drm fbdev=1
EOF
    
    log_success "NVIDIA drivers installed for Ubuntu"
}

# Placeholder functions for component installation
install_ubuntu_terminal_components() {
    log_info "Ubuntu terminal components installation not yet implemented"
}

install_ubuntu_shell_components() {
    log_info "Ubuntu shell components installation not yet implemented"
}

install_ubuntu_editor_components() {
    log_info "Ubuntu editor components installation not yet implemented"
}

install_ubuntu_wm_components() {
    log_info "Ubuntu window manager components installation not yet implemented"
}

install_ubuntu_dev_tools() {
    log_info "Ubuntu development tools installation not yet implemented"
}