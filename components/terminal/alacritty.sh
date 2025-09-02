#!/usr/bin/env bash

# components/terminal/alacritty.sh - Alacritty terminal emulator installation and configuration
# This module handles the installation and configuration of Alacritty terminal emulator
# with proper dotfiles integration and cross-distribution support.

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
readonly ALACRITTY_COMPONENT_NAME="alacritty"
readonly ALACRITTY_CONFIG_SOURCE="$PROJECT_ROOT/dotfiles/alacritty/.config/alacritty"
readonly ALACRITTY_CONFIG_TARGET="$HOME/.config/alacritty"

# Package definitions per distribution
declare -A ALACRITTY_PACKAGES=(
    ["arch"]="alacritty"
    ["ubuntu"]="alacritty"
)

# Font dependencies (Nerd Fonts for proper terminal experience)
declare -A ALACRITTY_FONT_PACKAGES=(
    ["arch"]="ttf-cascadia-code ttf-firacode-nerd"
    ["ubuntu"]="fonts-cascadia-code fonts-firacode"
)

#######################################
# Alacritty Installation Functions
#######################################

# Check if Alacritty is already installed
# Returns: 0 if installed, 1 if not installed
# Requirements: 7.1 - Component installation detection
is_alacritty_installed() {
    if command -v alacritty >/dev/null 2>&1; then
        return 0
    fi
    
    # Also check if package is installed via package manager
    local distro
    distro=$(get_distro)
    
    case "$distro" in
        "arch")
            pacman -Qi alacritty >/dev/null 2>&1
            ;;
        "ubuntu")
            dpkg -l alacritty >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

# Install Alacritty packages
# Returns: 0 if successful, 1 if failed
# Requirements: 7.1 - Package installation with distribution detection
install_alacritty_packages() {
    local distro
    distro=$(get_distro)
    
    if [[ -z "${ALACRITTY_PACKAGES[$distro]}" ]]; then
        log_error "Alacritty packages not defined for distribution: $distro"
        return 1
    fi
    
    log_info "Installing Alacritty packages for $distro..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install packages: ${ALACRITTY_PACKAGES[$distro]}"
        log_info "[DRY-RUN] Would install font packages: ${ALACRITTY_FONT_PACKAGES[$distro]:-none}"
        return 0
    fi
    
    # Install main Alacritty package
    local packages
    read -ra packages <<< "${ALACRITTY_PACKAGES[$distro]}"
    
    for package in "${packages[@]}"; do
        if ! install_package "$package"; then
            log_error "Failed to install Alacritty package: $package"
            return 1
        fi
    done
    
    # Install font packages if available
    if [[ -n "${ALACRITTY_FONT_PACKAGES[$distro]:-}" ]]; then
        log_info "Installing Alacritty font dependencies..."
        local font_packages
        read -ra font_packages <<< "${ALACRITTY_FONT_PACKAGES[$distro]}"
        
        for font_package in "${font_packages[@]}"; do
            if ! install_package "$font_package"; then
                log_warn "Failed to install font package: $font_package (continuing anyway)"
            fi
        done
    fi
    
    log_success "Alacritty packages installed successfully"
    return 0
}

# Configure Alacritty with dotfiles
# Returns: 0 if successful, 1 if failed
# Requirements: 7.1, 7.2 - Configuration management with dotfiles integration
configure_alacritty() {
    log_info "Configuring Alacritty terminal emulator..."
    
    if [[ ! -d "$ALACRITTY_CONFIG_SOURCE" ]]; then
        log_error "Alacritty configuration source not found: $ALACRITTY_CONFIG_SOURCE"
        return 1
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create configuration directory: $ALACRITTY_CONFIG_TARGET"
        log_info "[DRY-RUN] Would copy configurations from: $ALACRITTY_CONFIG_SOURCE"
        return 0
    fi
    
    # Create configuration directory
    if ! mkdir -p "$ALACRITTY_CONFIG_TARGET"; then
        log_error "Failed to create Alacritty config directory: $ALACRITTY_CONFIG_TARGET"
        return 1
    fi
    
    # Copy configuration files using symlinks for easy updates
    log_info "Creating symlinks for Alacritty configuration files..."
    
    # Find all configuration files in the source directory
    while IFS= read -r -d '' config_file; do
        local relative_path="${config_file#$ALACRITTY_CONFIG_SOURCE/}"
        local target_file="$ALACRITTY_CONFIG_TARGET/$relative_path"
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
    done < <(find "$ALACRITTY_CONFIG_SOURCE" -type f -print0)
    
    log_success "Alacritty configuration completed"
    return 0
}

