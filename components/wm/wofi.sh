#!/bin/bash

# components/wm/wofi.sh - Wofi application launcher installation and configuration
# This module handles the installation and configuration of Wofi application launcher
# with proper dotfiles integration, theme support, and cross-distribution compatibility.

# Source required modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Source core modules if not already loaded
if [[ -z "${LOGGER_SOURCED:-}" ]]; then
    source "$PROJECT_ROOT/core/logger.sh"
fi
if ! declare -f detect_distro >/dev/null 2>&1; then
    source "$PROJECT_ROOT/core/common.sh"
fi

# Component metadata
readonly WOFI_COMPONENT_NAME="wofi"
readonly WOFI_CONFIG_SOURCE="$PROJECT_ROOT/dotfiles/wofi/.config/wofi"
readonly WOFI_CONFIG_TARGET="$HOME/.config/wofi"

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

# Check if Wofi is already installed
# Returns: 0 if installed, 1 if not installed
# Requirements: 7.1 - Component installation detection
is_wofi_installed() {
    if command -v wofi >/dev/null 2>&1; then
        return 0
    fi
    
    # Also check if package is installed via package manager
    local distro
    distro=$(get_distro)
    
    case "$distro" in
        "arch")
            pacman -Qi wofi >/dev/null 2>&1
            ;;
        "ubuntu")
            dpkg -l wofi >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

# Install Wofi packages
# Returns: 0 if successful, 1 if failed
# Requirements: 7.1 - Package installation with distribution detection
install_wofi_packages() {
    local distro
    distro=$(get_distro)
    
    if [[ -z "${WOFI_PACKAGES[$distro]}" ]]; then
        log_error "Wofi packages not defined for distribution: $distro"
        return 1
    fi
    
    log_info "Installing Wofi packages for $distro..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install packages: ${WOFI_PACKAGES[$distro]}"
        log_info "[DRY-RUN] Would install dependencies: ${WOFI_DEPS[$distro]:-none}"
        log_info "[DRY-RUN] Would install optional packages: ${WOFI_OPTIONAL[$distro]:-none}"
        return 0
    fi
    
    # Install dependencies first
    if [[ -n "${WOFI_DEPS[$distro]:-}" ]]; then
        log_info "Installing Wofi dependencies..."
        local deps
        read -ra deps <<< "${WOFI_DEPS[$distro]}"
        
        for dep in "${deps[@]}"; do
            if ! install_package "$dep"; then
                log_warn "Failed to install dependency: $dep (continuing anyway)"
            fi
        done
    fi
    
    # Install main Wofi package
    local packages
    read -ra packages <<< "${WOFI_PACKAGES[$distro]}"
    
    for package in "${packages[@]}"; do
        if ! install_package "$package"; then
            log_error "Failed to install Wofi package: $package"
            return 1
        fi
    done
    
    # Install optional packages for enhanced functionality
    if [[ -n "${WOFI_OPTIONAL[$distro]:-}" ]]; then
        log_info "Installing optional Wofi packages..."
        local optional_packages
        read -ra optional_packages <<< "${WOFI_OPTIONAL[$distro]}"
        
        for opt_package in "${optional_packages[@]}"; do
            if ! install_package "$opt_package"; then
                log_warn "Failed to install optional package: $opt_package (continuing anyway)"
            fi
        done
    fi
    
    log_success "Wofi packages installed successfully"
    return 0
}

# Configure Wofi with dotfiles
# Returns: 0 if successful, 1 if failed
# Requirements: 7.1, 7.2 - Configuration management with dotfiles integration
configure_wofi() {
    log_info "Configuring Wofi application launcher..."
    
    if [[ ! -d "$WOFI_CONFIG_SOURCE" ]]; then
        log_error "Wofi configuration source not found: $WOFI_CONFIG_SOURCE"
        return 1
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create configuration directory: $WOFI_CONFIG_TARGET"
        log_info "[DRY-RUN] Would copy configurations from: $WOFI_CONFIG_SOURCE"
        return 0
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
# Returns: 0 if successful, 1 if failed
create_default_wofi_config() {
    local config_file="$WOFI_CONFIG_TARGET/config"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create default Wofi config if needed"
        return 0
    fi
    
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
# Returns: 0 if successful, 1 if failed
setup_wofi_scripts() {
    log_info "Setting up Wofi helper scripts..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create Wofi helper scripts"
        return 0
    fi
    
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
# Returns: 0 if valid, 1 if invalid
test_wofi_config() {
    log_info "Testing Wofi configuration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would test Wofi configuration"
        return 0
    fi
    
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
# Returns: 0 if valid, 1 if invalid
# Requirements: 10.1 - Post-installation validation
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
# Returns: 0 if successful, 1 if failed
# Requirements: 7.1, 7.2 - Complete component installation
install_wofi() {
    log_section "Installing Wofi Application Launcher"
    
    # Check if already installed
    if is_wofi_installed; then
        log_info "Wofi is already installed"
        if ! ask_yes_no "Do you want to reconfigure Wofi?" "n"; then
            log_info "Skipping Wofi installation"
            return 0
        fi
    fi
    
    # Validate distribution support
    local distro
    distro=$(get_distro)
    if [[ -z "${WOFI_PACKAGES[$distro]}" ]]; then
        log_error "Wofi installation not supported on: $distro"
        return 1
    fi
    
    # Install packages
    if ! install_wofi_packages; then
        log_error "Failed to install Wofi packages"
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
    
    log_success "Wofi installation completed successfully"
    log_info "Note: Use 'wofi-launcher' command or configure keybindings in Hyprland to launch Wofi"
    return 0
}

# Uninstall Wofi (for testing/cleanup)
# Returns: 0 if successful, 1 if failed
uninstall_wofi() {
    log_info "Uninstalling Wofi..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would uninstall Wofi packages and remove configurations"
        return 0
    fi
    
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
    
    # Remove configuration (with backup)
    if [[ -d "$WOFI_CONFIG_TARGET" ]]; then
        local backup_dir="$HOME/.config/install-backups/wofi-$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$(dirname "$backup_dir")"
        mv "$WOFI_CONFIG_TARGET" "$backup_dir"
        log_info "Wofi configuration backed up to: $backup_dir"
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

# Export functions for use by other modules
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Being sourced, export functions
    export -f install_wofi
    export -f configure_wofi
    export -f is_wofi_installed
    export -f validate_wofi_installation
    export -f uninstall_wofi
fi