#!/usr/bin/env bash

# components/terminal/kitty.sh - Kitty terminal emulator installation and configuration
# This module handles the installation and configuration of Kitty terminal emulator
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
readonly KITTY_COMPONENT_NAME="kitty"
readonly KITTY_CONFIG_SOURCE="$PROJECT_ROOT/dotfiles/kitty/.config/kitty"
readonly KITTY_CONFIG_TARGET="$HOME/.config/kitty"

# Package definitions per distribution
declare -A KITTY_PACKAGES=(
    ["arch"]="kitty"
    ["ubuntu"]="kitty"
)

# Font dependencies (JetBrains Mono Nerd Font for optimal experience)
declare -A KITTY_FONT_PACKAGES=(
    ["arch"]="ttf-jetbrains-mono-nerd ttf-firacode-nerd"
    ["ubuntu"]="fonts-jetbrains-mono fonts-firacode"
)

# Theme dependencies
declare -A KITTY_THEME_PACKAGES=(
    ["arch"]=""  # Themes are usually included or downloaded separately
    ["ubuntu"]=""
)

#######################################
# Kitty Installation Functions
#######################################

# Check if Kitty terminal emulator is already installed on the system
# This function performs comprehensive detection by checking both the command
# availability and package manager installation status to ensure accurate
# detection across different installation methods.
# 
# Arguments: None
# 
# Returns:
#   0 if Kitty is installed and available
#   1 if Kitty is not installed or not available
# 
# Global Variables:
#   Uses get_distro() to determine distribution-specific package checking
# 
# Side Effects: None (read-only function)
# 
# Requirements: 7.1 - Component installation detection
# 
# Usage Examples:
#   if is_kitty_installed; then
#       echo "Kitty is already installed"
#   else
#       echo "Kitty needs to be installed"
#   fi
#   
#   # Use in conditional installation
#   is_kitty_installed || install_kitty_packages
is_kitty_installed() {
    if command -v kitty >/dev/null 2>&1; then
        return 0
    fi
    
    # Also check if package is installed via package manager
    local distro
    distro=$(get_distro)
    
    case "$distro" in
        "arch")
            pacman -Qi kitty >/dev/null 2>&1
            ;;
        "ubuntu")
            dpkg -l kitty >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

# Install Kitty packages
# Returns: 0 if successful, 1 if failed
# Requirements: 7.1 - Package installation with distribution detection
install_kitty_packages() {
    local distro
    distro=$(get_distro)
    
    if [[ -z "${KITTY_PACKAGES[$distro]}" ]]; then
        log_error "Kitty packages not defined for distribution: $distro"
        return 1
    fi
    
    log_info "Installing Kitty packages for $distro..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install packages: ${KITTY_PACKAGES[$distro]}"
        log_info "[DRY-RUN] Would install font packages: ${KITTY_FONT_PACKAGES[$distro]:-none}"
        return 0
    fi
    
    # Install main Kitty package
    local packages
    read -ra packages <<< "${KITTY_PACKAGES[$distro]}"
    
    for package in "${packages[@]}"; do
        if ! install_package "$package"; then
            log_error "Failed to install Kitty package: $package"
            return 1
        fi
    done
    
    # Install font packages if available
    if [[ -n "${KITTY_FONT_PACKAGES[$distro]:-}" ]]; then
        log_info "Installing Kitty font dependencies..."
        local font_packages
        read -ra font_packages <<< "${KITTY_FONT_PACKAGES[$distro]}"
        
        for font_package in "${font_packages[@]}"; do
            if ! install_package "$font_package"; then
                log_warn "Failed to install font package: $font_package (continuing anyway)"
            fi
        done
    fi
    
    log_success "Kitty packages installed successfully"
    return 0
}

# Download and install Kitty themes
# Returns: 0 if successful, 1 if failed
install_kitty_themes() {
    log_info "Installing Kitty themes..."
    
    local themes_dir="$KITTY_CONFIG_TARGET/themes"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create themes directory: $themes_dir"
        log_info "[DRY-RUN] Would download Catppuccin theme for Kitty"
        return 0
    fi
    
    # Create themes directory
    mkdir -p "$themes_dir"
    
    # Download Catppuccin theme (matches the current-theme.conf reference)
    log_info "Downloading Catppuccin Mocha theme for Kitty..."
    
    local catppuccin_url="https://raw.githubusercontent.com/catppuccin/kitty/main/themes/mocha.conf"
    local catppuccin_file="$themes_dir/catppuccin-mocha.conf"
    
    if command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL "$catppuccin_url" -o "$catppuccin_file"; then
            log_warn "Failed to download Catppuccin theme, continuing without it"
        else
            log_success "Downloaded Catppuccin Mocha theme"
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -q "$catppuccin_url" -O "$catppuccin_file"; then
            log_warn "Failed to download Catppuccin theme, continuing without it"
        else
            log_success "Downloaded Catppuccin Mocha theme"
        fi
    else
        log_warn "Neither curl nor wget available, skipping theme download"
    fi
    
    return 0
}

