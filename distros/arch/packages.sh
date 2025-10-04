#!/usr/bin/env bash

# Arch Linux package management with pacman and AUR support

source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"
source "$CORE_DIR/common.sh"
source "$CORE_DIR/logger.sh"

arch_install_pacman_packages() {
    local packages=("$@")
    
    [[ ${#packages[@]} -eq 0 ]] && { log_warn "No packages specified"; return 0; }
    
    log_info "Installing pacman packages: ${packages[*]}"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] pacman -S --needed --noconfirm ${packages[*]}"
        return 0
    fi
    
    if ! sudo pacman -S --needed --noconfirm "${packages[@]}"; then
        log_error "Failed to install pacman packages"
        return 1
    fi
    
    log_success "Pacman packages installed"
}

arch_install_aur_packages() {
    local packages=("$@")
    local aur_helper
    
    [[ ${#packages[@]} -eq 0 ]] && { log_warn "No AUR packages specified"; return 0; }
    
    aur_helper=$(arch_get_aur_helper)
    [[ -z "$aur_helper" ]] && { log_error "No AUR helper available"; return 1; }
    
    log_info "Installing AUR packages with $aur_helper: ${packages[*]}"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] $aur_helper -S --needed --noconfirm ${packages[*]}"
        return 0
    fi
    
    local failed_packages=()
    
    for package in "${packages[@]}"; do
        if ! $aur_helper -S --needed --noconfirm "$package"; then
            failed_packages+=("$package")
            log_warn "Failed to install: $package"
        fi
    done
    
    if [[ ${#failed_packages[@]} -gt 0 ]]; then
        log_error "Failed AUR packages: ${failed_packages[*]}"
        return 1
    fi
    
    log_success "AUR packages installed"
}

arch_get_aur_helper() {
    local helpers=("yay" "paru" "trizen" "yaourt")
    
    for helper in "${helpers[@]}"; do
        command -v "$helper" >/dev/null 2>&1 && { echo "$helper"; return 0; }
    done
    
    return 1
}

arch_ensure_aur_helper() {
    if arch_get_aur_helper >/dev/null 2>&1; then
        log_info "AUR helper available: $(arch_get_aur_helper)"
        return 0
    fi
    
    log_info "Installing yay AUR helper..."
    
    [[ "${DRY_RUN:-false}" == "true" ]] && { log_info "[DRY RUN] Would install yay"; return 0; }
    
    sudo pacman -S --needed --noconfirm base-devel git || { log_error "Failed to install yay dependencies"; return 1; }
    
    local temp_dir
    temp_dir=$(mktemp -d)
    
    (
        cd "$temp_dir" || exit 1
        git clone https://aur.archlinux.org/yay.git
        cd yay || exit 1
        makepkg -si --noconfirm
    )
    
    local result=$?
    rm -rf "$temp_dir"
    
    [[ $result -ne 0 ]] && { log_error "Failed to build yay"; return 1; }
    
    log_success "yay installed"
}

arch_install_from_package_list() {
    local package_list_file="$1"
    local package_type="${2:-pacman}"
    local conditions="${3:-}"
    
    [[ ! -f "$package_list_file" ]] && { log_error "Package list not found: $package_list_file"; return 1; }
    
    log_info "Installing from $package_list_file ($package_type)"
    
    local packages=()
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        if [[ "$line" =~ \| ]]; then
            local package="${line%%|*}"
            local condition="${line##*|}"
            arch_should_include_condition "$condition" "$conditions" && packages+=("$package")
        else
            packages+=("$line")
        fi
    done < "$package_list_file"
    
    [[ ${#packages[@]} -eq 0 ]] && { log_warn "No packages to install"; return 0; }
    
    case "$package_type" in
        "pacman") arch_install_pacman_packages "${packages[@]}" ;;
        "aur") arch_install_aur_packages "${packages[@]}" ;;
        *) log_error "Unknown package type: $package_type"; return 1 ;;
    esac
}

arch_should_include_condition() {
    local condition="$1"
    local user_conditions="$2"
    
    case "$condition" in
        "nvidia") arch_has_nvidia_gpu && [[ "$user_conditions" =~ nvidia ]] ;;
        "amd") arch_has_amd_gpu && [[ "$user_conditions" =~ amd ]] ;;
        "intel") arch_has_intel_gpu && [[ "$user_conditions" =~ intel ]] ;;
        "gaming") [[ "$user_conditions" =~ gaming ]] ;;
        "laptop") arch_is_laptop && [[ "$user_conditions" =~ laptop ]] ;;
        "vm") arch_is_vm && [[ "$user_conditions" =~ vm ]] ;;
        "asus") arch_is_asus_hardware && [[ "$user_conditions" =~ asus ]] ;;
        *) return 0 ;;
    esac
}

