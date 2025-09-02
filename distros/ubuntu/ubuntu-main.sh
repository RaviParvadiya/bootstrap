#!/usr/bin/env bash

# Ubuntu Main Orchestrator
# Main entry point for Ubuntu installations (Hyprland environment setup)

# Source core utilities
source "$(dirname "${BASH_SOURCE[0]}")/../../core/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../core/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../core/validator.sh"

# Source Ubuntu-specific modules
source "$(dirname "${BASH_SOURCE[0]}")/packages.sh"
source "$(dirname "${BASH_SOURCE[0]}")/repositories.sh"
source "$(dirname "${BASH_SOURCE[0]}")/hyprland.sh"
source "$(dirname "${BASH_SOURCE[0]}")/services.sh"

# Main Ubuntu installation orchestrator
ubuntu_main_install() {
    local selected_components=("$@")
    local dry_run="${DRY_RUN:-false}"
    
    log_info "Starting Ubuntu Hyprland environment installation..."
    
    # Validate system requirements
    if ! validate_ubuntu_system; then
        log_error "System validation failed"
        return 1
    fi
    
    # Update system first
    if ! ubuntu_update_system; then
        log_error "Failed to update system"
        return 1
    fi
    
    # Setup additional repositories (PPAs, flatpak, snap)
    if ! ubuntu_setup_repositories; then
        log_error "Failed to setup repositories"
        return 1
    fi
    
    # Install base packages required for Hyprland environment
    if ! ubuntu_install_base_packages; then
        log_error "Failed to install base packages"
        return 1
    fi
    
    # Install packages from Ubuntu package list
    if ! ubuntu_install_packages_from_list; then
        log_warn "Some packages from Ubuntu package list failed to install"
        # Continue with installation as some packages may be optional
    fi
    
    # Install and configure Hyprland
    if ! ubuntu_install_hyprland; then
        log_error "Failed to install Hyprland"
        return 1
    fi
    
    # Install selected components
    for component in "${selected_components[@]}"; do
        log_info "Installing component: $component"
        if ! ubuntu_install_component "$component"; then
            log_warn "Failed to install component: $component"
            # Continue with other components
        fi
    done
    
    # Configure services (but don't enable them automatically)
    ubuntu_configure_services "${selected_components[@]}"
    
    log_success "Ubuntu Hyprland environment installation completed"
    
    # Show summary
    ubuntu_show_installation_summary "${selected_components[@]}"
}

# Validate Ubuntu system requirements
validate_ubuntu_system() {
    log_info "Validating Ubuntu system..."
    
    # Check if running on Ubuntu
    if ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
        log_error "This script is designed for Ubuntu"
        return 1
    fi
    
    # Check Ubuntu version (minimum 20.04)
    local ubuntu_version
    ubuntu_version=$(grep "VERSION_ID" /etc/os-release | cut -d'"' -f2)
    if [[ -n "$ubuntu_version" ]]; then
        local major_version="${ubuntu_version%%.*}"
        if [[ "$major_version" -lt 20 ]]; then
            log_error "Ubuntu 20.04 or later is required (found: $ubuntu_version)"
            return 1
        fi
        log_info "Ubuntu version: $ubuntu_version"
    fi
    
    # Check internet connectivity
    if ! check_internet; then
        log_error "Internet connection required"
        return 1
    fi
    
    # Check if apt is available
    if ! command -v apt >/dev/null 2>&1; then
        log_error "apt package manager not found"
        return 1
    fi
    
    # Check available disk space (at least 10GB for Hyprland build)
    local available_space
    available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 10485760 ]]; then  # 10GB in KB
        log_warn "Low disk space detected (less than 10GB available)"
        log_warn "Hyprland compilation requires significant disk space"
    fi
    
    # Check if we're in a desktop environment (warn about potential conflicts)
    if [[ -n "$XDG_CURRENT_DESKTOP" ]]; then
        log_warn "Existing desktop environment detected: $XDG_CURRENT_DESKTOP"
        log_warn "Installing Hyprland may conflict with existing desktop environment"
        
        if ! ask_yes_no "Continue with installation?"; then
            log_info "Installation cancelled by user"
            return 1
        fi
    fi
    
    log_success "System validation passed"
    return 0
}

