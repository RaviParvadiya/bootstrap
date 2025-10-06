# Modular Install Framework

A comprehensive, modular installation framework for automating Linux development environment setup. Supports both Arch Linux (complete installation) and Ubuntu (Hyprland environment installation) with consistent configuration management and hardware-specific optimizations.

## Features

- **Multi-Distribution Support**: Arch Linux and Ubuntu
- **Modular Architecture**: Install only what you need
- **Interactive Component Selection**: Choose components through an intuitive menu
- **Hardware Detection**: Automatic NVIDIA GPU and ASUS TUF laptop support
- **Safety Features**: backups, and VM testing
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

# Install specific components
./install.sh --components terminal,shell,editor

# Install all available components
./install.sh --all


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
- **Package Management**: Pacman + AUR (yay)
- **Repository Setup**: Multilib, Chaotic-AUR
- **Hardware Support**: Full NVIDIA and ASUS TUF support

### Ubuntu

- **Environment Installation**: Hyprland desktop environment setup
- **Package Management**: APT
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

### Backup System

Automatic backup creation before making changes:
- Configuration files backed up with timestamps
- Rollback capability for critical failures
- Selective backup and restore

### VM Testing

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

## Usage Examples

### Example 1: First-Time Arch Linux Setup

```bash
# 1. Start with a dry-run to see what will be installed


# 2. Install everything at once (all components)
./install.sh --all            # Install everything

# 3. Or run the interactive installation for selective components
./install.sh

# 3. Select components in the menu:
#    - terminal (Kitty recommended)
#    - shell (Zsh + Starship)
#    - editor (Neovim)
#    - wm (Hyprland + Waybar + Wofi)
#    - hardware (if NVIDIA GPU detected)

# 4. After installation, manually enable desired services
sudo systemctl enable NetworkManager
sudo systemctl enable bluetooth
```

### Example 2: Ubuntu Hyprland Environment

```bash
# 1. Preview the Hyprland installation


# 2. Install Hyprland environment (builds from source)
./install.sh --components wm

# 3. Install additional development tools
./install.sh --components dev-tools

# 4. Configure display manager for Hyprland session
# Follow the post-installation instructions
```

### Example 3: Selective Component Installation

```bash
# Install only terminal and shell components
./install.sh --components terminal,shell

# Add editor later
./install.sh --components editor

# Check what's installed
./install.sh validate
```

### Example 4: VM Testing Setup

```bash
# 1. In your VM, clone the repository
git clone <repository-url>
cd modular-install-framework

# 2. Run actual installation

# 4. Validate the installation
./install.sh validate
```

### Example 5: Complete System Setup with --all

```bash
# 1. Preview what will be installed with --all


# 2. Install everything at once
./install.sh --all

# 3. Or install everything


# 4. Validate the complete installation
./install.sh validate
```

### Example 6: Development Environment Restoration

```bash
# 1. Restore from existing backup
./install.sh restore --backup-path ~/backups/config-20240101

# 2. Or create fresh installation with specific components
./install.sh --components terminal,shell,editor,dev-tools

# 3. Validate everything is working
./install.sh validate
```

## Advanced Configuration

### Custom Component Selection

Create a custom component configuration file:

```bash
# Create ~/.config/modular-install/components.conf
cat > ~/.config/modular-install/components.conf << EOF
# Custom component selection
terminal=kitty
shell=zsh
editor=neovim
wm=hyprland
dev-tools=git,docker
hardware=nvidia
EOF

# Use custom configuration
./install.sh --config ~/.config/modular-install/components.conf
```

### Environment Variables

Customize behavior with environment variables:

```bash
./install.sh

# Use specific AUR helper
export AUR_HELPER=yay
./install.sh

# Skip hardware detection
export SKIP_HARDWARE=true
./install.sh

# Use custom dotfiles repository
export DOTFILES_REPO="https://github.com/yourusername/dotfiles"
./install.sh
```

### Post-Installation Tasks

After installation, you may want to:

```bash
# 1. Configure Git (if not already done)
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"

# 2. Set up SSH keys
ssh-keygen -t ed25519 -C "your.email@example.com"

# 3. Configure shell (Zsh will be default after reboot)
# Or switch immediately:
chsh -s /usr/bin/zsh

# 4. Enable desired services
sudo systemctl enable --now NetworkManager
sudo systemctl enable --now bluetooth

# 5. For NVIDIA users, configure optimus-manager
sudo systemctl enable optimus-manager
# Reboot required for GPU switching
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Permission Denied Errors

**Problem**: Script fails with permission denied errors
**Solution**:
```bash
# Ensure you're not running as root
whoami  # Should NOT return 'root'

# If you accidentally ran as root, fix ownership
sudo chown -R $USER:$USER ~/.config
sudo chown -R $USER:$USER ~/.local
```

#### 2. Network/Download Issues

**Problem**: Package downloads fail or timeout
**Solutions**:
```bash
# Check internet connectivity
ping -c 3 google.com

# For Arch: Update mirrors
sudo reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist

# For Ubuntu: Change to local mirror
sudo sed -i 's/archive.ubuntu.com/us.archive.ubuntu.com/g' /etc/apt/sources.list
sudo apt update
```

#### 3. Package Conflicts

**Problem**: Package installation fails due to conflicts
**Solutions**:
```bash
# Preview what will be installed


# For Arch: Clear package cache and update
sudo pacman -Scc
sudo pacman -Syu

# For Ubuntu: Fix broken packages
sudo apt --fix-broken install
sudo apt autoremove
```

#### 4. Hardware Detection Issues

**Problem**: NVIDIA GPU not detected or configured incorrectly
**Solutions**:
```bash
# Check if NVIDIA GPU is present
lspci | grep -i nvidia

# Check current driver
nvidia-smi  # Should show GPU info

# For Arch: Reinstall NVIDIA drivers
sudo pacman -S nvidia-dkms nvidia-utils

# For Ubuntu: Use driver manager
ubuntu-drivers devices
sudo ubuntu-drivers autoinstall
```

#### 5. Hyprland Won't Start

**Problem**: Hyprland fails to start or crashes
**Solutions**:
```bash
# Check Hyprland logs
journalctl -u hyprland --user -f

# Verify Wayland support
echo $XDG_SESSION_TYPE  # Should be 'wayland'

# Check graphics drivers
glxinfo | grep "OpenGL renderer"

# For NVIDIA: Ensure proper environment variables
cat ~/.config/hypr/hyprland.conf | grep env
```

#### 6. Configuration Files Not Applied

**Problem**: Dotfiles/configs not properly linked
**Solutions**:
```bash
# Check symlinks
ls -la ~/.config/

# Manually create missing symlinks
ln -sf ~/dotfiles/kitty/.config/kitty ~/.config/kitty

# Restore from backup if needed
./install.sh restore
```

#### 7. Services Not Working

**Problem**: Installed services don't start
**Solutions**:
```bash
# Check service status
systemctl status NetworkManager
systemctl status bluetooth

# Enable and start services manually
sudo systemctl enable --now NetworkManager
sudo systemctl enable --now bluetooth

# Check for conflicts
systemctl list-units --failed
```

#### 8. VM-Specific Issues

**Problem**: Installation fails in virtual machine
**Solutions**:
```bash
# Install VM guest additions first
# VirtualBox:
sudo pacman -S virtualbox-guest-utils  # Arch
sudo apt install virtualbox-guest-utils  # Ubuntu

# VMware:
sudo pacman -S open-vm-tools  # Arch
sudo apt install open-vm-tools  # Ubuntu
```

### Debug Information Collection

When reporting issues, collect this information:

```bash
# System information
uname -a
cat /etc/os-release

# Hardware information
lscpu
lspci | grep -E "(VGA|3D)"
free -h
df -h

# Installation logs
ls -la /tmp/modular-install-*.log
tail -50 /tmp/modular-install-*.log