arch_install_packages_by_category() {
    local category="$1"
    local conditions="${2:-}"
    local data_dir="${3:-$DATA_DIR}"
    local use_minimal="${4:-true}"
    
    local suffix=""
    [[ "$use_minimal" == "true" ]] && suffix="-minimal"
    
    local arch_list="$data_dir/arch-packages${suffix}.lst"
    local aur_list="$data_dir/aur-packages${suffix}.lst"
    
    log_info "Installing $category packages (conditions: $conditions)"
    
    case "$category" in
        "base"|"system")
            arch_install_from_package_list "$arch_list" "pacman" "$conditions"
            ;;
        "aur")
            arch_ensure_aur_helper || return 1
            arch_install_from_package_list "$aur_list" "aur" "$conditions"
            ;;
        "all")
            arch_install_packages_by_category "base" "$conditions" "$data_dir" "$use_minimal" || local base_failed=true
            arch_install_packages_by_category "aur" "$conditions" "$data_dir" "$use_minimal" || local aur_failed=true
            
            if [[ "$base_failed" == "true" || "$aur_failed" == "true" ]]; then
                log_warn "Some packages failed to install"
                return 1
            fi
            ;;
        *)
            log_error "Unknown category: $category"
            return 1
            ;;
    esac
}

arch_install_base_packages() {
    local use_minimal="${1:-true}"
    local base_packages
    
    if [[ "$use_minimal" == "true" ]]; then
        base_packages=("git" "curl" "wget" "unzip" "tar")
    else
        base_packages=("base-devel" "git" "curl" "wget" "unzip" "tar" "gzip" "sudo" "which" "man-db" "man-pages")
    fi
    
    arch_install_pacman_packages "${base_packages[@]}"
}

arch_has_nvidia_gpu() {
    lspci | grep -i nvidia >/dev/null 2>&1
}

arch_has_intel_gpu() {
    lspci | grep -i "intel.*graphics\|intel.*vga" >/dev/null 2>&1
}

arch_has_amd_gpu() {
    lspci | grep -i "amd\|ati" >/dev/null 2>&1
}

arch_is_laptop() {
    [[ -d /sys/class/power_supply/BAT* ]] || \
    [[ -f /sys/class/dmi/id/chassis_type && "$(cat /sys/class/dmi/id/chassis_type 2>/dev/null)" =~ ^(8|9|10|14)$ ]]
}

arch_is_vm() {
    systemd-detect-virt >/dev/null 2>&1 || \
    [[ "$(dmidecode -s system-manufacturer 2>/dev/null)" =~ (VMware|VirtualBox|QEMU|Xen|Microsoft Corporation) ]] || \
    grep -q "hypervisor" /proc/cpuinfo 2>/dev/null
}

arch_is_asus_hardware() {
    [[ "$(dmidecode -s system-manufacturer 2>/dev/null)" =~ ASUS ]] || \
    [[ "$(dmidecode -s baseboard-manufacturer 2>/dev/null)" =~ ASUS ]]
}

arch_is_package_installed() {
    pacman -Qi "$1" >/dev/null 2>&1
}

arch_get_package_version() {
    pacman -Qi "$1" 2>/dev/null | awk '/Version/ {print $3}'
}

