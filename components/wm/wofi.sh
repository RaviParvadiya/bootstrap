#!/usr/bin/env bash
#
# components/wm/wofi.sh - Wofi installer
# Handles installation, dotfiles, helper scripts, and validation.

source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"
source "$CORE_DIR/logger.sh"
source "$CORE_DIR/common.sh"

# Component metadata
readonly WOFI_COMPONENT_NAME="wofi"
readonly WOFI_CONFIG_SOURCE="$DOTFILES_DIR/wofi/.config/wofi"
readonly WOFI_CONFIG_TARGET="$HOME/.config/wofi"
readonly WOFI_BIN_DIR="$HOME/.local/bin"

# Package definitions per distribution
declare -A WOFI_PACKAGES=(
    ["arch"]="wofi"
    ["ubuntu"]="wofi"
)

# Dependencies for Wofi functionality
declare -A WOFI_DEPS=(
    ["arch"]="gtk3"
    ["ubuntu"]="libgtk-3-0"
)

# Optional packages for enhanced Wofi functionality
declare -A WOFI_OPTIONAL=(
    ["arch"]="wtype"  # For typing text in Wayland
    ["ubuntu"]="wtype"
)

#######################################
# Wofi Installation Functions
#######################################

# Install Wofi packages
install_wofi_packages() {
    local distro
    distro=$(get_distro)
    
    log_info "Installing Wofi packages for $distro..."
    
    install_packages ${WOFI_DEPS[$distro]} ${WOFI_PACKAGES[$distro]} ${WOFI_OPTIONAL[$distro]}
    
    log_success "Wofi packages installed"
}

# Configure Wofi with dotfiles
configure_wofi() {
    log_info "Configuring Wofi application launcher..."
    
    [[ ! -d "$WOFI_CONFIG_SOURCE" ]] && { log_error "Missing config: $WOFI_CONFIG_SOURCE"; return 1; }
  
    mkdir -p "$WOFI_CONFIG_TARGET"
    
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
    log_info "Creating Wofi helper scripts..."
    
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
    timeout 5 wofi --help &>/dev/null && log_debug "Wofi basic functionality OK" || log_warn "Wofi test failed"
    [[ -r "$WOFI_CONFIG_TARGET/config" ]] && log_debug "Config readable"
    [[ -r "$WOFI_CONFIG_TARGET/style.css" ]] && log_debug "Style readable"
}

# Validate Wofi installation

validate_wofi_installation() {
    command -v wofi >/dev/null || { log_error "wofi not found"; return 1; }
    [[ -d "$WOFI_CONFIG_TARGET" ]] || log_warn "Config dir missing"
    test_wofi_config
    for s in wofi-launcher wofi-run wofi-window; do
        [[ -x "$WOFI_BIN_DIR/$s" ]] && log_debug "Found script: $s" || log_warn "Missing script: $s"
    done
    log_success "Wofi validation passed"
}

#######################################
# Main Installation Function
#######################################

# Main Wofi installation function
install_wofi() {
    log_section "Installing Wofi Application Launcher"
    
    install_wofi_packages || return 1
    configure_wofi || return 1
    
    ask_yes_no "Create Wofi helper scripts?" "y" && setup_wofi_scripts

    validate_wofi_installation
    
    log_success "Wofi installation complete. Use 'wofi-launcher' or configure keybindings."
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
    
    log_success "Wofi uninstalled"
}

# Export essential functions
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && export -f install_wofi