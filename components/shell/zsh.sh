#!/usr/bin/env bash
#
# components/shell/zsh.sh - Zsh shell installation and configuration
# Handles Zsh install, Zinit plugin manager, dotfiles, and shell setup.

source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"
source "$CORE_DIR/logger.sh"
source "$CORE_DIR/common.sh"

# Component metadata
readonly ZSH_COMPONENT_NAME="zsh"
readonly ZSH_CONFIG_SOURCE="$DOTFILES_DIR/zshrc/.zshrc"
readonly ZSH_CONFIG_TARGET="$HOME/.zshrc"
readonly ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

# Manual installation packages (not available in all repos)
declare -A ZSH_PACKAGES=(
    ["arch"]="zsh zsh-completions fzf eza exa zoxide"
    ["ubuntu"]="zsh fzf exa zoxide"  # Not in Ubuntu repos, install manually
)

#######################################
# Zsh Installation Functions
#######################################

# Check if Zsh is the current user's default shell
is_zsh_default_shell() {
    [[ "$SHELL" == *"zsh"* ]]
}

# Install Zsh packages
install_zsh_packages() {
    local distro
    distro=$(get_distro)
    
    log_info "Installing Zsh for $distro..."

    install_packages ${ZSH_PACKAGES[$distro]} || log_warn "Zsh install incomplete"

    # Handle Ubuntu separately for zsh-completions
    if [[ "$distro" == "ubuntu" ]]; then
        install_zsh_completions_ubuntu || log_warn "Manual zsh-completions install failed"
    fi

    log_success "Zsh packages installed for $distro"
}

# Install zsh-completions manually for Ubuntu
install_zsh_completions_ubuntu() {
    log_info "Installing zsh-completions manually for Ubuntu..."
    
    local completions_dir="/usr/share/zsh/vendor-completions"
    local temp_dir="/tmp/zsh-completions-install"
    
    # Check if already installed
    if [[ -d "$completions_dir" ]] && [[ -n "$(ls -A "$completions_dir" 2>/dev/null)" ]]; then
        log_info "zsh-completions appears to already be installed"
        return 0
    fi
    
    # Create temp directory
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    
    # Clone zsh-completions repository
    log_info "Downloading zsh-completions from GitHub..."
    if ! git clone --depth 1 https://github.com/zsh-users/zsh-completions.git "$temp_dir"; then
        log_error "Failed to clone zsh-completions repository"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Install completions
    log_info "Installing zsh-completions to system directory..."
    if ! sudo mkdir -p "$completions_dir"; then
        log_error "Failed to create completions directory: $completions_dir"
        rm -rf "$temp_dir"
        return 1
    fi
    
    if ! sudo cp "$temp_dir/src/"_* "$completions_dir/" 2>/dev/null; then
        log_error "Failed to copy completion files"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Clean up
    rm -rf "$temp_dir"
    
    log_success "zsh-completions installed"
    return 0
}

# Install Zinit plugin manager
install_zinit() {
    # Check if Zinit is already installed
    if [[ -d "$ZINIT_HOME" ]]; then
        log_info "Updating existing Zinit..."
        git -C "$ZINIT_HOME" pull --quiet || log_warn "Zinit update failed"
        return 0
    fi
    
    log_info "Installing Zinit plugin manager..."
    
    mkdir -p "$(dirname "$ZINIT_HOME")"
    
    git clone --quiet https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME" ||
        { log_error "Failed to clone Zinit"; return 1; }
    
    log_success "Zinit installed"
}

# Configure Zsh with dotfiles
configure_zsh() {
    log_info "Configuring Zsh..."
    
    [[ ! -f "$ZSH_CONFIG_SOURCE" ]] && { log_error "Missing $ZSH_CONFIG_SOURCE"; return 1; }
    
    install_zinit || return 1
    
    # Create symlink for .zshrc
    log_info "Creating symlink for Zsh configuration..."
    if ! create_symlink "$ZSH_CONFIG_SOURCE" "$ZSH_CONFIG_TARGET"; then
        log_error "Failed to create Zsh configuration symlink"
        return 1
    fi
    
    # Create history file directory if needed
    local histfile_dir="$HOME"
    if [[ ! -d "$histfile_dir" ]]; then
        mkdir -p "$histfile_dir"
    fi
    
    # Create completion dump directory
    local zcompdump_dir="$HOME"
    if [[ ! -d "$zcompdump_dir" ]]; then
        mkdir -p "$zcompdump_dir"
    fi
    
    # Create local bin directory for user scripts
    local local_bin="$HOME/.local/bin"
    if [[ ! -d "$local_bin" ]]; then
        mkdir -p "$local_bin"
    fi
    
    log_success "Zsh configuration completed"
}

