#!/bin/bash

# Configuration restoration utilities
# Handles configuration restoration and rollback
# Extracted and enhanced from existing dotfiles/install.sh

# Global restoration variables
BACKUP_BASE_DIR="$HOME/.config-backups"
SYSTEM_BACKUP_DIR="$BACKUP_BASE_DIR/system"
COMPONENT_BACKUP_DIR="$BACKUP_BASE_DIR/components"
RESTORE_LOG="$BACKUP_BASE_DIR/restore.log"

# Initialize restoration system
init_restore_system() {
    # Ensure backup directories exist
    mkdir -p "$BACKUP_BASE_DIR" "$SYSTEM_BACKUP_DIR" "$COMPONENT_BACKUP_DIR"
    
    # Initialize restore log
    echo "=== Restore Session Started: $(date) ===" >> "$RESTORE_LOG"
    
    log_info "Restoration system initialized"
}

# Restore from backup
restore_from_backup() {
    local backup_path="$1"
    local target_dir="${2:-$HOME}"
    
    log_info "Restoring from backup: $(basename "$backup_path")"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would restore from backup: $backup_path to: $target_dir"
        show_backup_contents "$backup_path"
        return 0
    fi
    
    # Validate backup file
    if [[ ! -f "$backup_path" ]]; then
        log_error "Backup file not found: $backup_path"
        return 1
    fi
    
    # Verify backup integrity
    if ! verify_backup_integrity "$backup_path"; then
        log_error "Backup integrity check failed: $backup_path"
        return 1
    fi
    
    # Initialize restoration system
    init_restore_system
    
    # Create pre-restore backup
    log_info "Creating pre-restore backup..."
    local pre_restore_backup="$BACKUP_BASE_DIR/pre_restore_$(date +%Y%m%d_%H%M%S).tar.gz"
    create_pre_restore_backup "$pre_restore_backup"
    
    # Extract backup
    log_info "Extracting backup to: $target_dir"
    
    cd "$target_dir" || return 1
    
    if tar -xzf "$backup_path" 2>>"$RESTORE_LOG"; then
        log_success "Backup restored successfully from: $(basename "$backup_path")"
        
        # Log restoration
        echo "Restored: $backup_path to $target_dir at $(date)" >> "$RESTORE_LOG"
        
        # Post-restore tasks
        post_restore_tasks
        
        return 0
    else
        log_error "Failed to restore backup: $(basename "$backup_path")"
        echo "FAILED: $backup_path to $target_dir at $(date)" >> "$RESTORE_LOG"
        return 1
    fi
}

# Restore component configuration
restore_component_config() {
    local component="$1"
    local backup_path="$2"
    
    log_info "Restoring configuration for component: $component"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would restore configuration for: $component from: $backup_path"
        return 0
    fi
    
    # If no specific backup path provided, find the latest backup for the component
    if [[ -z "$backup_path" ]]; then
        backup_path=$(find_latest_component_backup "$component")
        if [[ -z "$backup_path" ]]; then
            log_error "No backup found for component: $component"
            return 1
        fi
    fi
    
    # Validate backup file
    if [[ ! -f "$backup_path" ]]; then
        log_error "Backup file not found: $backup_path"
        return 1
    fi
    
    # Initialize restoration system
    init_restore_system
    
    # Create component-specific pre-restore backup
    log_info "Creating pre-restore backup for component: $component"
    create_config_backup "$component" "Pre-restore backup for $component"
    
    # Restore component configuration
    log_info "Restoring $component configuration from: $(basename "$backup_path")"
    
    cd "$HOME" || return 1
    
    if tar -xzf "$backup_path" 2>>"$RESTORE_LOG"; then
        log_success "Component configuration restored: $component"
        
        # Log restoration
        echo "Component restored: $component from $backup_path at $(date)" >> "$RESTORE_LOG"
        
        # Component-specific post-restore tasks
        post_restore_component_tasks "$component"
        
        return 0
    else
        log_error "Failed to restore component configuration: $component"
        echo "FAILED: Component $component from $backup_path at $(date)" >> "$RESTORE_LOG"
        return 1
    fi
}