# Configure Kitty with dotfiles
# Returns: 0 if successful, 1 if failed
# Requirements: 7.1, 7.2 - Configuration management with dotfiles integration
configure_kitty() {
    log_info "Configuring Kitty terminal emulator..."
    
    if [[ ! -d "$KITTY_CONFIG_SOURCE" ]]; then
        log_error "Kitty configuration source not found: $KITTY_CONFIG_SOURCE"
        return 1
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create configuration directory: $KITTY_CONFIG_TARGET"
        log_info "[DRY-RUN] Would copy configurations from: $KITTY_CONFIG_SOURCE"
        return 0
    fi
    
    # Create configuration directory
    if ! mkdir -p "$KITTY_CONFIG_TARGET"; then
        log_error "Failed to create Kitty config directory: $KITTY_CONFIG_TARGET"
        return 1
    fi
    
    # Install themes first
    install_kitty_themes
    
    # Copy configuration files using symlinks for easy updates
    log_info "Creating symlinks for Kitty configuration files..."
    
    # Find all configuration files in the source directory
    while IFS= read -r -d '' config_file; do
        local relative_path="${config_file#$KITTY_CONFIG_SOURCE/}"
        local target_file="$KITTY_CONFIG_TARGET/$relative_path"
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
    done < <(find "$KITTY_CONFIG_SOURCE" -type f -print0)
    
    # Handle the current-theme.conf reference
    setup_kitty_theme_link
    
    log_success "Kitty configuration completed"
    return 0
}

# Setup theme symlink for current-theme.conf
# Returns: 0 if successful, 1 if failed
setup_kitty_theme_link() {
    local current_theme_file="$KITTY_CONFIG_TARGET/current-theme.conf"
    local catppuccin_theme="$KITTY_CONFIG_TARGET/themes/catppuccin-mocha.conf"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create theme symlink: current-theme.conf"
        return 0
    fi
    
    # If Catppuccin theme exists, link to it
    if [[ -f "$catppuccin_theme" ]]; then
        log_info "Linking current theme to Catppuccin Mocha..."
        if ! create_symlink "$catppuccin_theme" "$current_theme_file"; then
            log_warn "Failed to create theme symlink, theme may not work correctly"
        fi
    else
        log_warn "Catppuccin theme not found, current-theme.conf may not work"
    fi
    
    return 0
}

# Validate Kitty installation
# Returns: 0 if valid, 1 if invalid
# Requirements: 10.1 - Post-installation validation
validate_kitty_installation() {
    log_info "Validating Kitty installation..."
    
    # Check if binary is available
    if ! command -v kitty >/dev/null 2>&1; then
        log_error "Kitty binary not found in PATH"
        return 1
    fi
    
    # Check if configuration exists
    if [[ ! -f "$KITTY_CONFIG_TARGET/kitty.conf" ]]; then
        log_warn "Kitty configuration file not found: $KITTY_CONFIG_TARGET/kitty.conf"
    fi
    
    # Test Kitty version (basic functionality test)
    if ! kitty --version >/dev/null 2>&1; then
        log_error "Kitty version check failed"
        return 1
    fi
    
    # Check if theme configuration exists
    if [[ -f "$KITTY_CONFIG_TARGET/current-theme.conf" ]]; then
        log_debug "Kitty theme configuration found"
    else
        log_warn "Kitty theme configuration not found"
    fi
    
    log_success "Kitty installation validation passed"
    return 0
}

