#!/usr/bin/env bash

# components/editor/neovim.sh - Neovim editor installation and configuration
# This module handles the installation and configuration of Neovim with
# plugin management via lazy.nvim, language server support, and cross-distribution compatibility.

source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"
source "$CORE_DIR/logger.sh"
source "$CORE_DIR/common.sh"

# Component metadata
readonly NEOVIM_COMPONENT_NAME="neovim"
readonly NEOVIM_CONFIG_SOURCE="$DOTFILES_DIR/nvim/.config/nvim"
readonly NEOVIM_CONFIG_TARGET="$HOME/.config/nvim"

#######################################
# Neovim Installation Functions
#######################################

# Check if Neovim is already installed
is_neovim_installed() {
    command -v nvim >/dev/null 2>&1
}

# Install language servers via npm and pip
install_language_servers() {
    log_info "Installing language servers for Neovim..."
    
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
configure_neovim() {
    log_info "Configuring Neovim editor..."
    
    [[ ! -d "$NEOVIM_CONFIG_SOURCE" ]] && { log_error "Neovim configuration source not found: $NEOVIM_CONFIG_SOURCE"; return 1; }
    
    mkdir -p "$NEOVIM_CONFIG_TARGET" || { log_error "Failed to create Neovim config directory: $NEOVIM_CONFIG_TARGET"; return 1; }
    
    log_info "Creating symlinks for Neovim configuration files..."
    while IFS= read -r -d '' config_file; do
        local relative_path="${config_file#$NEOVIM_CONFIG_SOURCE/}"
        local target_file="$NEOVIM_CONFIG_TARGET/$relative_path"
        local target_dir=$(dirname "$target_file")
        
        [[ ! -d "$target_dir" ]] && mkdir -p "$target_dir"
        create_symlink "$config_file" "$target_file" || log_warn "Failed to create symlink for: $relative_path"
    done < <(find "$NEOVIM_CONFIG_SOURCE" -type f -print0)
    
    log_success "Neovim configuration completed"
}

# Initialize Neovim plugins (run nvim to trigger lazy.nvim plugin installation)
initialize_neovim_plugins() {
    log_info "Initializing Neovim plugins..."
    
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
set_neovim_as_default() {
    log_info "Setting Neovim as default editor..."
    
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
install_neovim() {
    log_section "Configuring Neovim Editor"
    
    # Check if already installed (packages should be installed by main system)
    if ! is_neovim_installed; then
        log_error "Neovim not found. Ensure packages are installed by the main system first."
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
    
    log_success "Neovim configuration completed successfully"
    log_info "Note: Run ':checkhealth' in Neovim to verify all components are working correctly"
    return 0
}

# Uninstall Neovim (for testing/cleanup)
uninstall_neovim() {
    log_info "Uninstalling Neovim..."
    
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

# Export essential functions
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && export -f install_neovim configure_neovim is_neovim_installed