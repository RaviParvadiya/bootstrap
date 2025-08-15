#!/bin/bash

# Arch Linux main orchestrator
# Handles the complete Arch Linux installation process

# Run Arch Linux installation
run_arch_installation() {
    log_section "Arch Linux Installation"
    
    # Source Arch-specific modules
    source "$DISTROS_DIR/arch/packages.sh"
    source "$DISTROS_DIR/arch/repositories.sh"
    source "$DISTROS_DIR/arch/services.sh"
    
    # Hardware-specific modules
    if [[ -f "$DISTROS_DIR/arch/hardware/nvidia.sh" ]]; then
        source "$DISTROS_DIR/arch/hardware/nvidia.sh"
    fi
    
    # Update system first
    update_arch_system
    
    # Setup repositories
    setup_arch_repositories
    
    # Install selected components
    for component in "${SELECTED_COMPONENTS[@]}"; do
        install_arch_component "$component"
    done
    
    # Configure services
    configure_arch_services
    
    log_success "Arch Linux installation completed"
}

# Update Arch system
update_arch_system() {
    log_info "Updating Arch Linux system..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would update system packages"
        return 0
    fi
    
    sudo pacman -Syu --noconfirm
}

# Install component for Arch Linux
install_arch_component() {
    local component="$1"
    
    log_info "Installing component: $component"
    
    case "$component" in
        "terminal")
            source "$COMPONENTS_DIR/terminal/alacritty.sh"
            source "$COMPONENTS_DIR/terminal/kitty.sh"
            install_terminal_components
            ;;
        "shell")
            source "$COMPONENTS_DIR/shell/zsh.sh"
            source "$COMPONENTS_DIR/shell/starship.sh"
            install_shell_components
            ;;
        "editor")
            source "$COMPONENTS_DIR/editor/neovim.sh"
            source "$COMPONENTS_DIR/editor/vscode.sh"
            install_editor_components
            ;;
        "wm")
            source "$COMPONENTS_DIR/wm/hyprland.sh"
            source "$COMPONENTS_DIR/wm/waybar.sh"
            source "$COMPONENTS_DIR/wm/wofi.sh"
            source "$COMPONENTS_DIR/wm/swaync.sh"
            install_wm_components
            ;;
        "dev-tools")
            source "$COMPONENTS_DIR/dev-tools/git.sh"
            source "$COMPONENTS_DIR/dev-tools/docker.sh"
            source "$COMPONENTS_DIR/dev-tools/languages.sh"
            install_dev_tools
            ;;
        "hardware")
            install_hardware_components
            ;;
        *)
            log_warn "Unknown component: $component"
            ;;
    esac
}

# Install hardware-specific components
install_hardware_components() {
    log_info "Installing hardware-specific components..."
    
    # NVIDIA GPU support
    if lspci | grep -i nvidia >/dev/null 2>&1; then
        if ask_yes_no "NVIDIA GPU detected. Install NVIDIA drivers?"; then
            install_nvidia_drivers
        fi
    fi
    
    # ASUS TUF specific configurations
    local product_name=""
    if [[ -r /sys/class/dmi/id/product_name ]]; then
        product_name=$(cat /sys/class/dmi/id/product_name)
        if [[ "$product_name" =~ "ASUS".*"TUF" ]]; then
            log_info "ASUS TUF laptop detected"
            if ask_yes_no "Apply ASUS TUF specific configurations?"; then
                configure_asus_tuf
            fi
        fi
    fi
}

# Placeholder functions for component installation
install_terminal_components() {
    log_info "Terminal components installation not yet implemented"
}

install_shell_components() {
    log_info "Shell components installation not yet implemented"
}

install_editor_components() {
    log_info "Editor components installation not yet implemented"
}

install_wm_components() {
    log_info "Window manager components installation not yet implemented"
}

install_dev_tools() {
    log_info "Development tools installation not yet implemented"
}

install_nvidia_drivers() {
    log_info "NVIDIA drivers installation not yet implemented"
}

configure_asus_tuf() {
    log_info "ASUS TUF configuration not yet implemented"
}