#!/usr/bin/env bash

# components/wm/wofi.sh - Wofi application launcher installation and configuration
# This module handles the installation and configuration of Wofi application launcher
# with proper dotfiles integration, theme support, and cross-distribution compatibility.

source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"
source "$CORE_DIR/logger.sh"
source "$CORE_DIR/common.sh"

# Component metadata
readonly WOFI_COMPONENT_NAME="wofi"
readonly WOFI_CONFIG_SOURCE="$DOTFILES_DIR/wofi/.config/wofi"
readonly WOFI_CONFIG_TARGET="$HOME/.config/wofi"

#######################################
# Wofi Installation Functions
#######################################

# Check if Wofi is already installed
is_wofi_installed() {
    command -v wofi >/dev/null 2>&1
}

# Configure Wofi with dotfiles
configure_wofi() {
    log_info "Configuring Wofi application launcher..."
    
    if [[ ! -d "$WOFI_CONFIG_SOURCE" ]]; then
        log_error "Wofi configuration source not found: $WOFI_CONFIG_SOURCE"
        return 1
    fi
    
    # Create configuration directory
    if ! mkdir -p "$WOFI_CONFIG_TARGET"; then
        log_error "Failed to create Wofi config directory: $WOFI_CONFIG_TARGET"
        return 1
    fi
    
    # Copy configuration files using symlinks for easy updates
    log_info "Creating symlinks for Wofi configuration files..."
    
    # Find all configuration files in the source directory
    while IFS= read -r -d '' config_file; do
        local relative_path="${config_file#$WOFI_CONFIG_SOURCE/}"
        local target_file="$WOFI_CONFIG_TARGET/$relative_path"
        local target_dir
        target_dir=$(dirname "$target_file")
        
        # Create target directory if needed
        if [[ ! -d "$target_dir" ]]; then
            mkdir -p "$target_dir"
        fi
        
        # Create symlink
        if ! create_symlink "$config_file" "$target_file"; then
            log_warn "Failed to create symlink for: $relative_path"
        else
            log_debug "Created symlink: $target_file -> $config_file"
        fi
    done < <(find "$WOFI_CONFIG_SOURCE" -type f -print0)
    
    # Create default config if none exists
    create_default_wofi_config
    
    log_success "Wofi configuration completed"
    return 0
}

# Create default Wofi configuration if none exists
create_default_wofi_config() {
    local config_file="$WOFI_CONFIG_TARGET/config"
    
    # Only create if no config exists and no style.css exists
    if [[ ! -f "$config_file" && ! -f "$WOFI_CONFIG_TARGET/style.css" ]]; then
        log_info "Creating default Wofi configuration..."
        
        local default_config="width=600
height=400
location=center
show=drun
prompt=Search...
filter_rate=100
allow_markup=true
no_actions=true
halign=fill
orientation=vertical
content_halign=fill
insensitive=true
allow_images=true
image_size=40
gtk_dark=true"
        
        if echo "$default_config" > "$config_file"; then
            log_debug "Created default Wofi config"
        else
            log_warn "Failed to create default Wofi config"
        fi
    fi
    
    return 0
}

# Setup Wofi keybindings helper script
setup_wofi_scripts() {
    log_info "Setting up Wofi helper scripts..."
    
    local scripts_dir="$HOME/.local/bin"
    mkdir -p "$scripts_dir"
    
    # Create wofi launcher script
    local launcher_script="$scripts_dir/wofi-launcher"
    local launcher_content="#!/bin/bash
# Wofi application launcher script

# Kill any existing wofi instances
pkill wofi

# Launch wofi
wofi --show drun --allow-images --allow-markup --insensitive --prompt \"Launch: \"
"
    
    if echo "$launcher_content" > "$launcher_script"; then
        chmod +x "$launcher_script"
        log_debug "Created Wofi launcher script: $launcher_script"
    else
        log_warn "Failed to create Wofi launcher script"
    fi
    
    # Create wofi run script (for commands)
    local run_script="$scripts_dir/wofi-run"
    local run_content="#!/bin/bash
# Wofi run command script

# Kill any existing wofi instances
pkill wofi

# Launch wofi in run mode
wofi --show run --allow-markup --insensitive --prompt \"Run: \"
"
    
    if echo "$run_content" > "$run_script"; then
        chmod +x "$run_script"
        log_debug "Created Wofi run script: $run_script"
    else
        log_warn "Failed to create Wofi run script"
    fi
    
    # Create wofi window switcher script
    local window_script="$scripts_dir/wofi-window"
    local window_content="#!/bin/bash
# Wofi window switcher script

# Kill any existing wofi instances
pkill wofi

# Launch wofi in window mode (if supported)
if wofi --help | grep -q \"window\"; then
    wofi --show window --allow-markup --insensitive --prompt \"Window: \"
else
    # Fallback to drun if window mode not supported
    wofi --show drun --allow-images --allow-markup --insensitive --prompt \"Launch: \"
fi
"
    
    if echo "$window_content" > "$window_script"; then
        chmod +x "$window_script"
        log_debug "Created Wofi window script: $window_script"
    else
        log_warn "Failed to create Wofi window script"
    fi
    
    log_success "Wofi helper scripts created"
    return 0
}