# Set Zsh as default shell
set_zsh_as_default() {
    log_info "Setting Zsh as default shell..."
    
    # Check if Zsh is already the default shell
    if is_zsh_default_shell; then
        log_info "Zsh is already the default shell"
        return 0
    fi
    
    # Get Zsh path
    local zsh_path
    zsh_path=$(which zsh)
    
    if [[ -z "$zsh_path" ]]; then
        log_error "Zsh binary not found in PATH"
        return 1
    fi
    
    # Check if Zsh is in /etc/shells
    if ! grep -q "$zsh_path" /etc/shells 2>/dev/null; then
        log_info "Adding Zsh to /etc/shells..."
        if ! echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null; then
            log_error "Failed to add Zsh to /etc/shells"
            return 1
        fi
    fi
    
    # Change default shell
    log_info "Changing default shell to Zsh..."
    if ! chsh -s "$zsh_path"; then
        log_error "Failed to change default shell to Zsh"
        log_info "You can manually change it later with: chsh -s $zsh_path"
        return 1
    fi
    
    log_success "Zsh set as default shell (will take effect on next login)"
}

# Initialize Zsh plugins (run Zsh once to trigger plugin installation)
initialize_zsh_plugins() {
    log_info "Initializing Zsh plugins..."
    
    # Use a timeout to prevent hanging
    if ! timeout 60 zsh -c "
        source '$ZSH_CONFIG_TARGET' 2>/dev/null || true
        echo 'Zsh plugins initialized'
        exit 0
    " >/dev/null 2>&1; then
        log_warn "Zsh plugin initialization timed out or failed (plugins will install on first use)"
    else
        log_success "Plugin initialization done"
    fi
}

# Validate Zsh installation
validate_zsh_installation() {
    log_info "Validating Zsh installation..."
    
    # Check if binary is available
    command -v zsh >/dev/null || { log_error "Zsh not found"; return 1; }
    
    # Check if configuration exists
    [[ -f "$ZSH_CONFIG_TARGET" ]] || log_error "Zsh configuration file not found: $ZSH_CONFIG_TARGET"
    
    # Check if Zinit is installed
    [[ -d "$ZINIT_HOME" ]] || log_warn "Zinit not found"
    
    log_success "Zsh validation complete"
}

#######################################
# Main Installation Function
#######################################

# Main Zsh installation function
install_zsh() {
    log_section "Installing and Configuring Zsh Shell"
    
    install_zsh_packages || return 1
    configure_zsh || return 1
    validate_zsh_installation

    ask_yes_no "Set Zsh as default shell?" "y" && set_zsh_as_default
    ask_yes_no "Initialize Zsh plugins now?" "y" && initialize_zsh_plugins
    
    log_success "Zsh setup complete — restart shell to apply"
}

# Uninstall Zsh (for testing/cleanup)
uninstall_zsh() {
    log_info "Uninstalling Zsh..."

    if [[ "$SHELL" == *"zsh"* ]]; then
        log_warn "Zsh is your default shell"
        ask_yes_no "Switch to Bash before uninstall?" "y" && chsh -s "$(command -v bash)"
    fi
    
    # Remove manual installations
    local distro
    distro=$(get_distro)
    
    case "$distro" in
        "arch")
            sudo pacman -Rns --noconfirm zsh zsh-completions 2>/dev/null || true
            ;;
        "ubuntu")
            # Remove manually installed zsh-completions
            if [[ -d "/usr/share/zsh/vendor-completions" ]]; then
                sudo apt-get remove --purge -y zsh 2>/dev/null || true
                log_info "Removing manually installed zsh-completions..."
                sudo rm -rf "/usr/share/zsh/vendor-completions" 2>/dev/null || true
            fi
            ;;
    esac
    
    # Remove configuration
    if [[ -f "$ZSH_CONFIG_TARGET" ]]; then
        rm -f "$ZSH_CONFIG_TARGET"
        log_info "Zsh configuration removed"
    fi
    
    # Remove Zinit
    if [[ -d "$ZINIT_HOME" ]]; then
        rm -rf "$ZINIT_HOME"
        log_info "Zinit removed"
    fi
    
    log_success "Zsh uninstalled"
    
    # Final reminder about shell change
    if [[ "$SHELL" == *"zsh"* ]]; then
        log_warn "IMPORTANT: Your default shell is still set to zsh"
        log_warn "Please log out and back in, or run: chsh -s /bin/bash"
    fi
}

# Export essential functions
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && export -f install_zsh