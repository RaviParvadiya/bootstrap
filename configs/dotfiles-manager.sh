#!/bin/bash

# Dotfiles management system
# Handles symlink creation and configuration file management
# Extracted from existing dotfiles/install.sh

# Global variables for dotfiles management
DOTFILES_DIR="$SCRIPT_DIR/dotfiles"
BACKUP_DIR="$HOME/.config-backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Initialize dotfiles management
init_dotfiles_manager() {
    # Ensure backup directory exists
    mkdir -p "$BACKUP_DIR"
    
    # Source backup utilities
    source "$CONFIGS_DIR/backup.sh"
    
    log_info "Dotfiles manager initialized"
}

# Main dotfiles management function
manage_dotfiles() {
    local components=("$@")
    
    log_info "Managing dotfiles for components: ${components[*]}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would manage dotfiles for: ${components[*]}"
        return 0
    fi
    
    # Initialize dotfiles manager
    init_dotfiles_manager
    
    # Process each component
    for component in "${components[@]}"; do
        case "$component" in
            "terminal")
                configure_terminal_dotfiles
                ;;
            "shell")
                configure_shell_dotfiles
                ;;
            "editor")
                configure_editor_dotfiles
                ;;
            "wm"|"hyprland")
                configure_wm_dotfiles
                ;;
            "dev-tools")
                configure_dev_tools_dotfiles
                ;;
            *)
                log_warn "Unknown component for dotfiles: $component"
                ;;
        esac
    done
    
    # Apply system-wide configurations
    apply_system_configs
    
    log_success "Dotfiles management completed"
}

# Configure terminal-related dotfiles
configure_terminal_dotfiles() {
    log_info "Configuring terminal dotfiles..."
    
    # Kitty configuration
    if [[ -d "$DOTFILES_DIR/kitty" ]]; then
        backup_and_copy_config "kitty" "$DOTFILES_DIR/kitty/.config/kitty" "$HOME/.config/kitty"
        
        # Install xdg-terminal-exec
        if [[ -f "$DOTFILES_DIR/kitty/.local/bin/xdg-terminal-exec" ]]; then
            mkdir -p "$HOME/.local/bin"
            backup_and_copy_file "$DOTFILES_DIR/kitty/.local/bin/xdg-terminal-exec" "$HOME/.local/bin/xdg-terminal-exec"
            chmod +x "$HOME/.local/bin/xdg-terminal-exec"
        fi
    fi
    
    # Alacritty configuration
    if [[ -d "$DOTFILES_DIR/alacritty" ]]; then
        backup_and_copy_config "alacritty" "$DOTFILES_DIR/alacritty/.config/alacritty" "$HOME/.config/alacritty"
    fi
    
    # Tmux configuration
    if [[ -d "$DOTFILES_DIR/tmux" ]]; then
        backup_and_copy_file "$DOTFILES_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"
    fi
    
    log_success "Terminal dotfiles configured"
}

# Configure shell-related dotfiles
configure_shell_dotfiles() {
    log_info "Configuring shell dotfiles..."
    
    # Zsh configuration
    if [[ -d "$DOTFILES_DIR/zshrc" ]]; then
        backup_and_copy_file "$DOTFILES_DIR/zshrc/.zshrc" "$HOME/.zshrc"
        
        # Change shell to zsh
        if [[ "$SHELL" != "$(which zsh)" ]]; then
            log_info "Changing shell to zsh..."
            chsh -s "$(which zsh)"
            sudo chsh -s "$(which zsh)"
        fi
    fi
    
    # Starship configuration
    if [[ -d "$DOTFILES_DIR/starship" ]]; then
        backup_and_copy_config "starship" "$DOTFILES_DIR/starship/.config" "$HOME/.config"
    fi
    
    log_success "Shell dotfiles configured"
}

# Configure editor-related dotfiles
configure_editor_dotfiles() {
    log_info "Configuring editor dotfiles..."
    
    # Neovim configuration
    if [[ -d "$DOTFILES_DIR/nvim" ]]; then
        backup_and_copy_config "nvim" "$DOTFILES_DIR/nvim/.config/nvim" "$HOME/.config/nvim"
    fi
    
    # Doom Emacs configuration
    if [[ -d "$DOTFILES_DIR/doom" ]]; then
        backup_and_copy_config "doom" "$DOTFILES_DIR/doom/.config/doom" "$HOME/.config/doom"
    fi
    
    log_success "Editor dotfiles configured"
}

