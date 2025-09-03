#!/usr/bin/env bash

# components/editor/vscode.sh - Visual Studio Code installation and configuration
# This module handles the installation and configuration of Visual Studio Code with
# extension management, settings synchronization, and cross-distribution support.

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
readonly VSCODE_COMPONENT_NAME="vscode"
readonly VSCODE_CONFIG_TARGET="$HOME/.config/Code/User"

# Package definitions per distribution
declare -A VSCODE_PACKAGES=(
    ["arch"]="visual-studio-code-bin"  # AUR package
    ["ubuntu"]="code"  # Will be installed via Microsoft repository
)

# Repository setup for distributions
declare -A VSCODE_REPO_SETUP=(
    ["arch"]=""  # AUR package, no repo setup needed
    ["ubuntu"]="microsoft"  # Needs Microsoft repository
)

# Essential VS Code extensions for development
declare -a VSCODE_EXTENSIONS=(
    "ms-vscode.vscode-typescript-next"
    "ms-python.python"
    "ms-vscode.cpptools"
    "rust-lang.rust-analyzer"
    "golang.go"
    "ms-vscode.cmake-tools"
    "ms-vscode.makefile-tools"
    "redhat.vscode-yaml"
    "ms-vscode.vscode-json"
    "bradlc.vscode-tailwindcss"
    "esbenp.prettier-vscode"
    "ms-vscode.vscode-eslint"
    "GitLab.gitlab-workflow"
    "ms-vscode.remote-ssh"
    "ms-vscode-remote.remote-containers"
    "ms-azuretools.vscode-docker"
    "catppuccin.catppuccin-vsc"
    "PKief.material-icon-theme"
    "ms-vscode.hexeditor"
    "ms-vscode.live-server"
)

#######################################
# VS Code Installation Functions
#######################################

# Check if VS Code is already installed
# Returns: 0 if installed, 1 if not installed
# Requirements: 7.1 - Component installation detection
is_vscode_installed() {
    if command -v code >/dev/null 2>&1; then
        return 0
    fi
    
    # Also check if package is installed via package manager
    local distro
    distro=$(get_distro)
    
    case "$distro" in
        "arch")
            pacman -Qi visual-studio-code-bin >/dev/null 2>&1 || yay -Qi visual-studio-code-bin >/dev/null 2>&1
            ;;
        "ubuntu")
            dpkg -l code >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

# Setup Microsoft repository for Ubuntu
# Returns: 0 if successful, 1 if failed
setup_microsoft_repository() {
    log_info "Setting up Microsoft repository for VS Code..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would setup Microsoft repository"
        return 0
    fi
    
    # Download and install Microsoft GPG key
    if ! curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /usr/share/keyrings/packages.microsoft.gpg; then
        log_error "Failed to download Microsoft GPG key"
        return 1
    fi
    
    # Add Microsoft repository
    echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | \
        sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
    
    # Update package list
    if ! sudo apt-get update >/dev/null 2>&1; then
        log_error "Failed to update package list after adding Microsoft repository"
        return 1
    fi
    
    log_success "Microsoft repository setup completed"
    return 0
}

# Install VS Code packages
# Returns: 0 if successful, 1 if failed
# Requirements: 7.1 - Package installation with distribution detection
install_vscode_packages() {
    local distro
    distro=$(get_distro)
    
    if [[ -z "${VSCODE_PACKAGES[$distro]}" ]]; then
        log_error "VS Code packages not defined for distribution: $distro"
        return 1
    fi
    
    log_info "Installing VS Code packages for $distro..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install packages: ${VSCODE_PACKAGES[$distro]}"
        return 0
    fi
    
    # Setup repository if needed
    case "$distro" in
        "ubuntu")
            if ! setup_microsoft_repository; then
                log_error "Failed to setup Microsoft repository"
                return 1
            fi
            ;;
    esac
    
    # Install VS Code package
    local packages
    read -ra packages <<< "${VSCODE_PACKAGES[$distro]}"
    
    for package in "${packages[@]}"; do
        case "$distro" in
            "arch")
                # Use AUR helper for VS Code
                if command -v yay >/dev/null 2>&1; then
                    if ! yay -S --noconfirm "$package"; then
                        log_error "Failed to install VS Code package via yay: $package"
                        return 1
                    fi
                elif command -v paru >/dev/null 2>&1; then
                    if ! paru -S --noconfirm "$package"; then
                        log_error "Failed to install VS Code package via paru: $package"
                        return 1
                    fi
                else
                    log_error "No AUR helper found (yay or paru required for VS Code installation)"
                    return 1
                fi
                ;;
            *)
                if ! install_package "$package"; then
                    log_error "Failed to install VS Code package: $package"
                    return 1
                fi
                ;;
        esac
    done
    
    log_success "VS Code packages installed successfully"
    return 0
}

