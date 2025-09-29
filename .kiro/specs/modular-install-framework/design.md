# Design Document

## Overview

The Modular Install Framework is designed as a hierarchical, component-based system that can restore complete Linux development environments across different distributions. The architecture emphasizes modularity, extensibility, and safety through clear separation of concerns and comprehensive testing capabilities.

The framework follows a three-tier architecture:
1. **Core Layer**: Distribution detection, common utilities, and orchestration
2. **Distribution Layer**: Distro-specific package managers, repositories, and system configurations  
3. **Component Layer**: Individual tools, configurations, and services that can be selectively installed

## Architecture

### Directory Structure

```
/
├── install.sh                    # Main entry point
├── README.md                     # User installation guide
├── TESTING.md                    # Testing and safety guide
├── core/
│   ├── common.sh                 # Shared functions and utilities
│   ├── logger.sh                 # Logging and output management
│   ├── validator.sh              # System validation and prerequisites
│   └── menu.sh                   # Interactive component selection
├── distros/
│   ├── arch/
│   │   ├── arch-main.sh          # Arch Linux orchestrator
│   │   ├── packages.sh           # Package installation logic
│   │   ├── repositories.sh       # Repository and AUR setup
│   │   ├── services.sh           # Service management
│   │   └── hardware/
│   │       ├── nvidia.sh         # NVIDIA GPU configuration
│   │       └── asus-tuf.sh       # ASUS TUF specific tweaks
│   └── ubuntu/
│       ├── ubuntu-main.sh        # Ubuntu orchestrator
│       ├── packages.sh           # APT and snap package management
│       ├── repositories.sh       # PPA and repository setup
│       └── hyprland.sh           # Hyprland installation for Ubuntu
├── components/
│   ├── terminal/
│   │   ├── alacritty.sh          # Alacritty terminal setup
│   │   ├── kitty.sh              # Kitty terminal setup
│   │   └── tmux.sh               # Tmux configuration
│   ├── shell/
│   │   ├── zsh.sh                # Zsh and plugins setup
│   │   └── starship.sh           # Starship prompt configuration
│   ├── editor/
│   │   ├── neovim.sh             # Neovim configuration
│   │   └── vscode.sh             # VS Code setup
│   ├── wm/
│   │   ├── hyprland.sh           # Hyprland window manager
│   │   ├── waybar.sh             # Waybar configuration
│   │   ├── wofi.sh               # Wofi launcher
│   │   └── swaync.sh             # Notification daemon
│   └── dev-tools/
│       ├── git.sh                # Git configuration
│       ├── docker.sh             # Docker setup
│       └── languages.sh          # Programming language tools
├── configs/
│   ├── dotfiles-manager.sh       # Dotfiles symlink management
│   ├── backup.sh                 # Configuration backup utilities
│   └── restore.sh                # Configuration restoration
├── data/
│   ├── arch-packages.lst         # Arch package lists
│   ├── ubuntu-packages.lst       # Ubuntu package lists
│   ├── aur-packages.lst          # AUR package lists
│   ├── component-deps.json       # Component dependency mapping
│   └── hardware-profiles.json    # Hardware-specific configurations
└── tests/
    ├── dry-run.sh                # Dry run testing
    ├── vm-test.sh                # VM testing utilities
    └── validate.sh               # Post-installation validation
```

## Components and Interfaces

### Core Components

#### Main Entry Point (`install.sh`)
- **Purpose**: Primary script that users execute
- **Responsibilities**: 
  - Parse command-line arguments
  - Initialize logging
  - Detect distribution
  - Route to appropriate distribution handler
- **Interface**: Command-line arguments for mode selection (install, restore, test, etc.)

#### Common Utilities (`core/common.sh`)
- **Purpose**: Shared functions used across all modules
- **Key Functions**:
  - `detect_distro()`: Identify current Linux distribution
  - `check_internet()`: Verify internet connectivity
  - `ask_yes_no()`: Interactive confirmation prompts
  - `install_package()`: Universal package installation wrapper
  - `create_symlink()`: Safe symlink creation with backup

#### Logger (`core/logger.sh`)
- **Purpose**: Centralized logging and output management
- **Features**:
  - Color-coded output levels (info, warn, error, success)
  - File logging with timestamps
  - Dry-run mode support
  - Progress indicators

#### Validator (`core/validator.sh`)
- **Purpose**: System validation and prerequisite checking
- **Functions**:
  - `validate_system()`: Check system requirements
  - `validate_permissions()`: Verify user permissions
  - `validate_dependencies()`: Check for required tools

#### Interactive Menu (`core/menu.sh`)
- **Purpose**: Component selection interface
- **Features**:
  - Multi-select component menu
  - Dependency resolution display
  - Installation summary preview

### Distribution-Specific Components

#### Arch Linux Handler (`distros/arch/`)
- **Main Script**: `arch-main.sh` - orchestrates Arch-specific installation
- **Package Manager**: `packages.sh` - handles pacman and AUR packages
- **Repository Setup**: `repositories.sh` - configures multilib, chaotic-aur
- **Service Management**: `services.sh` - systemd service configuration

#### Ubuntu Handler (`distros/ubuntu/`)
- **Main Script**: `ubuntu-main.sh` - orchestrates Ubuntu-specific installation
- **Package Manager**: `packages.sh` - handles apt, snap, and flatpak
- **Repository Setup**: `repositories.sh` - manages PPAs and external repos
- **Hyprland Setup**: `hyprland.sh` - builds and configures Hyprland from source

