#!/usr/bin/env bash

# components/editor/neovim.sh - Neovim editor installation and configuration
# This module handles the installation and configuration of Neovim with
# plugin management via lazy.nvim, language server support, and cross-distribution compatibility.

# Initialize all project paths
source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"

# Source core modules if not already loaded
if [[ -z "${LOGGER_SOURCED:-}" ]]; then
    source "$CORE_DIR/logger.sh"
fi
if ! declare -f detect_distro >/dev/null 2>&1; then
    source "$CORE_DIR/common.sh"
fi

# Component metadata
readonly NEOVIM_COMPONENT_NAME="neovim"
readonly NEOVIM_CONFIG_SOURCE="$DOTFILES_DIR/nvim/.config/nvim"
readonly NEOVIM_CONFIG_TARGET="$HOME/.config/nvim"

# Package definitions per distribution
declare -A NEOVIM_PACKAGES=(
    ["arch"]="neovim"
    ["ubuntu"]="neovim"
)

# Language server and development tool packages
declare -A NEOVIM_LSP_PACKAGES=(
    ["arch"]="nodejs npm python-pip ripgrep fd"
    ["ubuntu"]="nodejs npm python3-pip ripgrep fd-find"
)

# Optional packages for enhanced development experience
declare -A NEOVIM_OPTIONAL_PACKAGES=(
    ["arch"]="git curl unzip tar gzip"
    ["ubuntu"]="git curl unzip tar gzip"
)

#######################################
# Neovim Installation Functions
#######################################

# Check if Neovim is already installed
# Returns: 0 if installed, 1 if not installed
# Requirements: 7.1 - Component installation detection
is_neovim_installed() {
    if command -v nvim >/dev/null 2>&1; then
        return 0
    fi
    
    # Also check if package is installed via package manager
    local distro
    distro=$(get_distro)
    
    case "$distro" in
        "arch")
            pacman -Qi neovim >/dev/null 2>&1
            ;;
        "ubuntu")
            dpkg -l neovim >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

# Install Neovim packages
# Returns: 0 if successful, 1 if failed
# Requirements: 7.1 - Package installation with distribution detection
install_neovim_packages() {
    local distro
    distro=$(get_distro)
    
    if [[ -z "${NEOVIM_PACKAGES[$distro]}" ]]; then
        log_error "Neovim packages not defined for distribution: $distro"
        return 1
    fi
    
    log_info "Installing Neovim packages for $distro..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install packages: ${NEOVIM_PACKAGES[$distro]}"
        log_info "[DRY-RUN] Would install LSP packages: ${NEOVIM_LSP_PACKAGES[$distro]:-none}"
        log_info "[DRY-RUN] Would install optional packages: ${NEOVIM_OPTIONAL_PACKAGES[$distro]:-none}"
        return 0
    fi
    
    # Install main Neovim package
    local packages
    read -ra packages <<< "${NEOVIM_PACKAGES[$distro]}"
    
    for package in "${packages[@]}"; do
        if ! install_package "$package"; then
            log_error "Failed to install Neovim package: $package"
            return 1
        fi
    done
    
    # Install LSP and development tool packages
    if [[ -n "${NEOVIM_LSP_PACKAGES[$distro]:-}" ]]; then
        log_info "Installing Neovim LSP and development dependencies..."
        local lsp_packages
        read -ra lsp_packages <<< "${NEOVIM_LSP_PACKAGES[$distro]}"
        
        for lsp_package in "${lsp_packages[@]}"; do
            if ! install_package "$lsp_package"; then
                log_warn "Failed to install LSP package: $lsp_package (continuing anyway)"
            fi
        done
    fi
    
    # Install optional packages for enhanced experience
    if [[ -n "${NEOVIM_OPTIONAL_PACKAGES[$distro]:-}" ]]; then
        log_info "Installing optional Neovim enhancement packages..."
        local optional_packages
        read -ra optional_packages <<< "${NEOVIM_OPTIONAL_PACKAGES[$distro]}"
        
        for opt_package in "${optional_packages[@]}"; do
            if ! install_package "$opt_package"; then
                log_warn "Failed to install optional package: $opt_package (continuing anyway)"
            fi
        done
    fi
    
    log_success "Neovim packages installed successfully"
    return 0
}

