#!/usr/bin/env bash
#
# components/editor/neovim.sh - Neovim installation and configuration
# Handles installation, LSP setup, and Neovim configuration from dotfiles.

source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"
source "$CORE_DIR/logger.sh"
source "$CORE_DIR/common.sh"

# Component metadata
readonly NEOVIM_COMPONENT_NAME="neovim"
readonly NEOVIM_CONFIG_SOURCE="$DOTFILES_DIR/nvim/.config/nvim"
readonly NEOVIM_CONFIG_TARGET="$HOME/.config/nvim"

# Packages per distro
declare -A NEOVIM_PACKAGES=(
    ["arch"]="neovim nodejs npm python-pip ripgrep fd"
    ["ubuntu"]="neovim nodejs npm python3-pip ripgrep fd-find"
)

#######################################
# Neovim Installation Functions
#######################################

# Install Neovim packages
install_neovim_packages() {
    local distro=$(get_distro)
    
    local packages="${NEOVIM_PACKAGES[$distro]}"

    log_info "Installing Neovim packages for $distro..."

    install_packages $packages || { log_error "Package installation failed"; return 1; }
    
    log_success "Neovim packages installed successfully"
}

# Install language servers via npm and pip
install_language_servers() {
    log_info "Installing language servers..."

    # Install popular language servers via npm
    if command -v npm >/dev/null 2>&1; then
        local npm_servers=(
            "typescript-language-server"
            "vscode-langservers-extracted"
            "bash-language-server"
            "yaml-language-server"
            "dockerfile-language-server-nodejs"
        )
        
        for server in "${npm_servers[@]}"; do
            npm install -g "$server" >/dev/null 2>&1 && log_debug "npm: $server" || log_warn "npm failed: $server"
        done
    else
        log_warn "npm not available, skipping npm-based language servers"
    fi
    
    # Install Python language servers via pip
    if command -v pip3 >/dev/null 2>&1 || command -v pip >/dev/null 2>&1; then
        local pip_cmd=$(command -v pip3 >/dev/null 2>&1 && echo pip3 || echo pip)i
        
        local python_servers=(
            "python-lsp-server"
            "black"
            "isort"
            "flake8"
        )
        
        for server in "${python_servers[@]}"; do
            "$pip_cmd" install --user "$server" >/dev/null 2>&1 && log_debug "pip: $server" || log_warn "pip failed: $server"
        done
    else
        log_warn "pip not available, skipping Python language servers"
    fi
    
    log_success "Language servers installation completed"
}

# Configure Neovim with dotfiles
configure_neovim() {
    log_info "Configuring Neovim..."
    
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
    
    git config --global core.editor nvim 2>/dev/null || true
    
    xdg-settings set default-text-editor nvim.desktop 2>/dev/null || true
    
    log_success "Neovim set as default editor"
}

# Validate Neovim installation
validate_neovim_installation() {
    log_info "Validating Neovim installation..."
    
    command -v nvim >/dev/null || { log_error "Neovim binary not found in PATH"; return 1; }

    [[ -f "$NEOVIM_CONFIG_TARGET/init.lua" ]] || log_warn "Neovim configuration file not found: $NEOVIM_CONFIG_TARGET/init.lua"
    
    log_success "Neovim validation passed"
}

#######################################
# Main Installation Function
#######################################

# Main Neovim installation function
install_neovim() {
    log_section "Installing Neovim Editor"

    install_neovim_packages || return 1
    configure_neovim || return 1
    
    ask_yes_no "Install language servers?" "y" && install_language_servers
    ask_yes_no "Set Neovim as default editor?" "y" && set_neovim_as_default
    ask_yes_no "Initialize plugins now?" "y" && initialize_neovim_plugins

    validate_neovim_installation
    log_success "Neovim setup complete — run ':checkhealth' to verify"
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
    
    # Remove configuration
    if [[ -d "$NEOVIM_CONFIG_TARGET" ]]; then
        rm -rf "$NEOVIM_CONFIG_TARGET"
        log_info "Neovim configuration removed"
    fi
    
    # Remove plugin data
    local nvim_data_dir="$HOME/.local/share/nvim"
    if [[ -d "$nvim_data_dir" ]]; then
        rm -rf "$nvim_data_dir"
        log_info "Neovim data removed"
    fi
    
    log_success "Neovim uninstalled"
}

# Export essential functions
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && export -f install_neovim configure_neovim