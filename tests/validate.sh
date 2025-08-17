#!/bin/bash

# Post-installation validation utilities
# Validates system state after installation or restoration

# Validate installation
validate_installation() {
    log_info "Starting installation validation..."
    
    local validation_passed=true
    
    # Validate core system components
    validate_core_system || validation_passed=false
    
    # Validate installed components
    validate_installed_components || validation_passed=false
    
    # Validate configurations
    validate_configurations || validation_passed=false
    
    # Validate services
    validate_services || validation_passed=false
    
    if [[ "$validation_passed" == "true" ]]; then
        log_success "Installation validation completed successfully"
        return 0
    else
        log_warn "Installation validation completed with warnings"
        return 1
    fi
}

# Validate core system components
validate_core_system() {
    log_info "Validating core system components..."
    
    local core_passed=true
    
    # Check shell
    if [[ -f "$HOME/.zshrc" ]]; then
        if command -v zsh &> /dev/null; then
            log_success "Zsh shell: OK"
        else
            log_warn "Zsh configuration found but zsh not installed"
            core_passed=false
        fi
    fi
    
    # Check basic directories
    local required_dirs=(
        "$HOME/.config"
        "$HOME/.local/bin"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log_success "Directory exists: $dir"
        else
            log_warn "Required directory missing: $dir"
            core_passed=false
        fi
    done
    
    return $([[ "$core_passed" == "true" ]] && echo 0 || echo 1)
}

# Validate installed components
validate_installed_components() {
    log_info "Validating installed components..."
    
    local components_passed=true
    
    # Terminal components
    if [[ -d "$HOME/.config/kitty" ]]; then
        if command -v kitty &> /dev/null; then
            log_success "Kitty terminal: OK"
        else
            log_warn "Kitty configuration found but kitty not installed"
            components_passed=false
        fi
    fi
    
    if [[ -d "$HOME/.config/alacritty" ]]; then
        if command -v alacritty &> /dev/null; then
            log_success "Alacritty terminal: OK"
        else
            log_warn "Alacritty configuration found but alacritty not installed"
            components_passed=false
        fi
    fi
    
    # Window manager components
    if [[ -d "$HOME/.config/hypr" ]]; then
        if command -v Hyprland &> /dev/null; then
            log_success "Hyprland: OK"
        else
            log_warn "Hyprland configuration found but Hyprland not installed"
            components_passed=false
        fi
    fi
    
    if [[ -d "$HOME/.config/waybar" ]]; then
        if command -v waybar &> /dev/null; then
            log_success "Waybar: OK"
        else
            log_warn "Waybar configuration found but waybar not installed"
            components_passed=false
        fi
    fi
    
    return $([[ "$components_passed" == "true" ]] && echo 0 || echo 1)
}

# Validate configurations
validate_configurations() {
    log_info "Validating configurations..."
    
    local config_passed=true
    
    # Check configuration file syntax
    if [[ -f "$HOME/.config/hypr/hyprland.conf" ]]; then
        # Basic syntax check for Hyprland config
        if grep -q "^#" "$HOME/.config/hypr/hyprland.conf"; then
            log_success "Hyprland configuration: OK"
        else
            log_warn "Hyprland configuration may have issues"
            config_passed=false
        fi
    fi
    
    # Check executable permissions on scripts
    if [[ -d "$HOME/.config/hypr/scripts" ]]; then
        local script_count=0
        local executable_count=0
        
        for script in "$HOME/.config/hypr/scripts"/*.sh; do
            if [[ -f "$script" ]]; then
                script_count=$((script_count + 1))
                if [[ -x "$script" ]]; then
                    executable_count=$((executable_count + 1))
                fi
            fi
        done
        
        if [[ $script_count -eq $executable_count ]]; then
            log_success "Hyprland scripts permissions: OK ($executable_count/$script_count)"
        else
            log_warn "Some Hyprland scripts not executable: $executable_count/$script_count"
            config_passed=false
        fi
    fi
    
    return $([[ "$config_passed" == "true" ]] && echo 0 || echo 1)
}

# Validate services
validate_services() {
    log_info "Validating services..."
    
    local services_passed=true
    
    # Check systemd services (if systemd is available)
    if command -v systemctl &> /dev/null; then
        # Check display manager
        if systemctl is-enabled sddm.service &> /dev/null; then
            log_success "SDDM service: enabled"
        elif systemctl is-enabled gdm.service &> /dev/null; then
            log_success "GDM service: enabled"
        else
            log_warn "No display manager service enabled"
            services_passed=false
        fi
        
        # Check other important services
        local important_services=("NetworkManager" "bluetooth")
        
        for service in "${important_services[@]}"; do
            if systemctl is-active "$service" &> /dev/null; then
                log_success "Service $service: active"
            elif systemctl is-enabled "$service" &> /dev/null; then
                log_success "Service $service: enabled (not running)"
            else
                log_info "Service $service: not enabled"
            fi
        done
    fi
    
    return $([[ "$services_passed" == "true" ]] && echo 0 || echo 1)
}

# Validate specific component
validate_component() {
    local component="$1"
    
    log_info "Validating component: $component"
    
    case "$component" in
        "terminal")
            validate_terminal_component
            ;;
        "shell")
            validate_shell_component
            ;;
        "editor")
            validate_editor_component
            ;;
        "wm"|"hyprland")
            validate_wm_component
            ;;
        "dev-tools")
            validate_dev_tools_component
            ;;
        *)
            log_warn "Unknown component for validation: $component"
            return 1
            ;;
    esac
}

# Validate terminal component
validate_terminal_component() {
    log_info "Validating terminal component..."
    
    local terminal_ok=true
    
    # Check Kitty
    if [[ -d "$HOME/.config/kitty" ]]; then
        if command -v kitty &> /dev/null; then
            log_success "Kitty: installed and configured"
        else
            log_warn "Kitty: configured but not installed"
            terminal_ok=false
        fi
    fi
    
    # Check Alacritty
    if [[ -d "$HOME/.config/alacritty" ]]; then
        if command -v alacritty &> /dev/null; then
            log_success "Alacritty: installed and configured"
        else
            log_warn "Alacritty: configured but not installed"
            terminal_ok=false
        fi
    fi
    
    # Check tmux
    if [[ -f "$HOME/.tmux.conf" ]]; then
        if command -v tmux &> /dev/null; then
            log_success "Tmux: installed and configured"
        else
            log_warn "Tmux: configured but not installed"
            terminal_ok=false
        fi
    fi
    
    return $([[ "$terminal_ok" == "true" ]] && echo 0 || echo 1)
}

# Validate shell component
validate_shell_component() {
    log_info "Validating shell component..."
    
    local shell_ok=true
    
    # Check Zsh
    if [[ -f "$HOME/.zshrc" ]]; then
        if command -v zsh &> /dev/null; then
            log_success "Zsh: installed and configured"
            
            # Check if zsh is the default shell
            if [[ "$SHELL" == "$(which zsh)" ]]; then
                log_success "Zsh: set as default shell"
            else
                log_warn "Zsh: not set as default shell"
            fi
        else
            log_warn "Zsh: configured but not installed"
            shell_ok=false
        fi
    fi
    
    # Check Starship
    if [[ -f "$HOME/.config/starship.toml" ]]; then
        if command -v starship &> /dev/null; then
            log_success "Starship: installed and configured"
        else
            log_warn "Starship: configured but not installed"
            shell_ok=false
        fi
    fi
    
    return $([[ "$shell_ok" == "true" ]] && echo 0 || echo 1)
}

# Validate editor component
validate_editor_component() {
    log_info "Validating editor component..."
    
    local editor_ok=true
    
    # Check Neovim
    if [[ -d "$HOME/.config/nvim" ]]; then
        if command -v nvim &> /dev/null; then
            log_success "Neovim: installed and configured"
        else
            log_warn "Neovim: configured but not installed"
            editor_ok=false
        fi
    fi
    
    # Check VS Code
    if command -v code &> /dev/null; then
        log_success "VS Code: installed"
    fi
    
    return $([[ "$editor_ok" == "true" ]] && echo 0 || echo 1)
}

# Validate window manager component
validate_wm_component() {
    log_info "Validating window manager component..."
    
    local wm_ok=true
    
    # Check Hyprland
    if [[ -d "$HOME/.config/hypr" ]]; then
        if command -v Hyprland &> /dev/null; then
            log_success "Hyprland: installed and configured"
            
            # Check configuration file
            if [[ -f "$HOME/.config/hypr/hyprland.conf" ]]; then
                log_success "Hyprland configuration file: exists"
            else
                log_warn "Hyprland configuration file: missing"
                wm_ok=false
            fi
        else
            log_warn "Hyprland: configured but not installed"
            wm_ok=false
        fi
    fi
    
    # Check Waybar
    if [[ -d "$HOME/.config/waybar" ]]; then
        if command -v waybar &> /dev/null; then
            log_success "Waybar: installed and configured"
        else
            log_warn "Waybar: configured but not installed"
            wm_ok=false
        fi
    fi
    
    return $([[ "$wm_ok" == "true" ]] && echo 0 || echo 1)
}

# Validate development tools component
validate_dev_tools_component() {
    log_info "Validating development tools component..."
    
    local dev_ok=true
    
    # Check Git
    if command -v git &> /dev/null; then
        log_success "Git: installed"
        
        # Check Git configuration
        if git config --global user.name &> /dev/null; then
            log_success "Git: configured with user name"
        else
            log_warn "Git: user name not configured"
        fi
    else
        log_warn "Git: not installed"
        dev_ok=false
    fi
    
    # Check Docker
    if command -v docker &> /dev/null; then
        log_success "Docker: installed"
    fi
    
    return $([[ "$dev_ok" == "true" ]] && echo 0 || echo 1)
}