# Install language servers via npm and pip
# Returns: 0 if successful, 1 if failed
# Requirements: 7.2 - Language server configuration
install_language_servers() {
    log_info "Installing language servers for Neovim..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install language servers via npm and pip"
        return 0
    fi
    
    # Install popular language servers via npm
    if command -v npm >/dev/null 2>&1; then
        log_info "Installing language servers via npm..."
        
        local npm_servers=(
            "typescript-language-server"
            "vscode-langservers-extracted"
            "bash-language-server"
            "yaml-language-server"
            "dockerfile-language-server-nodejs"
        )
        
        for server in "${npm_servers[@]}"; do
            if ! npm install -g "$server" >/dev/null 2>&1; then
                log_warn "Failed to install language server: $server"
            else
                log_debug "Installed language server: $server"
            fi
        done
    else
        log_warn "npm not available, skipping npm-based language servers"
    fi
    
    # Install Python language servers via pip
    if command -v pip3 >/dev/null 2>&1 || command -v pip >/dev/null 2>&1; then
        log_info "Installing Python language servers..."
        
        local pip_cmd="pip3"
        if ! command -v pip3 >/dev/null 2>&1; then
            pip_cmd="pip"
        fi
        
        local python_servers=(
            "python-lsp-server"
            "black"
            "isort"
            "flake8"
        )
        
        for server in "${python_servers[@]}"; do
            if ! $pip_cmd install --user "$server" >/dev/null 2>&1; then
                log_warn "Failed to install Python tool: $server"
            else
                log_debug "Installed Python tool: $server"
            fi
        done
    else
        log_warn "pip not available, skipping Python language servers"
    fi
    
    log_success "Language servers installation completed"
    return 0
}

# Configure Neovim with dotfiles
# Returns: 0 if successful, 1 if failed
# Requirements: 7.1, 7.2 - Configuration management with dotfiles integration
configure_neovim() {
    log_info "Configuring Neovim editor..."
    
    if [[ ! -d "$NEOVIM_CONFIG_SOURCE" ]]; then
        log_error "Neovim configuration source not found: $NEOVIM_CONFIG_SOURCE"
        return 1
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create configuration directory: $NEOVIM_CONFIG_TARGET"
        log_info "[DRY-RUN] Would copy configurations from: $NEOVIM_CONFIG_SOURCE"
        return 0
    fi
    
    # Create configuration directory
    if ! mkdir -p "$NEOVIM_CONFIG_TARGET"; then
        log_error "Failed to create Neovim config directory: $NEOVIM_CONFIG_TARGET"
        return 1
    fi
    
    # Copy configuration files using symlinks for easy updates
    log_info "Creating symlinks for Neovim configuration files..."
    
    # Find all configuration files in the source directory
    while IFS= read -r -d '' config_file; do
        local relative_path="${config_file#$NEOVIM_CONFIG_SOURCE/}"
        local target_file="$NEOVIM_CONFIG_TARGET/$relative_path"
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
    done < <(find "$NEOVIM_CONFIG_SOURCE" -type f -print0)
    
    log_success "Neovim configuration completed"
    return 0
}

# Initialize Neovim plugins (run nvim to trigger lazy.nvim plugin installation)
# Returns: 0 if successful, 1 if failed
# Requirements: 7.2 - Plugin management setup
initialize_neovim_plugins() {
    log_info "Initializing Neovim plugins..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would initialize Neovim plugins via lazy.nvim"
        return 0
    fi
    
    # Run Neovim headless to trigger plugin installation
    log_info "Running Neovim to initialize plugins (this may take a moment)..."
    
    # Use a timeout to prevent hanging and run headless
    if ! timeout 120 nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1; then
        log_warn "Neovim plugin initialization timed out or failed (plugins will install on first use)"
    else
        log_success "Neovim plugins initialized successfully"
    fi
    
    return 0
}

# Setup Neovim as default editor
# Returns: 0 if successful, 1 if failed
set_neovim_as_default() {
    log_info "Setting Neovim as default editor..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would set Neovim as default editor"
        return 0
    fi
    
    # Set EDITOR environment variable in shell configs
    local shell_configs=("$HOME/.bashrc" "$HOME/.zshrc")
    
    for config_file in "${shell_configs[@]}"; do
        if [[ -f "$config_file" ]]; then
            if ! grep -q "export EDITOR=nvim" "$config_file" 2>/dev/null; then
                echo "export EDITOR=nvim" >> "$config_file"
                log_debug "Added EDITOR=nvim to $config_file"
            fi
        fi
    done
    
    # Set as git editor
    if command -v git >/dev/null 2>&1; then
        git config --global core.editor nvim
        log_debug "Set Neovim as git editor"
    fi
    
    # Set XDG default
    if command -v xdg-settings >/dev/null 2>&1; then
        xdg-settings set default-text-editor nvim.desktop 2>/dev/null || true
    fi
    
    log_success "Neovim set as default editor"
    return 0
}