# Install VS Code extensions
# Returns: 0 if successful, 1 if failed
# Requirements: 7.2 - Extension management
install_vscode_extensions() {
    log_info "Installing VS Code extensions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install ${#VSCODE_EXTENSIONS[@]} VS Code extensions"
        for ext in "${VSCODE_EXTENSIONS[@]}"; do
            log_info "[DRY-RUN] Would install extension: $ext"
        done
        return 0
    fi
    
    # Check if code command is available
    if ! command -v code >/dev/null 2>&1; then
        log_error "VS Code 'code' command not found in PATH"
        return 1
    fi
    
    local installed_count=0
    local failed_count=0
    
    for extension in "${VSCODE_EXTENSIONS[@]}"; do
        log_info "Installing extension: $extension"
        
        if code --install-extension "$extension" --force >/dev/null 2>&1; then
            log_debug "Successfully installed: $extension"
            ((installed_count++))
        else
            log_warn "Failed to install extension: $extension"
            ((failed_count++))
        fi
    done
    
    log_success "VS Code extensions installation completed: $installed_count installed, $failed_count failed"
    
    if [[ $failed_count -gt 0 ]]; then
        log_warn "Some extensions failed to install. You can install them manually later."
    fi
    
    return 0
}

# Configure VS Code settings
# Returns: 0 if successful, 1 if failed
# Requirements: 7.1, 7.2 - Configuration management
configure_vscode() {
    log_info "Configuring VS Code settings..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create VS Code configuration directory: $VSCODE_CONFIG_TARGET"
        log_info "[DRY-RUN] Would create default settings.json and keybindings.json"
        return 0
    fi
    
    # Create configuration directory
    if ! mkdir -p "$VSCODE_CONFIG_TARGET"; then
        log_error "Failed to create VS Code config directory: $VSCODE_CONFIG_TARGET"
        return 1
    fi
    
    # Create default settings.json if it doesn't exist
    local settings_file="$VSCODE_CONFIG_TARGET/settings.json"
    if [[ ! -f "$settings_file" ]]; then
        log_info "Creating default VS Code settings..."
        
        cat > "$settings_file" << 'EOF'
{
    "workbench.colorTheme": "Catppuccin Mocha",
    "workbench.iconTheme": "material-icon-theme",
    "editor.fontFamily": "'JetBrains Mono', 'Fira Code', 'Cascadia Code', monospace",
    "editor.fontSize": 14,
    "editor.fontLigatures": true,
    "editor.lineNumbers": "on",
    "editor.rulers": [80, 120],
    "editor.wordWrap": "on",
    "editor.tabSize": 4,
    "editor.insertSpaces": true,
    "editor.detectIndentation": true,
    "editor.formatOnSave": true,
    "editor.formatOnPaste": true,
    "editor.codeActionsOnSave": {
        "source.fixAll": true,
        "source.organizeImports": true
    },
    "files.autoSave": "afterDelay",
    "files.autoSaveDelay": 1000,
    "files.trimTrailingWhitespace": true,
    "files.insertFinalNewline": true,
    "terminal.integrated.fontFamily": "'JetBrains Mono', 'Fira Code', 'Cascadia Code', monospace",
    "terminal.integrated.fontSize": 14,
    "git.enableSmartCommit": true,
    "git.confirmSync": false,
    "git.autofetch": true,
    "extensions.autoUpdate": true,
    "telemetry.telemetryLevel": "off",
    "update.mode": "start",
    "security.workspace.trust.untrustedFiles": "open"
}
EOF
        log_success "Created default VS Code settings"
    else
        log_info "VS Code settings.json already exists, skipping creation"
    fi
    
    # Create default keybindings.json if it doesn't exist
    local keybindings_file="$VSCODE_CONFIG_TARGET/keybindings.json"
    if [[ ! -f "$keybindings_file" ]]; then
        log_info "Creating default VS Code keybindings..."
        
        cat > "$keybindings_file" << 'EOF'
[
    {
        "key": "ctrl+shift+t",
        "command": "workbench.action.terminal.new"
    },
    {
        "key": "ctrl+shift+`",
        "command": "workbench.action.terminal.toggleTerminal"
    },
    {
        "key": "ctrl+shift+p",
        "command": "workbench.action.showCommands"
    },
    {
        "key": "ctrl+p",
        "command": "workbench.action.quickOpen"
    },
    {
        "key": "ctrl+shift+f",
        "command": "workbench.action.findInFiles"
    }
]
EOF
        log_success "Created default VS Code keybindings"
    else
        log_info "VS Code keybindings.json already exists, skipping creation"
    fi
    
    log_success "VS Code configuration completed"
    return 0
}

# Setup VS Code as default editor for specific file types
# Returns: 0 if successful, 1 if failed
setup_vscode_file_associations() {
    log_info "Setting up VS Code file associations..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would setup VS Code file associations"
        return 0
    fi
    
    # Common file types to associate with VS Code
    local file_types=(
        "text/plain"
        "text/x-python"
        "text/x-shellscript"
        "application/javascript"
        "text/x-c"
        "text/x-c++"
        "text/x-java"
        "text/x-rust"
        "text/x-go"
        "application/json"
        "text/x-yaml"
        "text/markdown"
    )
    
    if command -v xdg-mime >/dev/null 2>&1; then
        for file_type in "${file_types[@]}"; do
            xdg-mime default code.desktop "$file_type" 2>/dev/null || true
        done
        log_success "VS Code file associations configured"
    else
        log_warn "xdg-mime not available, skipping file associations"
    fi
    
    return 0
}

