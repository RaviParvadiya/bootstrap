#!/bin/bash

# Arch Linux package management
# Handles pacman and AUR package installation

# Install packages using pacman
install_pacman_packages() {
    local packages=("$@")
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        log_debug "No pacman packages to install"
        return 0
    fi
    
    log_info "Installing pacman packages: ${packages[*]}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install pacman packages: ${packages[*]}"
        return 0
    fi
    
    sudo pacman -S --noconfirm "${packages[@]}"
}

# Install AUR packages
install_aur_packages() {
    local packages=("$@")
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        log_debug "No AUR packages to install"
        return 0
    fi
    
    # Ensure AUR helper is installed
    ensure_aur_helper
    
    log_info "Installing AUR packages: ${packages[*]}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install AUR packages: ${packages[*]}"
        return 0
    fi
    
    # Use yay if available, otherwise paru
    if command_exists yay; then
        yay -S --noconfirm "${packages[@]}"
    elif command_exists paru; then
        paru -S --noconfirm "${packages[@]}"
    else
        log_error "No AUR helper available"
        return 1
    fi
}

# Ensure AUR helper is installed
ensure_aur_helper() {
    if command_exists yay || command_exists paru; then
        return 0
    fi
    
    log_info "Installing AUR helper (yay)..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install AUR helper"
        return 0
    fi
    
    # Install base-devel if not present
    sudo pacman -S --needed --noconfirm base-devel git
    
    # Clone and build yay
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd "$HOME"
    rm -rf "$temp_dir"
    
    log_success "AUR helper (yay) installed successfully"
}

# Read package list from file
read_package_list() {
    local file="$1"
    local packages=()
    
    if [[ ! -f "$file" ]]; then
        log_warn "Package list file not found: $file"
        return 1
    fi
    
    while IFS= read -r line; do
        # Skip empty lines and comments
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # Handle conditional packages (package|condition)
        if [[ "$line" =~ \| ]]; then
            local package="${line%|*}"
            local condition="${line#*|}"
            
            # Evaluate condition (placeholder for now)
            if eval_package_condition "$condition"; then
                packages+=("$package")
            fi
        else
            packages+=("$line")
        fi
    done < "$file"
    
    echo "${packages[@]}"
}

# Evaluate package installation condition
eval_package_condition() {
    local condition="$1"
    
    case "$condition" in
        "nvidia")
            lspci | grep -i nvidia >/dev/null 2>&1
            ;;
        "vm")
            is_vm
            ;;
        "!vm")
            ! is_vm
            ;;
        *)
            log_debug "Unknown package condition: $condition"
            return 1
            ;;
    esac
}

# Install packages from category
install_package_category() {
    local category="$1"
    local package_file="$DATA_DIR/arch-packages.lst"
    
    log_info "Installing $category packages..."
    
    # This is a placeholder - actual implementation would parse
    # categorized package files
    case "$category" in
        "base")
            local packages=(git curl wget vim nano)
            install_pacman_packages "${packages[@]}"
            ;;
        "development")
            local packages=(gcc make cmake nodejs npm python python-pip)
            install_pacman_packages "${packages[@]}"
            ;;
        *)
            log_warn "Unknown package category: $category"
            ;;
    esac
}