# Validate Neovim installation
# Returns: 0 if valid, 1 if invalid
# Requirements: 10.1 - Post-installation validation
validate_neovim_installation() {
    log_info "Validating Neovim installation..."
    
    # Check if binary is available
    if ! command -v nvim >/dev/null 2>&1; then
        log_error "Neovim binary not found in PATH"
        return 1
    fi
    
    # Check if configuration exists
    if [[ ! -f "$NEOVIM_CONFIG_TARGET/init.lua" ]]; then
        log_warn "Neovim configuration file not found: $NEOVIM_CONFIG_TARGET/init.lua"
    fi
    
    # Test Neovim version (basic functionality test)
    if ! nvim --version >/dev/null 2>&1; then
        log_error "Neovim version check failed"
        return 1
    fi
    
    # Check if configuration is syntactically valid
    if ! nvim --headless -c "lua vim.health.check()" -c "qa" >/dev/null 2>&1; then
        log_warn "Neovim configuration may have issues (check with :checkhealth)"
    fi
    
    # Check if lazy.nvim is available
    if [[ -d "$HOME/.local/share/nvim/lazy" ]]; then
        log_debug "Lazy.nvim plugin manager found"
    else
        log_warn "Lazy.nvim plugin manager not found"
    fi
    
    log_success "Neovim installation validation passed"
    return 0
}

#######################################
# Main Installation Function
#######################################

# Main Neovim installation function
# Returns: 0 if successful, 1 if failed
# Requirements: 7.1, 7.2 - Complete component installation
install_neovim() {
    log_section "Installing Neovim Editor"
    
    # Check if already installed
    if is_neovim_installed; then
        log_info "Neovim is already installed"
        if ! ask_yes_no "Do you want to reconfigure Neovim?" "n"; then
            log_info "Skipping Neovim installation"
            return 0
        fi
    fi
    
    # Validate distribution support
    local distro
    distro=$(get_distro)
    if [[ -z "${NEOVIM_PACKAGES[$distro]}" ]]; then
        log_error "Neovim installation not supported on: $distro"
        return 1
    fi
    
    # Install packages
    if ! install_neovim_packages; then
        log_error "Failed to install Neovim packages"
        return 1
    fi
    
    # Configure Neovim
    if ! configure_neovim; then
        log_error "Failed to configure Neovim"
        return 1
    fi
    
    # Install language servers
    if ask_yes_no "Install language servers for development?" "y"; then
        install_language_servers
    fi
    
    # Validate installation
    if ! validate_neovim_installation; then
        log_error "Neovim installation validation failed"
        return 1
    fi
    
    # Ask if user wants to set as default editor
    if ask_yes_no "Set Neovim as default editor?" "y"; then
        set_neovim_as_default
    fi
    
    # Initialize plugins
    if ask_yes_no "Initialize Neovim plugins now?" "y"; then
        initialize_neovim_plugins
    fi
    
    log_success "Neovim installation completed successfully"
    log_info "Note: Run ':checkhealth' in Neovim to verify all components are working correctly"
    return 0
}

# Uninstall Neovim (for testing/cleanup)
# Returns: 0 if successful, 1 if failed
uninstall_neovim() {
    log_info "Uninstalling Neovim..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would uninstall Neovim packages and remove configurations"
        return 0
    fi
    
    local distro
    distro=$(get_distro)
    
    # Remove packages
    case "$distro" in
        "arch")
            sudo pacman -Rns --noconfirm neovim 2>/dev/null || true
            ;;
        "ubuntu")
            sudo apt-get remove --purge -y neovim 2>/dev/null || true
            ;;
    esac
    
    # Remove configuration (with backup)
    if [[ -d "$NEOVIM_CONFIG_TARGET" ]]; then
        local backup_dir="$HOME/.config/install-backups/neovim-$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$(dirname "$backup_dir")"
        mv "$NEOVIM_CONFIG_TARGET" "$backup_dir"
        log_info "Neovim configuration backed up to: $backup_dir"
    fi
    
    # Remove plugin data (with backup)
    local nvim_data_dir="$HOME/.local/share/nvim"
    if [[ -d "$nvim_data_dir" ]]; then
        local backup_dir="$HOME/.config/install-backups/neovim-data-$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$(dirname "$backup_dir")"
        mv "$nvim_data_dir" "$backup_dir"
        log_info "Neovim data backed up to: $backup_dir"
    fi
    
    log_success "Neovim uninstalled successfully"
    return 0
}

# Export functions for use by other modules
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Being sourced, export functions
    export -f install_neovim
    export -f configure_neovim
    export -f is_neovim_installed
    export -f validate_neovim_installation
    export -f uninstall_neovim
    export -f set_neovim_as_default
fi