# Test Wofi configuration
test_wofi_config() {
    log_info "Testing Wofi configuration..."
    
    # Test if wofi can start and exit cleanly
    if timeout 5 wofi --help >/dev/null 2>&1; then
        log_success "Wofi basic functionality test passed"
    else
        log_warn "Wofi basic functionality test failed"
        return 1
    fi
    
    # Check if config file is readable
    if [[ -f "$WOFI_CONFIG_TARGET/config" ]]; then
        if [[ -r "$WOFI_CONFIG_TARGET/config" ]]; then
            log_debug "Wofi config file is readable"
        else
            log_warn "Wofi config file is not readable"
        fi
    fi
    
    # Check if style file exists and is readable
    if [[ -f "$WOFI_CONFIG_TARGET/style.css" ]]; then
        if [[ -r "$WOFI_CONFIG_TARGET/style.css" ]]; then
            log_debug "Wofi style file is readable"
        else
            log_warn "Wofi style file is not readable"
        fi
    fi
    
    return 0
}

# Validate Wofi installation
validate_wofi_installation() {
    log_info "Validating Wofi installation..."
    
    # Check if binary is available
    if ! command -v wofi >/dev/null 2>&1; then
        log_error "Wofi binary not found in PATH"
        return 1
    fi
    
    # Check if configuration directory exists
    if [[ ! -d "$WOFI_CONFIG_TARGET" ]]; then
        log_warn "Wofi configuration directory not found: $WOFI_CONFIG_TARGET"
    fi
    
    # Test Wofi version (basic functionality test)
    if ! wofi --version >/dev/null 2>&1; then
        log_error "Wofi version check failed"
        return 1
    fi
    
    # Test configuration
    if ! test_wofi_config; then
        log_warn "Wofi configuration test failed"
    fi
    
    # Check if helper scripts exist
    local scripts=("wofi-launcher" "wofi-run" "wofi-window")
    for script in "${scripts[@]}"; do
        if [[ -x "$HOME/.local/bin/$script" ]]; then
            log_debug "Found Wofi helper script: $script"
        else
            log_warn "Wofi helper script not found: $script"
        fi
    done
    
    log_success "Wofi installation validation passed"
    return 0
}

#######################################
# Main Installation Function
#######################################

# Main Wofi installation function
install_wofi() {
    log_section "Configuring Wofi Application Launcher"
    
    # Check if already installed (packages should be installed by main system)
    if ! is_wofi_installed; then
        log_error "Wofi not found. Ensure packages are installed by the main system first."
        return 1
    fi
    
    # Configure Wofi
    if ! configure_wofi; then
        log_error "Failed to configure Wofi"
        return 1
    fi
    
    # Setup helper scripts
    if ask_yes_no "Create Wofi helper scripts?" "y"; then
        setup_wofi_scripts
    fi
    
    # Validate installation
    if ! validate_wofi_installation; then
        log_error "Wofi installation validation failed"
        return 1
    fi
    
    log_success "Wofi configuration completed successfully"
    log_info "Note: Use 'wofi-launcher' command or configure keybindings in Hyprland to launch Wofi"
    return 0
}

# Uninstall Wofi (for testing/cleanup)
uninstall_wofi() {
    log_info "Uninstalling Wofi..."
    
    local distro
    distro=$(get_distro)
    
    # Remove packages
    case "$distro" in
        "arch")
            sudo pacman -Rns --noconfirm wofi 2>/dev/null || true
            ;;
        "ubuntu")
            sudo apt-get remove --purge -y wofi 2>/dev/null || true
            ;;
    esac
    
    # Remove configuration
    if [[ -d "$WOFI_CONFIG_TARGET" ]]; then
        rm -rf "$WOFI_CONFIG_TARGET"
        log_info "Wofi configuration removed"
    fi
    
    # Remove helper scripts
    local scripts=("wofi-launcher" "wofi-run" "wofi-window")
    for script in "${scripts[@]}"; do
        if [[ -f "$HOME/.local/bin/$script" ]]; then
            rm -f "$HOME/.local/bin/$script"
            log_debug "Removed Wofi helper script: $script"
        fi
    done
    
    log_success "Wofi uninstalled successfully"
    return 0
}

# Export essential functions
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && export -f install_wofi configure_wofi is_wofi_installed