# Validate VS Code installation
# Returns: 0 if valid, 1 if invalid
# Requirements: 10.1 - Post-installation validation
validate_vscode_installation() {
    log_info "Validating VS Code installation..."
    
    # Check if binary is available
    if ! command -v code >/dev/null 2>&1; then
        log_error "VS Code 'code' command not found in PATH"
        return 1
    fi
    
    # Check if configuration directory exists
    if [[ ! -d "$VSCODE_CONFIG_TARGET" ]]; then
        log_warn "VS Code configuration directory not found: $VSCODE_CONFIG_TARGET"
    fi
    
    # Test VS Code version (basic functionality test)
    if ! code --version >/dev/null 2>&1; then
        log_error "VS Code version check failed"
        return 1
    fi
    
    # Check if settings file exists
    if [[ -f "$VSCODE_CONFIG_TARGET/settings.json" ]]; then
        log_debug "VS Code settings.json found"
    else
        log_warn "VS Code settings.json not found"
    fi
    
    # List installed extensions
    local extension_count
    extension_count=$(code --list-extensions 2>/dev/null | wc -l)
    log_debug "VS Code has $extension_count extensions installed"
    
    log_success "VS Code installation validation passed"
    return 0
}

#######################################
# Main Installation Function
#######################################

# Main VS Code installation function
# Returns: 0 if successful, 1 if failed
# Requirements: 7.1, 7.2 - Complete component installation
install_vscode() {
    log_section "Installing Visual Studio Code"
    
    # Check if already installed
    if is_vscode_installed; then
        log_info "VS Code is already installed"
        if ! ask_yes_no "Do you want to reconfigure VS Code?" "n"; then
            log_info "Skipping VS Code installation"
            return 0
        fi
    fi
    
    # Validate distribution support
    local distro
    distro=$(get_distro)
    if [[ -z "${VSCODE_PACKAGES[$distro]}" ]]; then
        log_error "VS Code installation not supported on: $distro"
        return 1
    fi
    
    # Install packages
    if ! install_vscode_packages; then
        log_error "Failed to install VS Code packages"
        return 1
    fi
    
    # Configure VS Code
    if ! configure_vscode; then
        log_error "Failed to configure VS Code"
        return 1
    fi
    
    # Install extensions
    if ask_yes_no "Install recommended VS Code extensions?" "y"; then
        install_vscode_extensions
    fi
    
    # Setup file associations
    if ask_yes_no "Setup VS Code as default editor for common file types?" "y"; then
        setup_vscode_file_associations
    fi
    
    # Validate installation
    if ! validate_vscode_installation; then
        log_error "VS Code installation validation failed"
        return 1
    fi
    
    log_success "VS Code installation completed successfully"
    log_info "Note: You can install additional extensions via the Extensions view (Ctrl+Shift+X)"
    return 0
}

# Uninstall VS Code (for testing/cleanup)
# Returns: 0 if successful, 1 if failed
uninstall_vscode() {
    log_info "Uninstalling VS Code..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would uninstall VS Code packages and remove configurations"
        return 0
    fi
    
    local distro
    distro=$(get_distro)
    
    # Remove packages
    case "$distro" in
        "arch")
            if command -v yay >/dev/null 2>&1; then
                yay -Rns --noconfirm visual-studio-code-bin 2>/dev/null || true
            elif command -v paru >/dev/null 2>&1; then
                paru -Rns --noconfirm visual-studio-code-bin 2>/dev/null || true
            fi
            ;;
        "ubuntu")
            sudo apt-get remove --purge -y code 2>/dev/null || true
            # Remove Microsoft repository
            sudo rm -f /etc/apt/sources.list.d/vscode.list
            sudo rm -f /usr/share/keyrings/packages.microsoft.gpg
            ;;
    esac
    
    # Remove configuration (with backup)
    if [[ -d "$VSCODE_CONFIG_TARGET" ]]; then
        local backup_dir="$HOME/.config/install-backups/vscode-$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$(dirname "$backup_dir")"
        mv "$VSCODE_CONFIG_TARGET" "$backup_dir"
        log_info "VS Code configuration backed up to: $backup_dir"
    fi
    
    # Remove extensions directory (with backup)
    local extensions_dir="$HOME/.vscode/extensions"
    if [[ -d "$extensions_dir" ]]; then
        local backup_dir="$HOME/.config/install-backups/vscode-extensions-$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$(dirname "$backup_dir")"
        mv "$extensions_dir" "$backup_dir"
        log_info "VS Code extensions backed up to: $backup_dir"
    fi
    
    log_success "VS Code uninstalled successfully"
    return 0
}

# Export functions for use by other modules
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Being sourced, export functions
    export -f install_vscode
    export -f configure_vscode
    export -f is_vscode_installed
    export -f validate_vscode_installation
    export -f uninstall_vscode
fi