# Rollback to previous state
rollback_changes() {
    local rollback_target="${1:-latest}"
    
    log_info "Rolling back changes to: $rollback_target"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would rollback changes to: $rollback_target"
        return 0
    fi
    
    # Initialize restoration system
    init_restore_system
    
    local backup_to_restore=""
    
    case "$rollback_target" in
        "latest")
            backup_to_restore=$(find_latest_system_backup)
            ;;
        "pre-restore")
            backup_to_restore=$(find_latest_pre_restore_backup)
            ;;
        *)
            # Assume it's a specific backup file path
            backup_to_restore="$rollback_target"
            ;;
    esac
    
    if [[ -z "$backup_to_restore" ]]; then
        log_error "No backup found for rollback target: $rollback_target"
        return 1
    fi
    
    log_info "Rolling back using backup: $(basename "$backup_to_restore")"
    
    # Perform rollback
    if restore_from_backup "$backup_to_restore"; then
        log_success "Rollback completed successfully"
        echo "Rollback completed: $backup_to_restore at $(date)" >> "$RESTORE_LOG"
        return 0
    else
        log_error "Rollback failed"
        echo "Rollback FAILED: $backup_to_restore at $(date)" >> "$RESTORE_LOG"
        return 1
    fi
}

# Find latest system backup
find_latest_system_backup() {
    local latest_backup=$(ls -t "$SYSTEM_BACKUP_DIR"/system_backup_*.tar.gz 2>/dev/null | head -n1)
    echo "$latest_backup"
}

# Find latest component backup
find_latest_component_backup() {
    local component="$1"
    local latest_backup=$(ls -t "$COMPONENT_BACKUP_DIR/${component}_backup_"*.tar.gz 2>/dev/null | head -n1)
    echo "$latest_backup"
}

# Find latest pre-restore backup
find_latest_pre_restore_backup() {
    local latest_backup=$(ls -t "$BACKUP_BASE_DIR"/pre_restore_*.tar.gz 2>/dev/null | head -n1)
    echo "$latest_backup"
}