### Component Modules

Each component module follows a standard interface:

```bash
# Standard component interface
install_component() {
    local component_name="$1"
    local dry_run="${2:-false}"
    
    log_info "Installing $component_name..."
    
    # Check if already installed
    if is_installed "$component_name"; then
        log_warn "$component_name already installed, skipping..."
        return 0
    fi
    
    # Install packages
    install_packages "${component_name}_packages[@]"
    
    # Apply configurations
    apply_configs "$component_name"
    
    # Post-install setup
    post_install_setup "$component_name"
    
    log_success "$component_name installation complete"
}
```

## Data Models

### Component Dependency Model (`data/component-deps.json`)
```json
{
  "components": {
    "hyprland": {
      "packages": {
        "arch": ["hyprland", "waybar", "wofi", "grim", "slurp"],
        "ubuntu": ["build-essential", "cmake", "libwayland-dev"]
      },
      "dependencies": ["terminal", "shell"],
      "conflicts": ["gnome", "kde"],
      "post_install": ["enable_hyprland_session"]
    },
    "terminal": {
      "options": ["alacritty", "kitty"],
      "default": "kitty",
      "packages": {
        "arch": ["kitty", "alacritty"],
        "ubuntu": ["kitty", "alacritty"]
      }
    }
  }
}
```

### Hardware Profile Model (`data/hardware-profiles.json`)
```json
{
  "profiles": {
    "asus-tuf-dash-f15": {
      "gpu": "nvidia",
      "features": ["mux_switch", "optimus"],
      "packages": {
        "arch": ["nvidia-dkms", "nvidia-utils", "optimus-manager"]
      },
      "configs": {
        "nvidia_modeset": true,
        "nvidia_drm_fbdev": true
      }
    }
  }
}
```

### Package Lists
- **Format**: Simple text files with package names, one per line
- **Comments**: Lines starting with `#` are ignored
- **Sections**: Use `# --- Section Name ---` for organization
- **Conditional**: Support `package_name|condition` syntax

## Error Handling

### Error Categories
1. **Critical Errors**: System incompatibility, missing permissions
2. **Package Errors**: Failed installations, missing dependencies
3. **Configuration Errors**: File conflicts, invalid configurations
4. **Network Errors**: Download failures, repository issues

### Error Handling Strategy
- **Graceful Degradation**: Continue with remaining components when possible
- **Rollback Capability**: Restore backups on critical failures
- **User Notification**: Clear error messages with suggested actions
- **Logging**: Comprehensive error logging for debugging

### Recovery Mechanisms
```bash
handle_error() {
    local error_type="$1"
    local error_msg="$2"
    local component="$3"
    
    case "$error_type" in
        "critical")
            log_error "Critical error: $error_msg"
            cleanup_and_exit 1
            ;;
        "package")
            log_warn "Package error in $component: $error_msg"
            add_to_failed_list "$component"
            ;;
        "config")
            log_warn "Configuration error: $error_msg"
            restore_backup "$component"
            ;;
    esac
}
```

## Testing Strategy

### Testing Modes

#### Dry Run Mode
- **Purpose**: Show what would be executed without making changes
- **Implementation**: All functions check `$DRY_RUN` flag
- **Output**: Detailed log of planned operations

#### VM Testing Mode
- **Purpose**: Safe testing in virtual machines
- **Features**: Skip hardware-specific configurations
- **Validation**: Automated post-install checks

#### Backup Mode
- **Purpose**: Create backups before making changes
- **Strategy**: Timestamp-based backup directories
- **Restoration**: Automated rollback capability

### Validation Tests
1. **Pre-installation**: System requirements, permissions, connectivity
2. **During installation**: Package availability, dependency resolution
3. **Post-installation**: Service status, configuration validity, functionality

### Test Structure
```bash
# Test framework integration
run_tests() {
    local test_mode="$1"
    
    case "$test_mode" in
        "dry-run")
            export DRY_RUN=true
            run_installation
            ;;
        "vm")
            export VM_MODE=true
            run_installation
            validate_installation
            ;;
        "backup")
            create_system_backup
            run_installation
            ;;
    esac
}
```

## Security Considerations

### Permission Management
- **Principle**: Minimal privilege escalation
- **Implementation**: Sudo only when necessary
- **Validation**: Check permissions before operations

### Package Verification
- **GPG Signatures**: Verify package signatures when possible
- **Checksums**: Validate downloaded files
- **Source Verification**: Use official repositories when available

### Configuration Safety
- **Backup First**: Always backup existing configurations
- **Validation**: Validate configuration files before applying
- **Sandboxing**: Test configurations in isolated environments when possible

## Performance Considerations

### Parallel Processing
- **Package Installation**: Install independent packages in parallel
- **Configuration Application**: Apply non-conflicting configs simultaneously
- **Download Optimization**: Parallel downloads where supported

### Caching Strategy
- **Package Cache**: Leverage distribution package caches
- **Configuration Cache**: Cache processed configuration files
- **Dependency Cache**: Cache dependency resolution results

### Resource Management
- **Memory Usage**: Monitor and limit memory consumption
- **Disk Space**: Check available space before operations
- **Network Usage**: Optimize download patterns and retry logic