# Package information
# Arch:
pacman -Q | wc -l
pacman -Qm  # AUR packages

# Ubuntu:
dpkg -l | wc -l
apt list --installed | wc -l
```

### Log Files and Debugging

#### Log File Locations

- **Installation logs**: `/tmp/modular-install-YYYYMMDD-HHMMSS.log`
- **Component logs**: `/tmp/component-<name>-YYYYMMDD-HHMMSS.log`

#### Enabling Debug Mode

```bash
# Debug specific component

# Debug specific component
DEBUG=true ./install.sh --components terminal

# Monitor logs in real-time
tail -f /tmp/modular-install-*.log
```

### Getting Help

1. **Check the logs**: Always start with the log files for detailed error information
2. **Check logs**: Review log files for detailed error information
4. **Use validate command**: Use `./install.sh validate` to check installation status
5. **Check component status**: Use `./install.sh validate` to check installation status
6. **Community support**: Check the project's issue tracker or community forums

### Recovery Procedures

#### Complete System Recovery

```bash
# 1. Boot from live USB/CD
# 2. Mount your system
sudo mount /dev/sdXY /mnt
sudo arch-chroot /mnt  # Arch
# or
sudo chroot /mnt  # Ubuntu

# 3. Restore from backup
cp -r /path/to/backup/.config/* ~/.config/
cp -r /path/to/backup/.local/* ~/.local/

# 4. Fix bootloader if needed
grub-mkconfig -o /boot/grub/grub.cfg
```

#### Partial Recovery

```bash
# Restore specific configurations
./install.sh restore --component terminal
./install.sh restore --component shell

# Reset to defaults
rm -rf ~/.config/hypr
./install.sh --components wm --force
```

## Documentation

### User Documentation

- **[README.md](README.md)** - Main installation and usage guide

- **[docs/USAGE_EXAMPLES.md](docs/USAGE_EXAMPLES.md)** - Comprehensive usage examples and troubleshooting

### Developer Documentation

- **[docs/FUNCTION_REFERENCE.md](docs/FUNCTION_REFERENCE.md)** - Complete function reference with parameters and examples
- **[.kiro/specs/modular-install-framework/design.md](.kiro/specs/modular-install-framework/design.md)** - Architecture and design documentation
- **[.kiro/specs/modular-install-framework/requirements.md](.kiro/specs/modular-install-framework/requirements.md)** - Requirements specification

## Development

### Project Structure

```
├── install.sh              # Main entry point
├── README.md               # Main documentation
├── core/                   # Core utilities
│   ├── common.sh           # Shared functions & system validation
│   ├── logger.sh           # Logging system
│   └── menu.sh             # Interactive menus
├── distros/               # Distribution-specific modules
│   ├── arch/              # Arch Linux support
│   └── ubuntu/            # Ubuntu support
├── components/            # Component installation modules
│   ├── terminal/          # Terminal emulators
│   ├── shell/             # Shell configuration
│   ├── editor/            # Text editors
│   ├── wm/                # Window managers
│   └── dev-tools/         # Development tools
├── configs/               # Configuration management
├── data/                  # Package lists and dependencies
├── tests/                 # Testing utilities
└── docs/                  # Additional documentation
    ├── USAGE_EXAMPLES.md  # Usage examples and troubleshooting
    └── FUNCTION_REFERENCE.md  # Developer function reference
```

### Contributing

1. **Follow the modular architecture** - Each component should be self-contained
2. **Add comprehensive logging** - Use the logging functions from `core/logger.sh`
3. **Support both Arch and Ubuntu** - Test on both distributions
4. **Include dry-run mode support** - All functions should respect `$DRY_RUN`
5. **Test in safe environments** - Use validation commands for testing
6. **Document functions** - Follow the patterns in `docs/FUNCTION_REFERENCE.md`
7. **Add usage examples** - Include examples in function documentation

## License

[License information to be added]

## Acknowledgments

- Hyprland community for the amazing window manager
- Arch Linux and Ubuntu communities
- All the open-source projects that make this possible