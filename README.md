# Modular Install Framework

A comprehensive, modular installation framework for automating Linux development environment setup. Supports both Arch Linux (complete installation) and Ubuntu (Hyprland environment installation) with consistent configuration management and hardware-specific optimizations.

## Features

- **Multi-Distribution Support**: Arch Linux and Ubuntu
- **Modular Architecture**: Install only what you need
- **Interactive Component Selection**: Choose components through an intuitive menu
- **Hardware Detection**: Automatic NVIDIA GPU and ASUS TUF laptop support
- **Safety Features**: Dry-run mode, backups, and VM testing
- **Comprehensive Logging**: Detailed operation logs and progress tracking
- **Service Management**: No auto-start policy - you control what runs

## Quick Start

### Prerequisites

- Linux system (Arch Linux or Ubuntu 18.04+)
- Internet connection
- Sudo access (do not run as root)
- Basic tools: `curl`, `git`, `tar`, `unzip`

### Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd modular-install-framework
```

2. Make the script executable:
```bash
chmod +x install.sh
```

3. Run the installation:
```bash
./install.sh
```

## Usage

### Basic Usage

```bash
# Interactive installation with component selection
./install.sh

# Dry-run mode (preview without changes)
./install.sh --dry-run

# Install specific components
./install.sh --components terminal,shell,editor

# VM-safe mode (skips hardware-specific configs)
./install.sh --test

# Verbose output
./install.sh --verbose
```

### Available Commands

- `install` - Run interactive installation (default)
- `restore` - Restore from backup
- `validate` - Validate current installation
- `backup` - Create system backup
- `list` - List available components

### Component Selection

The framework offers the following components:

- **terminal** - Terminal emulators (Alacritty, Kitty)
- **shell** - Shell configuration (Zsh, Starship)
- **editor** - Text editors (Neovim, VS Code)
- **wm** - Window manager (Hyprland, Waybar, Wofi)
- **dev-tools** - Development tools (Git, Docker, Languages)
- **hardware** - Hardware-specific configurations (NVIDIA, ASUS)

Dependencies are automatically resolved during selection.

## Distribution-Specific Information

### Arch Linux

- **Full Installation**: Complete system setup from base installation
- **Package Management**: Pacman + AUR (yay/paru)
- **Repository Setup**: Multilib, Chaotic-AUR
- **Hardware Support**: Full NVIDIA and ASUS TUF support

### Ubuntu

- **Environment Installation**: Hyprland desktop environment setup
- **Package Management**: APT + Snap + Flatpak
- **Hyprland**: Built from source with all dependencies
- **Hardware Support**: Basic NVIDIA driver installation

## Hardware Support

### NVIDIA GPUs

- Automatic driver installation (nvidia-dkms on Arch, nvidia-driver-535 on Ubuntu)
- Wayland compatibility configuration
- Environment variable setup
- Kernel module configuration

### ASUS TUF Laptops

- MUX switch support via optimus-manager
- ASUS utilities (asusctl, supergfxctl)
- Power management optimization
- Keyboard backlight configuration
- Thermal management

## Safety Features

### Dry-Run Mode

Preview all operations without making changes:
```bash
./install.sh --dry-run
```

### Backup System

Automatic backup creation before making changes:
- Configuration files backed up with timestamps
- Rollback capability for critical failures
- Selective backup and restore

### VM Testing

Safe testing in virtual machines:
```bash
./install.sh --test
```
- Skips hardware-specific configurations
- VM-optimized package selection
- Guest agent installation

## Configuration Management

The framework integrates with your existing dotfiles repository:

- Preserves existing dotfiles structure
- Creates symlinks to maintain consistency
- Handles configuration conflicts gracefully
- Supports backup and restore operations

## Service Management

**No Auto-Start Policy**: Services are installed but not automatically enabled.

To manage services:
```bash
# List service status
systemctl list-unit-files --type=service

# Enable a service
sudo systemctl enable <service-name>

# Start a service
sudo systemctl start <service-name>
```

Available services include:
- NetworkManager (network management)
- bluetooth (Bluetooth support)
- docker (container service)
- optimus-manager (GPU switching)

## Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure you're not running as root
2. **Network Issues**: Check internet connectivity
3. **Package Conflicts**: Use `--dry-run` to preview changes
4. **Hardware Detection**: Check logs for hardware-specific errors

### Log Files

Logs are saved to `/tmp/modular-install-YYYYMMDD-HHMMSS.log`

### Getting Help

1. Check the log files for detailed error information
2. Run with `--verbose` for additional debug output
3. Use `--dry-run` to preview operations
4. Consult the TESTING.md file for testing procedures

## Development

### Project Structure

```
├── install.sh              # Main entry point
├── core/                   # Core utilities
├── distros/               # Distribution-specific modules
├── components/            # Component installation modules
├── configs/               # Configuration management
├── data/                  # Package lists and dependencies
└── tests/                 # Testing utilities
```

### Contributing

1. Follow the modular architecture
2. Add comprehensive logging
3. Support both Arch and Ubuntu
4. Include dry-run mode support
5. Test in VM environments

## License

[License information to be added]

## Acknowledgments

- Hyprland community for the amazing window manager
- Arch Linux and Ubuntu communities
- All the open-source projects that make this possible