# Validate Alacritty installation
# Returns: 0 if valid, 1 if invalid
# Requirements: 10.1 - Post-installation validation
validate_alacritty_installation() {
    log_info "Validating Alacritty installation..."
    
    # Check if binary is available
    if ! command -v alacritty >/dev/null 2>&1; then
        log_error "Alacritty binary not found in PATH"
        return 1
    fi
    
    # Check if configuration exists
    if [[ ! -f "$ALACRITTY_CONFIG_TARGET/alacritty.toml" ]]; then
        log_warn "Alacritty configuration file not found: $ALACRITTY_CONFIG_TARGET/alacritty.toml"
    fi
    
    # Test Alacritty version (basic functionality test)
    if ! alacritty --version >/dev/null 2>&1; then
        log_error "Alacritty version check failed"
        return 1
    fi
    
    log_success "Alacritty installation validation passed"
    return 0
}

# Set Alacritty as default terminal (optional)
# Returns: 0 if successful, 1 if failed
set_alacritty_as_default() {
    log_info "Setting Alacritty as default terminal..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would set Alacritty as default terminal"
        return 0
    fi
    
    # Set as default terminal emulator
    if command -v update-alternatives >/dev/null 2>&1; then
        # Ubuntu/Debian method
        sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator "$(which alacritty)" 50
        sudo update-alternatives --set x-terminal-emulator "$(which alacritty)"
    fi
    
    # Set XDG default
    if command -v xdg-settings >/dev/null 2>&1; then
        xdg-settings set default-terminal-emulator alacritty.desktop
    fi
    
    log_success "Alacritty set as default terminal"
    return 0
}

#######################################
# Main Installation Function
#######################################

# Main Alacritty installation function
# Returns: 0 if successful, 1 if failed
# Requirements: 7.1, 7.2 - Complete component installation
install_alacritty() {
    log_section "Installing Alacritty Terminal Emulator"
    
    # Check if already installed
    if is_alacritty_installed; then
        log_info "Alacritty is already installed"
        if ! ask_yes_no "Do you want to reconfigure Alacritty?" "n"; then
            log_info "Skipping Alacritty installation"
            return 0
        fi
    fi
    
    # Validate distribution support
    local distro
    distro=$(get_distro)
    if [[ -z "${ALACRITTY_PACKAGES[$distro]}" ]]; then
        log_error "Alacritty installation not supported on: $distro"
        return 1
    fi
    
    # Install packages
    if ! install_alacritty_packages; then
        log_error "Failed to install Alacritty packages"
        return 1
    fi
    
    # Configure Alacritty
    if ! configure_alacritty; then
        log_error "Failed to configure Alacritty"
        return 1
    fi
    
    # Validate installation
    if ! validate_alacritty_installation; then
        log_error "Alacritty installation validation failed"
        return 1
    fi
    
    # Ask if user wants to set as default
    if ask_yes_no "Set Alacritty as default terminal?" "n"; then
        set_alacritty_as_default
    fi
    
    log_success "Alacritty installation completed successfully"
    return 0
}

# Uninstall Alacritty (for testing/cleanup)
# Returns: 0 if successful, 1 if failed
uninstall_alacritty() {
    log_info "Uninstalling Alacritty..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would uninstall Alacritty packages and remove configurations"
        return 0
    fi
    
    local distro
    distro=$(get_distro)
    
    # Remove packages
    case "$distro" in
        "arch")
            sudo pacman -Rns --noconfirm alacritty 2>/dev/null || true
            ;;
        "ubuntu")
            sudo apt-get remove --purge -y alacritty 2>/dev/null || true
            ;;
    esac
    
    # Remove configuration (with backup)
    if [[ -d "$ALACRITTY_CONFIG_TARGET" ]]; then
        local backup_dir="$HOME/.config/install-backups/alacritty-$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$(dirname "$backup_dir")"
        mv "$ALACRITTY_CONFIG_TARGET" "$backup_dir"
        log_info "Alacritty configuration backed up to: $backup_dir"
    fi
    
    log_success "Alacritty uninstalled successfully"
    return 0
}

# Export functions for use by other modules
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Being sourced, export functions
    export -f install_alacritty
    export -f configure_alacritty
    export -f is_alacritty_installed
    export -f validate_alacritty_installation
    export -f uninstall_alacritty
fi