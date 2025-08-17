#!/bin/bash

# Arch Linux Main Orchestrator
# Main entry point for Arch Linux installations

# Source core utilities
source "$(dirname "${BASH_SOURCE[0]}")/../../core/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../core/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../core/validator.sh"

# Source Arch-specific modules
source "$(dirname "${BASH_SOURCE[0]}")/packages.sh"
source "$(dirname "${BASH_SOURCE[0]}")/repositories.sh"
source "$(dirname "${BASH_SOURCE[0]}")/services.sh"

# Source hardware modules
source "$(dirname "${BASH_SOURCE[0]}")/hardware/nvidia.sh"

# Main Arch Linux installation orchestrator
arch_main_install() {
    local selected_components=("$@")
    local dry_run="${DRY_RUN:-false}"
    
    log_info "Starting Arch Linux installation process..."
    
    # Validate system requirements
    if ! validate_arch_system; then
        log_error "System validation failed"
        return 1
    fi
    
    # Update system first
    if ! arch_update_system; then
        log_error "Failed to update system"
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
        user_preferences="$user_preferences,gaming"
    fi
    
    # Install main package set with auto-detection
    log_info "Installing packages with auto-detected system conditions..."
    if ! arch_install_packages_auto "all" "$user_preferences"; then
        log_warn "Some packages failed to install, continuing..."
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

# Validate Arch Linux system requirements
validate_arch_system() {
    log_info "Validating Arch Linux system..."
    
    # Check if running on Arch Linux
    if ! grep -q "Arch Linux" /etc/os-release 2>/dev/null; then
        log_error "This script is designed for Arch Linux"
        return 1
    fi
    
    # Check internet connectivity
    if ! check_internet; then
        log_error "Internet connection required"
        return 1
    fi
    
    # Check if pacman is available
    if ! command -v pacman >/dev/null 2>&1; then
        log_error "pacman package manager not found"
        return 1
    fi
    
    # Check available disk space (at least 5GB)
    local available_space
    available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 5242880 ]]; then  # 5GB in KB
        log_warn "Low disk space detected (less than 5GB available)"
    fi
    
    log_success "System validation passed"
    return 0
}

# Update Arch Linux system
arch_update_system() {
    log_info "Updating Arch Linux system..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would run: pacman -Syu --noconfirm"
        return 0
    fi
    
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
    
    # Check for NVIDIA GPU and offer installation
    if detect_nvidia_gpu; then
        if ask_yes_no "NVIDIA GPU detected. Would you like to install NVIDIA drivers?"; then
            if ! install_nvidia "${DRY_RUN:-false}"; then
                log_warn "NVIDIA installation failed, continuing with other components"
            fi
        else
            log_info "NVIDIA installation skipped by user"
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
    
    # Check if component script exists
    local component_script="$(dirname "${BASH_SOURCE[0]}")/../../components/$component"
    
    # Try different possible locations for the component
    local possible_locations=(
        "../../components/terminal/$component.sh"
        "../../components/shell/$component.sh"
        "../../components/editor/$component.sh"
        "../../components/wm/$component.sh"
        "../../components/dev-tools/$component.sh"
    )
    
    local found_script=""
    for location in "${possible_locations[@]}"; do
        local full_path="$(dirname "${BASH_SOURCE[0]}")/$location"
        if [[ -f "$full_path" ]]; then
            found_script="$full_path"
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