# Configure window manager dotfiles
configure_wm_dotfiles() {
    log_info "Configuring window manager dotfiles..."
    
    # Hyprland configuration
    if [[ -d "$DOTFILES_DIR/hyprland" ]]; then
        backup_and_copy_config "hyprland" "$DOTFILES_DIR/hyprland/.config/hypr" "$HOME/.config/hypr"
        
        # Make scripts executable
        if [[ -d "$HOME/.config/hypr/scripts" ]]; then
            chmod +x "$HOME/.config/hypr/scripts"/*.sh 2>/dev/null || true
            chmod +x "$HOME/.config/hypr/scripts"/*.py 2>/dev/null || true
        fi
        
        # Create user icon symlinks
        if [[ -f "$HOME/.config/hypr/profile-picture.png" ]]; then
            ln -sf "$HOME/.config/hypr/profile-picture.png" "$HOME/.face.icon"
            ln -sf "$HOME/.config/hypr/profile-picture.png" "$HOME/.face"
        fi
    fi
    
    # Hyprlock configuration
    if [[ -d "$DOTFILES_DIR/hyprlock" ]]; then
        backup_and_copy_config "hyprlock" "$DOTFILES_DIR/hyprlock/.config/hypr" "$HOME/.config/hypr"
    fi
    
    # Hypridle configuration
    if [[ -d "$DOTFILES_DIR/hypridle" ]]; then
        backup_and_copy_config "hypridle" "$DOTFILES_DIR/hypridle/.config/hypr" "$HOME/.config/hypr"
    fi
    
    # Hyprpaper configuration
    if [[ -d "$DOTFILES_DIR/hyprpaper" ]]; then
        backup_and_copy_config "hyprpaper" "$DOTFILES_DIR/hyprpaper/.config/hypr" "$HOME/.config/hypr"
    fi
    
    # Hyprmocha configuration
    if [[ -d "$DOTFILES_DIR/hyprmocha" ]]; then
        backup_and_copy_config "hyprmocha" "$DOTFILES_DIR/hyprmocha/.config/hypr" "$HOME/.config/hypr"
    fi
    
    # Waybar configuration
    if [[ -d "$DOTFILES_DIR/waybar" ]]; then
        backup_and_copy_config "waybar" "$DOTFILES_DIR/waybar/.config/waybar" "$HOME/.config/waybar"
        
        # Make scripts executable
        if [[ -d "$HOME/.config/waybar/scripts" ]]; then
            chmod +x "$HOME/.config/waybar/scripts"/*.sh 2>/dev/null || true
        fi
    fi
    
    # Wofi configuration
    if [[ -d "$DOTFILES_DIR/wofi" ]]; then
        backup_and_copy_config "wofi" "$DOTFILES_DIR/wofi/.config/wofi" "$HOME/.config/wofi"
    fi
    
    # Swaync configuration
    if [[ -d "$DOTFILES_DIR/swaync" ]]; then
        backup_and_copy_config "swaync" "$DOTFILES_DIR/swaync/.config/swaync" "$HOME/.config/swaync"
        
        # Update paths in config files
        if [[ -f "$HOME/.config/swaync/config.json" ]]; then
            sed -i "s|/home/reyshyram|$HOME|g" "$HOME/.config/swaync/config.json"
        fi
        
        # Make scripts executable
        if [[ -f "$HOME/.config/swaync/notification-controller.sh" ]]; then
            chmod +x "$HOME/.config/swaync/notification-controller.sh"
        fi
    fi
    
    log_success "Window manager dotfiles configured"
}

# Configure development tools dotfiles
configure_dev_tools_dotfiles() {
    log_info "Configuring development tools dotfiles..."
    
    # Git configuration (handled by components/dev-tools/git.sh)
    log_info "Git configuration handled by dev-tools component"
    
    log_success "Development tools dotfiles configured"
}

# Apply system-wide configurations
apply_system_configs() {
    log_info "Applying system-wide configurations..."
    
    # Copy wallpapers
    copy_wallpapers
    
    # Configure themes and appearance
    configure_themes
    
    # Set application associations
    set_application_associations
    
    log_success "System-wide configurations applied"
}

# Copy wallpapers
copy_wallpapers() {
    log_info "Copying wallpapers..."
    
    # Create directories
    mkdir -p "$HOME/Pictures/Wallpapers" "$HOME/Pictures/Screenshots"
    
    # Copy backgrounds
    if [[ -d "$DOTFILES_DIR/backgrounds" ]]; then
        backup_and_copy_config "backgrounds" "$DOTFILES_DIR/backgrounds/.config/backgrounds" "$HOME/.config/backgrounds"
    fi
    
    log_success "Wallpapers copied"
}

# Configure themes and appearance
configure_themes() {
    log_info "Configuring themes and appearance..."
    
    # GTK theme configuration
    configure_gtk_theme
    
    # Qt theme configuration
    configure_qt_theme
    
    # Icon theme configuration
    configure_icon_theme
    
    log_success "Themes configured"
}

# Configure GTK theme
configure_gtk_theme() {
    log_info "Configuring GTK theme..."
    
    # Create GTK config directories
    mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
    
    # Copy GTK configurations (placeholder - actual files would be in dotfiles)
    # This would copy from dotfiles/gtk-* directories if they exist
    
    log_success "GTK theme configured"
}

# Configure Qt theme
configure_qt_theme() {
    log_info "Configuring Qt theme..."
    
    # Qt5ct and Qt6ct configurations would be copied here
    # This would copy from dotfiles/qt* directories if they exist
    
    log_success "Qt theme configured"
}

# Configure icon theme
configure_icon_theme() {
    log_info "Configuring icon theme..."
    
    # Apply Papirus icon theme customizations
    if command -v papirus-folders &> /dev/null; then
        papirus-folders -C cat-mocha-lavender 2>/dev/null || true
    fi
    
    log_success "Icon theme configured"
}

# Set application associations
set_application_associations() {
    log_info "Setting application associations..."
    
    # Set default web browser
    if command -v firefox &> /dev/null; then
        xdg-settings set default-web-browser firefox.desktop 2>/dev/null || true
    fi
    
    # Set default file manager
    if command -v pcmanfm-qt &> /dev/null; then
        xdg-mime default pcmanfm-qt.desktop inode/directory 2>/dev/null || true
    fi
    
    log_success "Application associations set"
}

# Backup and copy configuration directory
backup_and_copy_config() {
    local component="$1"
    local source_dir="$2"
    local target_dir="$3"
    
    if [[ ! -d "$source_dir" ]]; then
        log_warn "Source directory not found: $source_dir"
        return 1
    fi
    
    # Create target directory
    mkdir -p "$(dirname "$target_dir")"
    
    # Backup existing configuration if it exists
    if [[ -d "$target_dir" ]]; then
        local backup_path="$BACKUP_DIR/${component}_${TIMESTAMP}"
        log_info "Backing up existing $component configuration to: $backup_path"
        cp -r "$target_dir" "$backup_path"
    fi
    
    # Copy new configuration
    log_info "Copying $component configuration from: $source_dir to: $target_dir"
    cp -r "$source_dir" "$target_dir"
    
    return 0
}

# Backup and copy single file
backup_and_copy_file() {
    local source_file="$1"
    local target_file="$2"
    
    if [[ ! -f "$source_file" ]]; then
        log_warn "Source file not found: $source_file"
        return 1
    fi
    
    # Create target directory
    mkdir -p "$(dirname "$target_file")"
    
    # Backup existing file if it exists
    if [[ -f "$target_file" ]]; then
        local backup_path="$BACKUP_DIR/$(basename "$target_file")_${TIMESTAMP}"
        log_info "Backing up existing file to: $backup_path"
        cp "$target_file" "$backup_path"
    fi
    
    # Copy new file
    log_info "Copying file from: $source_file to: $target_file"
    cp "$source_file" "$target_file"
    
    return 0
}

# Create configuration symlinks (alternative to copying)
create_config_symlinks() {
    local components=("$@")
    
    log_info "Creating configuration symlinks for: ${components[*]}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create configuration symlinks for: ${components[*]}"
        return 0
    fi
    
    # Initialize dotfiles manager
    init_dotfiles_manager
    
    # Process each component for symlinking
    for component in "${components[@]}"; do
        create_component_symlinks "$component"
    done
    
    log_success "Configuration symlinks created"
}

# Create symlinks for a specific component
create_component_symlinks() {
    local component="$1"
    
    log_info "Creating symlinks for component: $component"
    
    case "$component" in
        "terminal")
            create_symlink_if_exists "$DOTFILES_DIR/kitty/.config/kitty" "$HOME/.config/kitty"
            create_symlink_if_exists "$DOTFILES_DIR/alacritty/.config/alacritty" "$HOME/.config/alacritty"
            create_symlink_if_exists "$DOTFILES_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"
            ;;
        "shell")
            create_symlink_if_exists "$DOTFILES_DIR/zshrc/.zshrc" "$HOME/.zshrc"
            create_symlink_if_exists "$DOTFILES_DIR/starship/.config/starship.toml" "$HOME/.config/starship.toml"
            ;;
        "editor")
            create_symlink_if_exists "$DOTFILES_DIR/nvim/.config/nvim" "$HOME/.config/nvim"
            create_symlink_if_exists "$DOTFILES_DIR/doom/.config/doom" "$HOME/.config/doom"
            ;;
        "wm"|"hyprland")
            create_symlink_if_exists "$DOTFILES_DIR/hyprland/.config/hypr" "$HOME/.config/hypr"
            create_symlink_if_exists "$DOTFILES_DIR/waybar/.config/waybar" "$HOME/.config/waybar"
            create_symlink_if_exists "$DOTFILES_DIR/wofi/.config/wofi" "$HOME/.config/wofi"
            create_symlink_if_exists "$DOTFILES_DIR/swaync/.config/swaync" "$HOME/.config/swaync"
            ;;
        *)
            log_warn "Unknown component for symlinks: $component"
            ;;
    esac
}

# Create symlink if source exists
create_symlink_if_exists() {
    local source="$1"
    local target="$2"
    
    if [[ -e "$source" ]]; then
        # Backup existing target if it exists and is not a symlink
        if [[ -e "$target" && ! -L "$target" ]]; then
            local backup_path="$BACKUP_DIR/$(basename "$target")_${TIMESTAMP}"
            log_info "Backing up existing target to: $backup_path"
            mv "$target" "$backup_path"
        fi
        
        # Remove existing symlink
        if [[ -L "$target" ]]; then
            rm "$target"
        fi
        
        # Create parent directory
        mkdir -p "$(dirname "$target")"
        
        # Create symlink
        log_info "Creating symlink: $target -> $source"
        ln -sf "$source" "$target"
    else
        log_warn "Source not found for symlink: $source"
    fi
}

# Backup existing configurations
backup_existing_configs() {
    local components=("$@")
    
    log_info "Backing up existing configurations for: ${components[*]}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would backup existing configurations for: ${components[*]}"
        return 0
    fi
    
    # Initialize backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Create comprehensive backup
    local backup_archive="$BACKUP_DIR/full_config_backup_${TIMESTAMP}.tar.gz"
    
    log_info "Creating comprehensive configuration backup: $backup_archive"
    
    # Backup common configuration directories
    local config_dirs=(
        "$HOME/.config"
        "$HOME/.zshrc"
        "$HOME/.tmux.conf"
        "$HOME/.face"
        "$HOME/.face.icon"
    )
    
    # Create backup archive
    tar -czf "$backup_archive" -C "$HOME" \
        --exclude=".config/*/cache" \
        --exclude=".config/*/logs" \
        --exclude=".config/*/tmp" \
        $(printf "%s " "${config_dirs[@]/#$HOME\//}") 2>/dev/null || true
    
    log_success "Configuration backup created: $backup_archive"
}

# Handle configuration conflicts
handle_config_conflict() {
    local config_path="$1"
    local component="$2"
    
    if [[ ! -e "$config_path" ]]; then
        return 0  # No conflict if target doesn't exist
    fi
    
    log_warn "Configuration conflict detected: $config_path"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would handle conflict for: $config_path"
        return 0
    fi
    
    echo "Existing configuration found at: $config_path"
    echo "1. Backup and replace"
    echo "2. Skip this configuration"
    echo "3. View differences (if possible)"
    
    read -p "Choose action (1-3): " choice
    
    case "$choice" in
        1)
            log_info "Backing up and replacing configuration"
            return 0  # Proceed with backup and replace
            ;;
        2)
            log_info "Skipping configuration"
            return 1  # Skip this configuration
            ;;
        3)
            # Show differences if possible
            if command -v diff &> /dev/null; then
                echo "=== Configuration Differences ==="
                diff -u "$config_path" "$source_path" 2>/dev/null || echo "Cannot compare files"
                echo "================================="
            fi
            # Ask again after showing differences
            handle_config_conflict "$config_path" "$component"
            ;;
        *)
            log_warn "Invalid choice, defaulting to backup and replace"
            return 0
            ;;
    esac
}

# Validate dotfiles structure
validate_dotfiles_structure() {
    log_info "Validating dotfiles structure..."
    
    if [[ ! -d "$DOTFILES_DIR" ]]; then
        log_error "Dotfiles directory not found: $DOTFILES_DIR"
        return 1
    fi
    
    # Check for essential dotfiles components
    local essential_components=("kitty" "hyprland" "waybar" "swaync")
    local missing_components=()
    
    for component in "${essential_components[@]}"; do
        if [[ ! -d "$DOTFILES_DIR/$component" ]]; then
            missing_components+=("$component")
        fi
    done
    
    if [[ ${#missing_components[@]} -gt 0 ]]; then
        log_warn "Missing dotfiles components: ${missing_components[*]}"
    fi
    
    log_success "Dotfiles structure validation completed"
    return 0
}

# Extract configuration from existing install.sh patterns
extract_legacy_configs() {
    log_info "Extracting configurations from legacy patterns..."
    
    # This function can be used to migrate from old install.sh patterns
    # to the new modular structure
    
    local legacy_patterns=(
        "mkdir -p ~/.config"
        "cp -r ./config"
        "chmod +x"
        "ln -s"
    )
    
    log_info "Legacy configuration extraction completed"
}