# Set Kitty as default terminal (optional)
# Returns: 0 if successful, 1 if failed
set_kitty_as_default() {
    log_info "Setting Kitty as default terminal..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would set Kitty as default terminal"
        return 0
    fi
    
    # Set as default terminal emulator
    if command -v update-alternatives >/dev/null 2>&1; then
        # Ubuntu/Debian method
        sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator "$(which kitty)" 60
        sudo update-alternatives --set x-terminal-emulator "$(which kitty)"
    fi
    
    # Set XDG default
    if command -v xdg-settings >/dev/null 2>&1; then
        xdg-settings set default-terminal-emulator kitty.desktop
    fi
    
    # Set TERMINAL environment variable
    if ! grep -q "export TERMINAL=kitty" "$HOME/.bashrc" 2>/dev/null; then
        echo "export TERMINAL=kitty" >> "$HOME/.bashrc"
    fi
    
    if [[ -f "$HOME/.zshrc" ]] && ! grep -q "export TERMINAL=kitty" "$HOME/.zshrc" 2>/dev/null; then
        echo "export TERMINAL=kitty" >> "$HOME/.zshrc"
    fi
    
    log_success "Kitty set as default terminal"
    return 0
}

#######################################
# Main Installation Function
#######################################

# Main Kitty terminal emulator installation and configuration function
# This is the primary entry point for installing Kitty terminal emulator.
# It handles the complete installation process including package installation,
# configuration deployment, theme setup, and post-installation validation.
# The function is designed to be idempotent and safe to run multiple times.
# 
# Arguments: None
# 
# Returns:
#   0 if installation and configuration completed successfully
#   1 if installation failed at any step
# 
# Global Variables:
#   DRY_RUN - If "true", shows what would be done without making changes
#   VERBOSE - If "true", provides detailed progress information
# 
# Side Effects:
#   - Installs Kitty package via system package manager
#   - Installs recommended fonts (JetBrains Mono Nerd Font)
#   - Creates symlinks to dotfiles configuration
#   - Downloads and installs Kitty themes
#   - Creates backup of existing configuration
#   - Validates installation completeness
# 
# Dependencies:
#   - Requires internet connection for package downloads
#   - Requires sudo privileges for package installation
#   - Requires dotfiles repository structure in PROJECT_ROOT/dotfiles/
# 
# Requirements: 7.1, 7.2 - Complete component installation
# 
# Usage Examples:
#   # Standard installation
#   install_kitty
#   
#   # Check installation result
#   if install_kitty; then
#       echo "Kitty installation completed successfully"
#   else
#       echo "Kitty installation failed"
#       exit 1
#   fi
#   
#   # Use in dry-run mode
#   DRY_RUN=true install_kitty
install_kitty() {
    log_section "Installing Kitty Terminal Emulator"
    
    # Check if already installed
    if is_kitty_installed; then
        log_info "Kitty is already installed"
        if ! ask_yes_no "Do you want to reconfigure Kitty?" "n"; then
            log_info "Skipping Kitty installation"
            return 0
        fi
    fi
    
    # Validate distribution support
    local distro
    distro=$(get_distro)
    if [[ -z "${KITTY_PACKAGES[$distro]}" ]]; then
        log_error "Kitty installation not supported on: $distro"
        return 1
    fi
    
    # Install packages
    if ! install_kitty_packages; then
        log_error "Failed to install Kitty packages"
        return 1
    fi
    
    # Configure Kitty
    if ! configure_kitty; then
        log_error "Failed to configure Kitty"
        return 1
    fi
    
    # Validate installation
    if ! validate_kitty_installation; then
        log_error "Kitty installation validation failed"
        return 1
    fi
    
    # Ask if user wants to set as default
    if ask_yes_no "Set Kitty as default terminal?" "y"; then
        set_kitty_as_default
    fi
    
    log_success "Kitty installation completed successfully"
    return 0
}

# Uninstall Kitty (for testing/cleanup)
# Returns: 0 if successful, 1 if failed
uninstall_kitty() {
    log_info "Uninstalling Kitty..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would uninstall Kitty packages and remove configurations"
        return 0
    fi
    
    local distro
    distro=$(get_distro)
    
    # Remove packages
    case "$distro" in
        "arch")
            sudo pacman -Rns --noconfirm kitty 2>/dev/null || true
            ;;
        "ubuntu")
            sudo apt-get remove --purge -y kitty 2>/dev/null || true
            ;;
    esac
    
    # Remove configuration (with backup)
    if [[ -d "$KITTY_CONFIG_TARGET" ]]; then
        local backup_dir="$HOME/.config/install-backups/kitty-$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$(dirname "$backup_dir")"
        mv "$KITTY_CONFIG_TARGET" "$backup_dir"
        log_info "Kitty configuration backed up to: $backup_dir"
    fi
    
    log_success "Kitty uninstalled successfully"
    return 0
}

# Export functions for use by other modules
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Being sourced, export functions
    export -f install_kitty
    export -f configure_kitty
    export -f is_kitty_installed
    export -f validate_kitty_installation
    export -f uninstall_kitty
fi