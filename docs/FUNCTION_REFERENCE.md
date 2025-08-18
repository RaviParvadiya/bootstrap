# Function Reference Guide

This document provides comprehensive documentation for all functions in the Modular Install Framework, including parameters, return values, usage examples, and implementation details.

## Table of Contents

1. [Core Functions](#core-functions)
2. [Distribution Functions](#distribution-functions)
3. [Component Functions](#component-functions)
4. [Configuration Functions](#configuration-functions)
5. [Testing Functions](#testing-functions)
6. [Utility Functions](#utility-functions)

## Core Functions

### Distribution Detection (`core/common.sh`)

#### `detect_distro()`

**Purpose**: Automatically detect the current Linux distribution and set global variables.

**Parameters**: None

**Returns**: 
- `0` - Detection successful
- `1` - Detection failed

**Global Variables Set**:
- `DETECTED_DISTRO` - Distribution name ("arch", "ubuntu", "unsupported")
- `DISTRO_VERSION` - Version string (e.g., "20.04", "rolling")
- `DISTRO_CODENAME` - Codename (e.g., "focal", "jammy")
- `DISTRO_COMPATIBLE` - Compatibility flag ("true"/"false")

**Usage Examples**:
```bash
# Basic detection
detect_distro
echo "Detected: $DETECTED_DISTRO"

# Check if detection was successful
if detect_distro; then
    echo "Distribution: $DETECTED_DISTRO ($DISTRO_VERSION)"
else
    echo "Failed to detect distribution"
fi

# Use in conditional logic
detect_distro
case "$DETECTED_DISTRO" in
    "arch")
        echo "Using Arch Linux procedures"
        ;;
    "ubuntu")
        echo "Using Ubuntu procedures"
        ;;
    *)
        echo "Unsupported distribution"
        exit 1
        ;;
esac
```

**Implementation Details**:
- Primary detection via `/etc/os-release`
- Fallback detection using package managers and system files
- Supports Arch-based distributions (Manjaro, Garuda, etc.)
- Supports Ubuntu-based distributions (Pop!_OS, Linux Mint, etc.)
- Caches results to avoid repeated detection

#### `get_distro()`

**Purpose**: Get the detected distribution name.

**Parameters**: None

**Returns**: Echoes distribution name ("arch", "ubuntu", "unsupported")

**Usage Examples**:
```bash
distro=$(get_distro)
if [[ "$distro" == "arch" ]]; then
    pacman -Syu
elif [[ "$distro" == "ubuntu" ]]; then
    apt update && apt upgrade
fi
```

#### `is_supported_distro()`

**Purpose**: Check if the current distribution is fully supported.

**Parameters**: None

**Returns**:
- `0` - Distribution is supported
- `1` - Distribution is not supported

**Usage Examples**:
```bash
if is_supported_distro; then
    echo "Full support available"
    proceed_with_installation
else
    echo "Limited or no support"
    handle_unsupported_distro
fi
```

### Network Functions (`core/common.sh`)

#### `check_internet()`

**Purpose**: Test internet connectivity using multiple reliable endpoints.

**Parameters**: None

**Returns**:
- `0` - Internet connection available
- `1` - No internet connection

**Usage Examples**:
```bash
# Basic connectivity check
if check_internet; then
    echo "Internet connection available"
    download_packages
else
    echo "No internet connection"
    exit 1
fi

# Use in loops with retry logic
while ! check_internet; do
    echo "Waiting for internet connection..."
    sleep 5
done
```

**Implementation Details**:
- Tests multiple endpoints: Google DNS (8.8.8.8), Cloudflare DNS (1.1.1.1)
- Uses ping with timeout for reliability
- Non-blocking implementation suitable for scripts

#### `check_internet_retry()`

**Purpose**: Check internet connectivity with automatic retry logic.

**Parameters**:
- `$1` - Number of retries (optional, default: 3)

**Returns**:
- `0` - Connection established within retry limit
- `1` - Connection failed after all retries

**Usage Examples**:
```bash
# Use default retry count (3)
if check_internet_retry; then
    echo "Connection established"
fi

# Custom retry count
if check_internet_retry 5; then
    echo "Connection established after up to 5 retries"
else
    echo "Failed to establish connection after 5 attempts"
fi
```

### Package Management Functions (`core/common.sh`)

#### `install_package()`

**Purpose**: Universal package installation wrapper that works across distributions.

**Parameters**:
- `$1` - Package name (required)
- `$2` - Package manager (optional: "auto", "pacman", "apt", "yay", "paru")

**Returns**:
- `0` - Package installed successfully
- `1` - Package installation failed

**Global Variables**:
- `DRY_RUN` - If "true", shows what would be installed
- `VERBOSE` - If "true", shows detailed output

**Usage Examples**:
```bash
# Auto-detect package manager
install_package "git"

# Force specific package manager
install_package "firefox" "apt"

# Install AUR package
install_package "yay-bin" "yay"

# Check installation result
if install_package "neovim"; then
    echo "Neovim installed successfully"
    configure_neovim
else
    echo "Failed to install Neovim"
    exit 1
fi

# Batch installation with error handling
packages=("git" "curl" "wget" "vim")
failed_packages=()

for package in "${packages[@]}"; do
    if ! install_package "$package"; then
        failed_packages+=("$package")
    fi
done

if [[ ${#failed_packages[@]} -gt 0 ]]; then
    echo "Failed to install: ${failed_packages[*]}"
fi
```

**Implementation Details**:
- Automatically detects available package managers
- Supports pacman, apt, yay, paru
- Handles package manager-specific flags and options
- Respects dry-run mode for safe testing
- Provides detailed error messages

#### `install_packages()`

**Purpose**: Install multiple packages with batch processing and error handling.

**Parameters**: Array of package names

**Returns**:
- `0` - All packages installed successfully
- `1` - One or more packages failed to install

**Usage Examples**:
```bash
# Install array of packages
packages=("git" "curl" "wget" "vim" "tmux")
install_packages "${packages[@]}"

# With error handling
if install_packages "${packages[@]}"; then
    echo "All packages installed successfully"
else
    echo "Some packages failed to install"
fi

# Install from different arrays based on distribution
distro=$(get_distro)
case "$distro" in
    "arch")
        arch_packages=("pacman" "yay" "base-devel")
        install_packages "${arch_packages[@]}"
        ;;
    "ubuntu")
        ubuntu_packages=("apt-transport-https" "software-properties-common")
        install_packages "${ubuntu_packages[@]}"
        ;;
esac
```

#### `is_package_installed()`

**Purpose**: Check if a package is installed on the system.

**Parameters**:
- `$1` - Package name (required)
- `$2` - Package manager (optional: "auto", "pacman", "apt")

**Returns**:
- `0` - Package is installed
- `1` - Package is not installed

**Usage Examples**:
```bash
# Check if package is installed
if is_package_installed "git"; then
    echo "Git is already installed"
else
    echo "Installing Git..."
    install_package "git"
fi

# Check with specific package manager
if is_package_installed "firefox" "apt"; then
    echo "Firefox installed via APT"
fi

# Conditional installation
is_package_installed "docker" || install_package "docker"
```

### Interactive Functions (`core/common.sh`)

#### `ask_yes_no()`

**Purpose**: Interactive yes/no prompt with default option support.

**Parameters**:
- `$1` - Prompt message (required)
- `$2` - Default answer (optional: "y", "yes", "n", "no")

**Returns**:
- `0` - User chose yes
- `1` - User chose no

**Global Variables**:
- `DRY_RUN` - If "true", automatically returns default or 0

**Usage Examples**:
```bash
# Simple yes/no question
if ask_yes_no "Do you want to continue?"; then
    echo "User chose to continue"
    proceed_with_installation
else
    echo "User chose to abort"
    exit 0
fi

# With default value
if ask_yes_no "Install NVIDIA drivers?" "y"; then
    install_nvidia_drivers
fi

# With default no
if ask_yes_no "Delete existing configuration?" "n"; then
    rm -rf ~/.config/app
else
    echo "Keeping existing configuration"
fi

# In dry-run mode (automatically uses default)
DRY_RUN=true
if ask_yes_no "Install package?" "y"; then
    echo "Would install package (dry-run mode)"
fi
```

#### `ask_choice()`

**Purpose**: Multi-choice selection prompt.

**Parameters**:
- `$1` - Prompt message (required)
- `$2+` - Available options

**Returns**: Echoes the selected option

**Usage Examples**:
```bash
# Terminal selection
terminal=$(ask_choice "Select terminal emulator:" "kitty" "alacritty" "gnome-terminal")
echo "Selected terminal: $terminal"

# Editor selection with conditional logic
editor=$(ask_choice "Choose your editor:" "neovim" "vim" "nano" "emacs")
case "$editor" in
    "neovim")
        install_package "neovim"
        configure_neovim
        ;;
    "vim")
        install_package "vim"
        ;;
    *)
        install_package "$editor"
        ;;
esac

# Package manager selection
aur_helper=$(ask_choice "Select AUR helper:" "yay" "paru" "trizen")
install_package "$aur_helper"
```

### File Management Functions (`core/common.sh`)

#### `create_symlink()`

**Purpose**: Create safe symlinks with automatic backup of existing files.

**Parameters**:
- `$1` - Source file/directory (required)
- `$2` - Target location (required)

**Returns**:
- `0` - Symlink created successfully
- `1` - Symlink creation failed

**Global Variables**:
- `DRY_RUN` - If "true", shows what would be done
- `HOME` - Used for backup directory location

**Side Effects**:
- Creates backup directory: `~/.config/install-backups/YYYYMMDD_HHMMSS/`
- Backs up existing files before creating symlinks
- Creates parent directories if needed

**Usage Examples**:
```bash
# Link configuration file
create_symlink "$HOME/dotfiles/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"

# Link entire directory
create_symlink "$HOME/dotfiles/nvim" "$HOME/.config/nvim"

# With error handling
if create_symlink "$source" "$target"; then
    echo "Configuration linked successfully"
else
    echo "Failed to create symlink"
    exit 1
fi

# Batch symlink creation
dotfiles_dir="$HOME/dotfiles"
config_dir="$HOME/.config"

configs=("kitty" "alacritty" "nvim" "tmux")
for config in "${configs[@]}"; do
    if [[ -d "$dotfiles_dir/$config" ]]; then
        create_symlink "$dotfiles_dir/$config" "$config_dir/$config"
    fi
done
```

#### `create_symlinks_from_dir()`

**Purpose**: Create symlinks for all items in a source directory.

**Parameters**:
- `$1` - Source directory (required)
- `$2` - Target directory (required)

**Returns**:
- `0` - All symlinks created successfully
- `1` - One or more symlinks failed

**Usage Examples**:
```bash
# Link all dotfiles
create_symlinks_from_dir "$HOME/dotfiles/.config" "$HOME/.config"

# Link specific component configurations
create_symlinks_from_dir "$HOME/dotfiles/terminal" "$HOME/.config"
```

### Permission and Validation Functions (`core/common.sh`)

#### `validate_permissions()`

**Purpose**: Validate user permissions and system requirements.

**Parameters**: None

**Returns**:
- `0` - Permissions are valid
- `1` - Invalid permissions or requirements not met

**Usage Examples**:
```bash
# Check permissions before installation
if validate_permissions; then
    echo "Permissions validated, proceeding with installation"
    run_installation
else
    echo "Permission validation failed"
    exit 1
fi

# Use in installation script
validate_permissions || {
    echo "Please run as a regular user with sudo access"
    exit 1
}
```

#### `has_sudo()`

**Purpose**: Check if user has sudo privileges.

**Parameters**: None

**Returns**:
- `0` - User has sudo access
- `1` - User does not have sudo access

**Usage Examples**:
```bash
# Check sudo access
if has_sudo; then
    echo "Sudo access confirmed"
else
    echo "This script requires sudo access"
    exit 1
fi

# Conditional sudo usage
if has_sudo; then
    sudo pacman -S package
else
    echo "Cannot install packages without sudo"
fi
```

#### `is_root()`

**Purpose**: Check if script is running as root.

**Parameters**: None

**Returns**:
- `0` - Running as root
- `1` - Not running as root

**Usage Examples**:
```bash
# Prevent running as root
if is_root; then
    echo "Do not run this script as root"
    exit 1
fi

# Conditional behavior
if is_root; then
    echo "Running as root - skipping user configuration"
else
    echo "Running as user - configuring user environment"
    configure_user_environment
fi
```

## Logging Functions (`core/logger.sh`)

### `log_info()`

**Purpose**: Log informational messages with timestamp and formatting.

**Parameters**:
- `$1` - Message to log (required)

**Usage Examples**:
```bash
log_info "Starting installation process"
log_info "Installing package: $package_name"
log_info "Configuration completed successfully"
```

### `log_error()`

**Purpose**: Log error messages with red formatting.

**Parameters**:
- `$1` - Error message (required)

**Usage Examples**:
```bash
log_error "Failed to install package: $package_name"
log_error "Configuration file not found: $config_file"
log_error "Network connection failed"
```

### `log_warn()`

**Purpose**: Log warning messages with yellow formatting.

**Parameters**:
- `$1` - Warning message (required)

**Usage Examples**:
```bash
log_warn "Package already installed: $package_name"
log_warn "Configuration file exists, creating backup"
log_warn "Network connection unstable"
```

### `log_success()`

**Purpose**: Log success messages with green formatting.

**Parameters**:
- `$1` - Success message (required)

**Usage Examples**:
```bash
log_success "Package installed successfully: $package_name"
log_success "Configuration applied successfully"
log_success "Installation completed"
```

### `log_section()`

**Purpose**: Log section headers with prominent formatting.

**Parameters**:
- `$1` - Section title (required)

**Usage Examples**:
```bash
log_section "Installing Terminal Components"
log_section "Configuring Shell Environment"
log_section "Setting up Development Tools"
```

## Component Functions

### Terminal Components (`components/terminal/`)

#### `install_kitty()`

**Purpose**: Install and configure Kitty terminal emulator.

**Parameters**: None

**Returns**:
- `0` - Installation successful
- `1` - Installation failed

**Side Effects**:
- Installs Kitty package
- Installs recommended fonts
- Creates configuration symlinks
- Downloads themes

**Usage Examples**:
```bash
# Standard installation
install_kitty

# With error handling
if install_kitty; then
    log_success "Kitty installation completed"
else
    log_error "Kitty installation failed"
    exit 1
fi
```

#### `is_kitty_installed()`

**Purpose**: Check if Kitty is already installed.

**Parameters**: None

**Returns**:
- `0` - Kitty is installed
- `1` - Kitty is not installed

**Usage Examples**:
```bash
# Conditional installation
if ! is_kitty_installed; then
    echo "Installing Kitty..."
    install_kitty
else
    echo "Kitty is already installed"
fi
```

### Shell Components (`components/shell/`)

#### `install_zsh()`

**Purpose**: Install and configure Zsh shell with plugins.

**Parameters**: None

**Returns**:
- `0` - Installation successful
- `1` - Installation failed

**Usage Examples**:
```bash
install_zsh
```

#### `configure_starship()`

**Purpose**: Install and configure Starship prompt.

**Parameters**: None

**Returns**:
- `0` - Configuration successful
- `1` - Configuration failed

**Usage Examples**:
```bash
configure_starship
```

## Testing Functions (`tests/`)

### `run_dry_run()`

**Purpose**: Execute installation in dry-run mode.

**Parameters**: 
- `$1` - Components to test (optional)

**Returns**:
- `0` - Dry-run completed successfully
- `1` - Dry-run failed

**Usage Examples**:
```bash
# Test all components
run_dry_run

# Test specific components
run_dry_run "terminal,shell"
```

### `validate_installation()`

**Purpose**: Validate that installation completed successfully.

**Parameters**: None

**Returns**:
- `0` - Validation passed
- `1` - Validation failed

**Usage Examples**:
```bash
# Post-installation validation
if validate_installation; then
    echo "Installation validated successfully"
else
    echo "Installation validation failed"
fi
```

## Utility Functions

### `get_script_dir()`

**Purpose**: Get the script directory path.

**Parameters**: None

**Returns**: Echoes the script directory path

**Usage Examples**:
```bash
script_dir=$(get_script_dir)
source "$script_dir/core/common.sh"
```

### `is_dry_run()`

**Purpose**: Check if running in dry-run mode.

**Parameters**: None

**Returns**:
- `0` - In dry-run mode
- `1` - Not in dry-run mode

**Usage Examples**:
```bash
if is_dry_run; then
    echo "Would install package: $package"
else
    install_package "$package"
fi
```

### `debug_print()`

**Purpose**: Print debug messages if verbose mode is enabled.

**Parameters**:
- `$*` - Debug message

**Usage Examples**:
```bash
debug_print "Checking package status: $package"
debug_print "Configuration file: $config_file"
```

## Error Handling Patterns

### Standard Error Handling

```bash
# Function with error handling
install_component() {
    local component="$1"
    
    log_info "Installing $component..."
    
    # Check prerequisites
    if ! validate_component_prereqs "$component"; then
        log_error "Prerequisites not met for $component"
        return 1
    fi
    
    # Install packages
    if ! install_component_packages "$component"; then
        log_error "Failed to install packages for $component"
        return 1
    fi
    
    # Apply configuration
    if ! apply_component_config "$component"; then
        log_error "Failed to apply configuration for $component"
        return 1
    fi
    
    log_success "$component installed successfully"
    return 0
}
```

### Cleanup on Error

```bash
# Function with cleanup
install_with_cleanup() {
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Cleanup function
    cleanup() {
        rm -rf "$temp_dir"
    }
    
    # Set trap for cleanup
    trap cleanup EXIT ERR
    
    # Main installation logic
    download_files "$temp_dir"
    install_files "$temp_dir"
    
    # Cleanup happens automatically via trap
}
```

This function reference provides comprehensive documentation for developers working with or extending the Modular Install Framework. Each function includes detailed parameter descriptions, return values, usage examples, and implementation notes.