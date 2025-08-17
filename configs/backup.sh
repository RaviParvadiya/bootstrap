#!/bin/bash

# Configuration backup utilities
# Handles backup creation and management
# Extracted and enhanced from existing dotfiles/install.sh

# Global backup variables
BACKUP_BASE_DIR="$HOME/.config-backups"
SYSTEM_BACKUP_DIR="$BACKUP_BASE_DIR/system"
COMPONENT_BACKUP_DIR="$BACKUP_BASE_DIR/components"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Initialize backup system
init_backup_system() {
    # Create backup directories
    mkdir -p "$BACKUP_BASE_DIR" "$SYSTEM_BACKUP_DIR" "$COMPONENT_BACKUP_DIR"
    
    # Set proper permissions
    chmod 755 "$BACKUP_BASE_DIR"
    
    log_info "Backup system initialized at: $BACKUP_BASE_DIR"
}

# Create comprehensive system backup
create_system_backup() {
    log_info "Creating comprehensive system backup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create system backup at: $SYSTEM_BACKUP_DIR/system_backup_${TIMESTAMP}.tar.gz"
        return 0
    fi
    
    # Initialize backup system
    init_backup_system
    
    local backup_file="$SYSTEM_BACKUP_DIR/system_backup_${TIMESTAMP}.tar.gz"
    
    # Define what to backup
    local backup_paths=(
        ".config"
        ".zshrc"
        ".zprofile"
        ".p10k.zsh"
        ".tmux.conf"
        ".gtkrc-2.0"
        ".face"
        ".face.icon"
        ".local/bin"
        ".local/share/applications"
    )
    
    # Create backup with exclusions
    log_info "Creating system backup archive: $backup_file"
    
    cd "$HOME" || return 1
    
    tar -czf "$backup_file" \
        --exclude="*.cache*" \
        --exclude="*.log*" \
        --exclude="*.tmp*" \
        --exclude="*Cache*" \
        --exclude="*cache*" \
        --exclude="*logs*" \
        --exclude="*Logs*" \
        --exclude=".config/*/cache" \
        --exclude=".config/*/logs" \
        --exclude=".config/*/tmp" \
        --exclude=".config/*/Cache" \
        --exclude=".config/Code*/User/workspaceStorage" \
        --exclude=".config/Code*/User/History" \
        --exclude=".config/discord/Cache" \
        --exclude=".config/google-chrome*/Default/Cache" \
        --exclude=".config/firefox/*/cache2" \
        $(printf "%s " "${backup_paths[@]}") 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        log_success "System backup created: $backup_file"
        
        # Create backup metadata
        create_backup_metadata "$backup_file" "system" "Full system configuration backup"
        
        return 0
    else
        log_error "Failed to create system backup"
        return 1
    fi
}

