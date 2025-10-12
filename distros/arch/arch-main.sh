#!/usr/bin/env bash

# Arch Linux Main Orchestrator
# Main entry point for Arch Linux installations

# Initialize all project paths
source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"

# Source core utilities
source "$CORE_DIR/common.sh"
source "$CORE_DIR/logger.sh"

# Source Arch-specific modules
source "$DISTROS_DIR/arch/packages.sh"
source "$DISTROS_DIR/arch/repositories.sh"
source "$DISTROS_DIR/arch/services.sh"

# Source hardware modules
source "$DISTROS_DIR/arch/hardware/nvidia.sh"

# Main Arch Linux installation orchestrator
arch_main_install() {
    local selected_components=("$@")
    
    log_info "Starting Arch Linux installation process..."
    
    # Update system first
    if ! arch_update_system; then
        return 1
    fi
    
    # Setup repositories (multilib, chaotic-aur)
    if ! arch_setup_repositories; then
        log_error "Failed to setup repositories"
        return 1
    fi
    
    # Install AUR helper if needed
    if ! arch_ensure_aur_helper; then
        log_error "Failed to setup AUR helper"
        return 1
    fi
    
    # Configure system settings (pacman, makepkg, etc.)
    if ! arch_setup_system; then
        log_error "Failed to configure system settings"
        return 1
    fi
    
    # Install base packages
    if ! arch_install_base_packages; then
        log_error "Failed to install base packages"
        return 1
    fi
    
    # Install packages based on user preferences and auto-detected conditions
    local user_preferences=""
    
    # Ask user about optional package categories
    if ask_yes_no "Would you like to install gaming packages?"; then
        user_preferences="gaming"
    fi
    
    # Install main package set with auto-detection
    log_info "Installing package set..."
    
    if ! arch_install_packages_auto "all" "$user_preferences"; then
        log_warn "Some packages failed to install, continuing..."
        # Don't return error here, continue with installation
    fi
    
    # Check for hardware-specific configurations
    arch_configure_hardware
    
    # Install selected components
    for component in "${selected_components[@]}"; do
        log_info "Installing component: $component"
        if ! arch_install_component "$component"; then
            log_warn "Failed to install component: $component"
            # Continue with other components
        fi
    done
    
    # Configure services (but don't enable them automatically)
    arch_configure_services "${selected_components[@]}"
    
    log_success "Arch Linux installation process completed"
    
    # Show summary
    arch_show_installation_summary "${selected_components[@]}"
}

# Update Arch Linux system
arch_update_system() {
    log_info "Updating Arch Linux system..."
    
    # Update package database and system
    if ! sudo pacman -Syu --noconfirm; then
        log_error "Failed to update system"
        return 1
    fi
    
    log_success "System updated successfully"
    return 0
}

# Configure hardware-specific settings
arch_configure_hardware() {
    log_info "Configuring hardware-specific settings..."
    
    # Check for NVIDIA GPU and configure if packages are installed
    if detect_nvidia_gpu; then
        if ask_yes_no "NVIDIA GPU detected. Would you like to configure NVIDIA drivers?"; then
            if ! configure_nvidia; then
                log_warn "NVIDIA configuration failed, continuing with other components"
            fi
        else
            log_info "NVIDIA configuration skipped by user"
        fi
    fi
    
    # Future hardware configurations can be added here
    # e.g., AMD GPU, Intel GPU, specific laptop models, etc.
    
    return 0
}

# Install component packages and configurations
arch_install_component() {
    local component="$1"
    
    log_info "Installing Arch component: $component"
    
    # Try different possible locations for the component
    local possible_locations=(
        "$COMPONENTS_DIR/terminal/$component.sh"
        "$COMPONENTS_DIR/shell/$component.sh"
        "$COMPONENTS_DIR/editor/$component.sh"
        "$COMPONENTS_DIR/wm/$component.sh"
        "$COMPONENTS_DIR/dev-tools/$component.sh"
    )
    
    local found_script=""
    for location in "${possible_locations[@]}"; do
        if [[ -f "$location" ]]; then
            found_script="$location"
            break
        fi
    done
    
    if [[ -z "$found_script" ]]; then
        log_warn "Component script not found for: $component"
        return 1
    fi
    
    # Source and execute component installation
    if source "$found_script" && command -v "install_$component" >/dev/null 2>&1; then
        "install_$component"
    else
        log_warn "Installation function not found for component: $component"
        return 1
    fi
    
    return 0
}

# Show installation summary
arch_show_installation_summary() {
    local installed_components=("$@")
    
    log_info "=== Installation Summary ==="
    log_info "Distribution: Arch Linux"
    log_info "Installed components:"
    
    for component in "${installed_components[@]}"; do
        log_info "  - $component"
    done
    
    log_info ""
    log_info "Next steps:"
    log_info "1. Review installed services with: systemctl list-unit-files --state=disabled"
    log_info "2. Enable desired services manually with: systemctl enable <service>"
    log_info "3. Reboot or restart your session to apply all changes"
    log_info "4. Check configuration files in your dotfiles directory"
}

# Export main function for external use
export -f arch_main_install