# Create pre-restore backup
create_pre_restore_backup() {
    local backup_file="$1"
    
    log_info "Creating pre-restore backup: $(basename "$backup_file")"
    
    # Define what to backup before restoration
    local backup_paths=(
        ".config"
        ".zshrc"
        ".zprofile"
        ".p10k.zsh"
        ".tmux.conf"
        ".gtkrc-2.0"
        ".face"
        ".face.icon"
    )
    
    cd "$HOME" || return 1
    
    # Filter existing paths
    local existing_paths=()
    for path in "${backup_paths[@]}"; do
        if [[ -e "$path" ]]; then
            existing_paths+=("$path")
        fi
    done
    
    if [[ ${#existing_paths[@]} -gt 0 ]]; then
        tar -czf "$backup_file" "${existing_paths[@]}" 2>/dev/null
        log_info "Pre-restore backup created: $(basename "$backup_file")"
    else
        log_warn "No existing configurations to backup"
    fi
}

# Verify backup integrity
verify_backup_integrity() {
    local backup_file="$1"
    
    log_info "Verifying backup integrity: $(basename "$backup_file")"
    
    if tar -tzf "$backup_file" >/dev/null 2>&1; then
        log_success "Backup integrity verified"
        return 0
    else
        log_error "Backup integrity check failed"
        return 1
    fi
}

# Show backup contents
show_backup_contents() {
    local backup_file="$1"
    
    log_info "Backup contents preview:"
    echo
    tar -tzf "$backup_file" 2>/dev/null | head -20
    
    local total_files=$(tar -tzf "$backup_file" 2>/dev/null | wc -l)
    if [[ $total_files -gt 20 ]]; then
        echo "... and $((total_files - 20)) more files"
    fi
    echo
}

# Post-restore tasks
post_restore_tasks() {
    log_info "Running post-restore tasks..."
    
    # Fix permissions
    fix_restored_permissions
    
    # Update shell if zsh is restored
    if [[ -f "$HOME/.zshrc" ]] && [[ "$SHELL" != "$(which zsh)" ]]; then
        log_info "Updating shell to zsh..."
        chsh -s "$(which zsh)" 2>/dev/null || true
    fi
    
    # Make scripts executable
    make_scripts_executable
    
    # Update user icon symlinks
    update_user_icons
    
    log_success "Post-restore tasks completed"
}

# Component-specific post-restore tasks
post_restore_component_tasks() {
    local component="$1"
    
    log_info "Running post-restore tasks for component: $component"
    
    case "$component" in
        "terminal")
            # Make terminal scripts executable
            if [[ -f "$HOME/.local/bin/xdg-terminal-exec" ]]; then
                chmod +x "$HOME/.local/bin/xdg-terminal-exec"
            fi
            ;;
        "shell")
            # Update shell to zsh if restored
            if [[ -f "$HOME/.zshrc" ]] && [[ "$SHELL" != "$(which zsh)" ]]; then
                chsh -s "$(which zsh)" 2>/dev/null || true
            fi
            ;;
        "wm"|"hyprland")
            # Make Hyprland scripts executable
            if [[ -d "$HOME/.config/hypr/scripts" ]]; then
                chmod +x "$HOME/.config/hypr/scripts"/*.sh 2>/dev/null || true
                chmod +x "$HOME/.config/hypr/scripts"/*.py 2>/dev/null || true
            fi
            
            # Make Waybar scripts executable
            if [[ -d "$HOME/.config/waybar/scripts" ]]; then
                chmod +x "$HOME/.config/waybar/scripts"/*.sh 2>/dev/null || true
            fi
            
            # Make Swaync scripts executable
            if [[ -f "$HOME/.config/swaync/notification-controller.sh" ]]; then
                chmod +x "$HOME/.config/swaync/notification-controller.sh"
            fi
            
            # Update user icons
            update_user_icons
            ;;
    esac
    
    log_success "Component post-restore tasks completed for: $component"
}

# Fix restored file permissions
fix_restored_permissions() {
    log_info "Fixing restored file permissions..."
    
    # Fix .config directory permissions
    if [[ -d "$HOME/.config" ]]; then
        find "$HOME/.config" -type d -exec chmod 755 {} \; 2>/dev/null || true
        find "$HOME/.config" -type f -exec chmod 644 {} \; 2>/dev/null || true
    fi
    
    # Fix shell configuration permissions
    for file in ".zshrc" ".zprofile" ".p10k.zsh" ".tmux.conf" ".gtkrc-2.0"; do
        if [[ -f "$HOME/$file" ]]; then
            chmod 644 "$HOME/$file"
        fi
    done
    
    # Fix .local/bin permissions
    if [[ -d "$HOME/.local/bin" ]]; then
        chmod 755 "$HOME/.local/bin"
        find "$HOME/.local/bin" -type f -exec chmod 755 {} \; 2>/dev/null || true
    fi
}

# Make scripts executable
make_scripts_executable() {
    log_info "Making scripts executable..."
    
    # Hyprland scripts
    if [[ -d "$HOME/.config/hypr/scripts" ]]; then
        chmod +x "$HOME/.config/hypr/scripts"/*.sh 2>/dev/null || true
        chmod +x "$HOME/.config/hypr/scripts"/*.py 2>/dev/null || true
    fi
    
    # Waybar scripts
    if [[ -d "$HOME/.config/waybar/scripts" ]]; then
        chmod +x "$HOME/.config/waybar/scripts"/*.sh 2>/dev/null || true
    fi
    
    # Swaync scripts
    if [[ -f "$HOME/.config/swaync/notification-controller.sh" ]]; then
        chmod +x "$HOME/.config/swaync/notification-controller.sh"
    fi
    
    # Local bin scripts
    if [[ -d "$HOME/.local/bin" ]]; then
        find "$HOME/.local/bin" -type f -exec chmod +x {} \; 2>/dev/null || true
    fi
}

# Update user icon symlinks
update_user_icons() {
    log_info "Updating user icon symlinks..."
    
    if [[ -f "$HOME/.config/hypr/profile-picture.png" ]]; then
        ln -sf "$HOME/.config/hypr/profile-picture.png" "$HOME/.face.icon" 2>/dev/null || true
        ln -sf "$HOME/.config/hypr/profile-picture.png" "$HOME/.face" 2>/dev/null || true
    fi
}

# Interactive restoration menu
interactive_restore() {
    log_info "Starting interactive restoration..."
    
    # Source backup utilities
    source "$CONFIGS_DIR/backup.sh"
    
    echo
    echo "=== Interactive Restoration Menu ==="
    echo "1. Restore from system backup"
    echo "2. Restore component configuration"
    echo "3. Rollback to previous state"
    echo "4. List available backups"
    echo "5. Exit"
    echo
    
    read -p "Select option (1-5): " choice
    
    case "$choice" in
        1)
            interactive_system_restore
            ;;
        2)
            interactive_component_restore
            ;;
        3)
            interactive_rollback
            ;;
        4)
            list_backups
            ;;
        5)
            log_info "Exiting interactive restoration"
            return 0
            ;;
        *)
            log_error "Invalid option: $choice"
            return 1
            ;;
    esac
}

# Interactive system restore
interactive_system_restore() {
    echo
    echo "=== Available System Backups ==="
    
    local backups=($(ls -t "$SYSTEM_BACKUP_DIR"/*.tar.gz 2>/dev/null))
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        log_error "No system backups found"
        return 1
    fi
    
    for i in "${!backups[@]}"; do
        local backup="${backups[$i]}"
        local size=$(du -h "$backup" 2>/dev/null | cut -f1)
        local date=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1)
        echo "$((i+1)). $(basename "$backup") - Size: $size - Date: $date"
    done
    
    echo
    read -p "Select backup to restore (1-${#backups[@]}): " selection
    
    if [[ "$selection" -ge 1 && "$selection" -le ${#backups[@]} ]]; then
        local selected_backup="${backups[$((selection-1))]}"
        
        echo
        log_info "Selected backup: $(basename "$selected_backup")"
        
        if ask_yes_no "Are you sure you want to restore this backup? This will overwrite current configurations"; then
            restore_from_backup "$selected_backup"
        else
            log_info "Restoration cancelled"
        fi
    else
        log_error "Invalid selection: $selection"
        return 1
    fi
}

# Interactive component restore
interactive_component_restore() {
    echo
    echo "=== Available Components ==="
    echo "1. terminal"
    echo "2. shell"
    echo "3. editor"
    echo "4. wm (window manager)"
    echo "5. themes"
    echo "6. dev-tools"
    echo
    
    read -p "Select component (1-6): " choice
    
    local component=""
    case "$choice" in
        1) component="terminal" ;;
        2) component="shell" ;;
        3) component="editor" ;;
        4) component="wm" ;;
        5) component="themes" ;;
        6) component="dev-tools" ;;
        *) 
            log_error "Invalid choice: $choice"
            return 1
            ;;
    esac
    
    local latest_backup=$(find_latest_component_backup "$component")
    
    if [[ -z "$latest_backup" ]]; then
        log_error "No backup found for component: $component"
        return 1
    fi
    
    echo
    log_info "Latest backup for $component: $(basename "$latest_backup")"
    
    if ask_yes_no "Restore this component configuration?"; then
        restore_component_config "$component" "$latest_backup"
    else
        log_info "Component restoration cancelled"
    fi
}

# Interactive rollback
interactive_rollback() {
    echo
    echo "=== Rollback Options ==="
    echo "1. Rollback to latest system backup"
    echo "2. Rollback to pre-restore backup"
    echo "3. Select specific backup"
    echo
    
    read -p "Select rollback option (1-3): " choice
    
    case "$choice" in
        1)
            if ask_yes_no "Rollback to latest system backup?"; then
                rollback_changes "latest"
            fi
            ;;
        2)
            if ask_yes_no "Rollback to pre-restore backup?"; then
                rollback_changes "pre-restore"
            fi
            ;;
        3)
            interactive_system_restore
            ;;
        *)
            log_error "Invalid choice: $choice"
            return 1
            ;;
    esac
}