# Create configuration backup for specific component
create_config_backup() {
    local component="$1"
    local description="${2:-Configuration backup for $component}"
    
    log_info "Creating backup for component: $component"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create backup for: $component"
        return 0
    fi
    
    # Initialize backup system
    init_backup_system
    
    local backup_file="$COMPONENT_BACKUP_DIR/${component}_backup_${TIMESTAMP}.tar.gz"
    
    # Define component-specific backup paths
    local backup_paths=()
    
    case "$component" in
        "terminal")
            backup_paths=(
                ".config/kitty"
                ".config/alacritty"
                ".tmux.conf"
                ".local/bin/xdg-terminal-exec"
            )
            ;;
        "shell")
            backup_paths=(
                ".zshrc"
                ".zprofile"
                ".p10k.zsh"
                ".config/starship.toml"
            )
            ;;
        "editor")
            backup_paths=(
                ".config/nvim"
                ".config/doom"
                ".config/micro"
            )
            ;;
        "wm"|"hyprland")
            backup_paths=(
                ".config/hypr"
                ".config/waybar"
                ".config/wofi"
                ".config/swaync"
                ".config/wlogout"
            )
            ;;
        "themes")
            backup_paths=(
                ".config/gtk-3.0"
                ".config/gtk-4.0"
                ".config/qt5ct"
                ".config/qt6ct"
                ".config/Kvantum"
                ".gtkrc-2.0"
            )
            ;;
        "dev-tools")
            backup_paths=(
                ".gitconfig"
                ".config/git"
            )
            ;;
        *)
            log_warn "Unknown component for backup: $component"
            return 1
            ;;
    esac
    
    # Create component backup
    cd "$HOME" || return 1
    
    # Filter existing paths
    local existing_paths=()
    for path in "${backup_paths[@]}"; do
        if [[ -e "$path" ]]; then
            existing_paths+=("$path")
        fi
    done
    
    if [[ ${#existing_paths[@]} -eq 0 ]]; then
        log_warn "No existing configurations found for component: $component"
        return 1
    fi
    
    log_info "Backing up paths: ${existing_paths[*]}"
    
    tar -czf "$backup_file" "${existing_paths[@]}" 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        log_success "Component backup created: $backup_file"
        
        # Create backup metadata
        create_backup_metadata "$backup_file" "$component" "$description"
        
        return 0
    else
        log_error "Failed to create backup for component: $component"
        return 1
    fi
}

# Create backup metadata file
create_backup_metadata() {
    local backup_file="$1"
    local component="$2"
    local description="$3"
    
    local metadata_file="${backup_file%.tar.gz}.meta"
    
    cat > "$metadata_file" << EOF
# Backup Metadata
BACKUP_FILE=$(basename "$backup_file")
COMPONENT=$component
DESCRIPTION=$description
TIMESTAMP=$TIMESTAMP
DATE=$(date)
USER=$USER
HOSTNAME=$(hostname)
DISTRO=$(lsb_release -d 2>/dev/null | cut -f2 || echo "Unknown")
SIZE=$(du -h "$backup_file" 2>/dev/null | cut -f1 || echo "Unknown")
EOF
    
    log_info "Backup metadata created: $metadata_file"
}

# List available backups
list_backups() {
    log_info "Listing available backups..."
    
    init_backup_system
    
    echo
    echo "=== System Backups ==="
    if [[ -d "$SYSTEM_BACKUP_DIR" ]] && [[ -n "$(ls -A "$SYSTEM_BACKUP_DIR"/*.tar.gz 2>/dev/null)" ]]; then
        for backup in "$SYSTEM_BACKUP_DIR"/*.tar.gz; do
            if [[ -f "$backup" ]]; then
                local meta_file="${backup%.tar.gz}.meta"
                local size=$(du -h "$backup" 2>/dev/null | cut -f1 || echo "Unknown")
                local date=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1 || echo "Unknown")
                
                echo "  $(basename "$backup") - Size: $size - Date: $date"
                
                if [[ -f "$meta_file" ]]; then
                    local description=$(grep "^DESCRIPTION=" "$meta_file" 2>/dev/null | cut -d'=' -f2- || echo "No description")
                    echo "    Description: $description"
                fi
            fi
        done
    else
        echo "  No system backups found"
    fi
    
    echo
    echo "=== Component Backups ==="
    if [[ -d "$COMPONENT_BACKUP_DIR" ]] && [[ -n "$(ls -A "$COMPONENT_BACKUP_DIR"/*.tar.gz 2>/dev/null)" ]]; then
        for backup in "$COMPONENT_BACKUP_DIR"/*.tar.gz; do
            if [[ -f "$backup" ]]; then
                local meta_file="${backup%.tar.gz}.meta"
                local size=$(du -h "$backup" 2>/dev/null | cut -f1 || echo "Unknown")
                local date=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1 || echo "Unknown")
                
                echo "  $(basename "$backup") - Size: $size - Date: $date"
                
                if [[ -f "$meta_file" ]]; then
                    local component=$(grep "^COMPONENT=" "$meta_file" 2>/dev/null | cut -d'=' -f2 || echo "Unknown")
                    local description=$(grep "^DESCRIPTION=" "$meta_file" 2>/dev/null | cut -d'=' -f2- || echo "No description")
                    echo "    Component: $component"
                    echo "    Description: $description"
                fi
            fi
        done
    else
        echo "  No component backups found"
    fi
    
    echo
    echo "Backup directory: $BACKUP_BASE_DIR"
    
    # Show total backup size
    local total_size=$(du -sh "$BACKUP_BASE_DIR" 2>/dev/null | cut -f1 || echo "Unknown")
    echo "Total backup size: $total_size"
}

# Clean old backups (keep last N backups)
clean_old_backups() {
    local keep_count="${1:-5}"
    
    log_info "Cleaning old backups (keeping last $keep_count)..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would clean old backups"
        return 0
    fi
    
    # Clean system backups
    if [[ -d "$SYSTEM_BACKUP_DIR" ]]; then
        local system_backups=($(ls -t "$SYSTEM_BACKUP_DIR"/*.tar.gz 2>/dev/null))
        if [[ ${#system_backups[@]} -gt $keep_count ]]; then
            log_info "Removing old system backups..."
            for ((i=$keep_count; i<${#system_backups[@]}; i++)); do
                local backup="${system_backups[$i]}"
                local meta_file="${backup%.tar.gz}.meta"
                
                log_info "Removing old backup: $(basename "$backup")"
                rm -f "$backup" "$meta_file"
            done
        fi
    fi
    
    # Clean component backups by component type
    if [[ -d "$COMPONENT_BACKUP_DIR" ]]; then
        local components=($(ls "$COMPONENT_BACKUP_DIR"/*.tar.gz 2>/dev/null | sed 's/.*\/\([^_]*\)_backup_.*/\1/' | sort -u))
        
        for component in "${components[@]}"; do
            local component_backups=($(ls -t "$COMPONENT_BACKUP_DIR/${component}_backup_"*.tar.gz 2>/dev/null))
            if [[ ${#component_backups[@]} -gt $keep_count ]]; then
                log_info "Removing old $component backups..."
                for ((i=$keep_count; i<${#component_backups[@]}; i++)); do
                    local backup="${component_backups[$i]}"
                    local meta_file="${backup%.tar.gz}.meta"
                    
                    log_info "Removing old backup: $(basename "$backup")"
                    rm -f "$backup" "$meta_file"
                done
            fi
        done
    fi
    
    log_success "Old backup cleanup completed"
}

# Verify backup integrity
verify_backup() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi
    
    log_info "Verifying backup integrity: $(basename "$backup_file")"
    
    # Test tar file integrity
    if tar -tzf "$backup_file" >/dev/null 2>&1; then
        log_success "Backup integrity verified: $(basename "$backup_file")"
        return 0
    else
        log_error "Backup integrity check failed: $(basename "$backup_file")"
        return 1
    fi
}

# Get backup information
get_backup_info() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi
    
    local meta_file="${backup_file%.tar.gz}.meta"
    
    echo "=== Backup Information ==="
    echo "File: $(basename "$backup_file")"
    echo "Size: $(du -h "$backup_file" 2>/dev/null | cut -f1 || echo "Unknown")"
    echo "Date: $(stat -c %y "$backup_file" 2>/dev/null || echo "Unknown")"
    
    if [[ -f "$meta_file" ]]; then
        echo
        echo "=== Metadata ==="
        cat "$meta_file"
    fi
    
    echo
    echo "=== Contents ==="
    tar -tzf "$backup_file" 2>/dev/null | head -20
    
    local total_files=$(tar -tzf "$backup_file" 2>/dev/null | wc -l)
    if [[ $total_files -gt 20 ]]; then
        echo "... and $((total_files - 20)) more files"
    fi
}