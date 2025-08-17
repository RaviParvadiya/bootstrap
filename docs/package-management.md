# Package Management System

This document describes the modular package management system that has been extracted and enhanced from the original install.sh.

## Overview

The package management system has been completely modularized and now supports:

- **Structured package lists** in data files instead of hardcoded arrays
- **Conditional package installation** based on hardware and user preferences
- **Automatic hardware detection** for GPU types, laptop/desktop, VM detection
- **AUR helper management** with automatic installation and setup
- **Chaotic-AUR repository** setup and configuration
- **Enhanced pacman configuration** for better performance

## File Structure

```
data/
├── arch-packages.lst      # Official Arch packages
├── aur-packages.lst       # AUR packages
├── ubuntu-packages.lst    # Ubuntu packages
└── component-deps.json    # Component dependency mapping

distros/arch/
├── packages.sh           # Package installation logic
├── repositories.sh       # Repository management
└── arch-main.sh         # Main orchestrator
```

## Package List Format

Package lists use a simple text format with conditional support:

```bash
# Comments start with #
# Empty lines are ignored

# --- Section Headers ---
git
curl
wget

# Conditional packages (package|condition)
nvidia-dkms|nvidia
steam|gaming
batsignal|laptop
```

### Supported Conditions

- `nvidia` - NVIDIA GPU detected
- `amd` - AMD GPU detected  
- `intel` - Intel GPU detected
- `gaming` - User selected gaming packages
- `laptop` - Laptop hardware detected
- `vm` - Virtual machine detected
- `asus` - ASUS hardware detected

## Key Functions

### Package Installation

```bash
# Install from package list with conditions
arch_install_from_package_list "data/arch-packages.lst" "pacman" "nvidia,gaming"

# Install by category with auto-detection
arch_install_packages_auto "all" "gaming"

# Install specific package types
arch_install_pacman_packages "git" "curl" "wget"
arch_install_aur_packages "yay" "visual-studio-code-bin"
```

### Repository Management

```bash
# Setup all repositories (multilib + chaotic-aur)
arch_setup_repositories

# Individual repository functions
arch_enable_multilib
arch_setup_chaotic_aur
arch_update_package_database
```

### System Configuration

```bash
# Complete system setup
arch_setup_system

# Individual configuration functions
arch_configure_pacman      # Enable colors, parallel downloads
arch_configure_makepkg     # Faster compression
arch_setup_reflector       # Mirror management
arch_enable_trim          # SSD optimization
```

### Hardware Detection

```bash
# GPU detection
arch_has_nvidia_gpu
arch_has_amd_gpu
arch_has_intel_gpu

# System type detection
arch_is_laptop
arch_is_vm
arch_is_asus_hardware
```

## Migration from Original install.sh

The following functionality has been extracted and modularized:

### ✅ Completed

1. **Package Arrays** → Structured data files (`data/*.lst`)
2. **AUR Helper Installation** → `arch_ensure_aur_helper()`
3. **Chaotic-AUR Setup** → `arch_setup_chaotic_aur()`
4. **Pacman Configuration** → `arch_configure_pacman()`
5. **Makepkg Optimization** → `arch_configure_makepkg()`
6. **Hardware Detection** → Hardware detection functions
7. **Conditional Installation** → Condition-based package filtering

### Original Package Arrays Migrated

- `PACKAGES` array → `data/arch-packages.lst`
- `YAY_PACKAGES` array → `data/aur-packages.lst`  
- `GAMING_PACKAGES` array → Gaming section in package lists
- `GAMING_PACKAGES_YAY` array → Gaming section in AUR packages

### Enhanced Features

- **Auto-detection**: Automatically detects hardware and system type
- **Dry-run support**: Test installations without making changes
- **Better error handling**: Graceful failure handling and recovery
- **Modular design**: Easy to extend with new distributions or package types
- **Comprehensive logging**: Detailed logging of all operations

## Usage Examples

### Basic Installation

```bash
# Install all packages with auto-detection
arch_install_packages_auto "all"

# Install with specific preferences
arch_install_packages_auto "all" "gaming,laptop"
```

### Custom Installation

```bash
# Setup system configuration
arch_setup_system

# Setup repositories
arch_setup_repositories

# Install base packages
arch_install_packages_by_category "base" "nvidia"

# Install AUR packages
arch_install_packages_by_category "aur" "gaming"
```

### Testing

```bash
# Run in dry-run mode
export DRY_RUN=true
arch_install_packages_auto "all" "gaming"

# Run package management tests
./tests/test-package-management.sh
```

## Benefits

1. **Maintainability**: Package lists are now in separate, editable files
2. **Flexibility**: Easy to add new packages or conditions
3. **Testability**: Comprehensive test suite and dry-run support
4. **Modularity**: Each function has a single responsibility
5. **Extensibility**: Easy to add support for new distributions
6. **Safety**: Backup creation and rollback capabilities
7. **Performance**: Optimized pacman and makepkg configurations

## Future Enhancements

- Support for additional package managers (flatpak, snap)
- Package dependency resolution and conflict detection
- Package installation prioritization and ordering
- Integration with component-specific package requirements
- Package update and maintenance utilities