arch_remove_packages() {
    local packages=("$@")
    
    [[ ${#packages[@]} -eq 0 ]] && { log_warn "No packages specified for removal"; return 0; }
    
    log_info "Removing packages: ${packages[*]}"
    
    [[ "${DRY_RUN:-false}" == "true" ]] && { log_info "[DRY RUN] pacman -Rs --noconfirm ${packages[*]}"; return 0; }
    
    if ! sudo pacman -Rs --noconfirm "${packages[@]}"; then
        log_error "Failed to remove packages"
        return 1
    fi
    
    log_success "Packages removed"
}

arch_clean_package_cache() {
    log_info "Cleaning package cache"
    
    [[ "${DRY_RUN:-false}" == "true" ]] && { log_info "[DRY RUN] pacman -Sc --noconfirm"; return 0; }
    
    sudo pacman -Sc --noconfirm || log_warn "Failed to clean package cache"
}

# Export core functions
export -f arch_install_pacman_packages arch_install_aur_packages arch_get_aur_helper
export -f arch_ensure_aur_helper arch_install_from_package_list arch_install_base_packages
export -f arch_is_package_installed arch_get_package_version arch_remove_packages
export -f arch_clean_package_cache

arch_configure_pacman() {
    local pacman_conf="/etc/pacman.conf"
    
    log_info "Configuring pacman"
    
    [[ "${DRY_RUN:-false}" == "true" ]] && { log_info "[DRY RUN] Would configure pacman"; return 0; }
    
    sudo cp "$pacman_conf" "$pacman_conf.backup.$(date +%Y%m%d_%H%M%S)"
    sudo sed -i 's/^#Color/Color/; s/^#VerbosePkgLists/VerbosePkgLists/; s/^#ParallelDownloads = 5/ParallelDownloads = 5/' "$pacman_conf"
    
    log_success "Pacman configured"
}

arch_configure_makepkg() {
    local makepkg_conf="/etc/makepkg.conf"
    
    log_info "Configuring makepkg"
    
    [[ "${DRY_RUN:-false}" == "true" ]] && { log_info "[DRY RUN] Would configure makepkg"; return 0; }
    
    sudo cp "$makepkg_conf" "$makepkg_conf.backup.$(date +%Y%m%d_%H%M%S)"
    sudo sed -i 's/COMPRESSZST=(zstd -c -T0 --ultra -20 -)/COMPRESSZST=(zstd -c -T0 --fast -)/' "$makepkg_conf"
    
    log_success "Makepkg configured"
}

arch_setup_reflector() {
    log_info "Setting up reflector"
    
    arch_is_package_installed "reflector" || arch_install_pacman_packages "reflector"
    
    [[ "${DRY_RUN:-false}" == "true" ]] && { log_info "[DRY RUN] Would configure reflector"; return 0; }
    
    sudo systemctl enable reflector.timer
    sudo systemctl start reflector.timer
    
    log_success "Reflector configured"
}

arch_enable_trim() {
    log_info "Enabling SSD TRIM"
    
    [[ "${DRY_RUN:-false}" == "true" ]] && { log_info "[DRY RUN] Would enable fstrim.timer"; return 0; }
    
    sudo systemctl enable fstrim.timer
    log_success "TRIM enabled"
}

arch_setup_system() {
    log_info "Setting up Arch Linux system"
    
    arch_configure_pacman
    arch_configure_makepkg
    arch_setup_reflector
    arch_enable_trim
    
    log_success "System setup completed"
}

arch_install_packages_auto() {
    local category="$1"
    local user_preferences="${2:-}"
    local use_minimal="${3:-true}"
    
    local conditions=()
    
    arch_has_nvidia_gpu && conditions+=("nvidia")
    arch_has_amd_gpu && conditions+=("amd")
    arch_has_intel_gpu && conditions+=("intel")
    arch_is_laptop && conditions+=("laptop")
    arch_is_vm && conditions+=("vm")
    arch_is_asus_hardware && conditions+=("asus")
    
    if [[ -n "$user_preferences" ]]; then
        IFS=',' read -ra user_prefs <<< "$user_preferences"
        conditions+=("${user_prefs[@]}")
    fi
    
    local conditions_str="${conditions[*]}"
    log_info "Auto-detected conditions: $conditions_str"
    
    arch_install_packages_by_category "$category" "$conditions_str" "$DATA_DIR" "$use_minimal"
}

# Export system functions
export -f arch_configure_pacman arch_configure_makepkg arch_setup_reflector arch_enable_trim
export -f arch_setup_system arch_install_packages_auto arch_install_packages_by_category
export -f arch_has_nvidia_gpu arch_has_intel_gpu arch_has_amd_gpu arch_should_include_condition
export -f arch_is_laptop arch_is_vm arch_is_asus_hardware