# Update Ubuntu system
ubuntu_update_system() {
    log_info "Updating Ubuntu system..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would run: apt update && apt upgrade -y"
        return 0
    fi
    
    # Update package database
    if ! sudo apt update; then
        log_error "Failed to update package database"
        return 1
    fi
    
    # Upgrade system packages
    if ! sudo apt upgrade -y; then
        log_error "Failed to upgrade system packages"
        return 1
    fi
    
    log_success "System updated successfully"
    return 0
}

# Install component packages and configurations
ubuntu_install_component() {
    local component="$1"
    
    log_info "Installing Ubuntu component: $component"
    
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
    
    # Set Ubuntu-specific environment for component installation
    export DISTRO="ubuntu"
    export PACKAGE_MANAGER="apt"
    
    # Source and execute component installation
    if source "$found_script" && command -v "install_$component" >/dev/null 2>&1; then
        "install_$component"
    else
        log_warn "Installation function not found for component: $component"
        return 1
    fi
    
    return 0
}

# Install component-specific packages for Ubuntu
ubuntu_install_component_packages() {
    local component="$1"
    shift
    local packages=("$@")
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        log_warn "No packages specified for component: $component"
        return 0
    fi
    
    log_info "Installing packages for component $component: ${packages[*]}"
    
    # Separate packages by type (similar to package list parsing)
    local apt_packages=()
    local snap_packages=()
    local flatpak_packages=()
    
    for package in "${packages[@]}"; do
        if [[ "$package" =~ ^snap: ]]; then
            snap_packages+=("${package#snap:}")
        elif [[ "$package" =~ ^flatpak: ]]; then
            flatpak_packages+=("${package#flatpak:}")
        else
            apt_packages+=("$package")
        fi
    done
    
    # Install packages by type
    local install_success=true
    
    if [[ ${#apt_packages[@]} -gt 0 ]]; then
        if ! ubuntu_install_apt_packages "${apt_packages[@]}"; then
            install_success=false
        fi
    fi
    
    if [[ ${#snap_packages[@]} -gt 0 ]]; then
        if ! ubuntu_install_snap_packages "${snap_packages[@]}"; then
            install_success=false
        fi
    fi
    
    if [[ ${#flatpak_packages[@]} -gt 0 ]]; then
        if ! ubuntu_install_flatpak_packages "${flatpak_packages[@]}"; then
            install_success=false
        fi
    fi
    
    return $([[ "$install_success" == "true" ]] && echo 0 || echo 1)
}



# Show installation summary
ubuntu_show_installation_summary() {
    local installed_components=("$@")
    
    log_info "=== Installation Summary ==="
    log_info "Distribution: Ubuntu (Hyprland Environment)"
    log_info "Installed components:"
    
    for component in "${installed_components[@]}"; do
        log_info "  - $component"
    done
    
    log_info ""
    log_info "Next steps:"
    log_info "1. Log out of your current session"
    log_info "2. Select 'Hyprland' from the session menu at login"
    log_info "3. Review installed services with: systemctl list-unit-files --state=disabled"
    log_info "4. Enable desired services manually with: sudo systemctl enable <service>"
    log_info "5. Check configuration files in your dotfiles directory"
    log_info ""
    log_info "Hyprland keybindings:"
    log_info "  - Super+Return: Open terminal"
    log_info "  - Super+D: Application launcher"
    log_info "  - Super+Q: Close window"
    log_info "  - Super+Shift+E: Exit Hyprland"
}

# Check if running in Wayland session
ubuntu_is_wayland_session() {
    [[ "$XDG_SESSION_TYPE" == "wayland" ]]
}

# Check if running in X11 session
ubuntu_is_x11_session() {
    [[ "$XDG_SESSION_TYPE" == "x11" ]]
}

# Get Ubuntu codename
ubuntu_get_codename() {
    grep "UBUNTU_CODENAME" /etc/os-release | cut -d'=' -f2
}

# Get Ubuntu version
ubuntu_get_version() {
    grep "VERSION_ID" /etc/os-release | cut -d'"' -f2
}

# Check if package is from universe repository
ubuntu_is_universe_enabled() {
    grep -q "^deb.*universe" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null
}

# Export main function for external use
export -f ubuntu_main_install
export -f validate_ubuntu_system
export -f ubuntu_update_system
export -f ubuntu_install_component
export -f ubuntu_install_component_packages
export -f ubuntu_configure_services
export -f ubuntu_show_installation_summary
export -f ubuntu_is_wayland_session
export -f ubuntu_is_x11_session
export -f ubuntu_get_codename
export -f ubuntu_get_version
export -f ubuntu_is_universe_enabled