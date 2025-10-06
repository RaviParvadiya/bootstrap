# Usage Examples and Troubleshooting Guide

This document provides comprehensive usage examples, common scenarios, and troubleshooting solutions for the Modular Install Framework.

## Table of Contents

1. [Basic Usage Examples](#basic-usage-examples)
2. [Advanced Configuration](#advanced-configuration)
3. [Distribution-Specific Examples](#distribution-specific-examples)
4. [Component-Specific Examples](#component-specific-examples)
5. [Testing and Safety Examples](#testing-and-safety-examples)
6. [Troubleshooting Guide](#troubleshooting-guide)
7. [Recovery Procedures](#recovery-procedures)

## Basic Usage Examples

### Example 1: Complete Fresh Installation (Arch Linux)

```bash
# Step 1: Clone the repository
git clone <repository-url>
cd modular-install-framework

# Step 2: Preview what will be installed
./install.sh --dry-run

# Step 3: Run interactive installation
./install.sh

# Step 4: Select components in the interactive menu
# Recommended selections for complete setup:
# - [x] terminal (Kitty)
# - [x] shell (Zsh + Starship)
# - [x] editor (Neovim)
# - [x] wm (Hyprland + Waybar + Wofi)
# - [x] dev-tools (Git, Docker, Languages)
# - [x] hardware (if NVIDIA GPU detected)

# Step 5: Post-installation tasks
# Enable services manually (framework doesn't auto-enable)
sudo systemctl enable NetworkManager
sudo systemctl enable bluetooth

# Switch to Zsh shell
chsh -s /usr/bin/zsh

# Reboot to apply all changes
sudo reboot
```

### Example 2: Ubuntu Hyprland Environment Setup

```bash
# Step 1: Ensure system is updated
sudo apt update && sudo apt upgrade -y

# Step 2: Clone and prepare framework
git clone <repository-url>
cd modular-install-framework
chmod +x install.sh

# Step 3: Preview Hyprland installation (builds from source)
./install.sh --components wm --dry-run

# Step 4: Install Hyprland environment
./install.sh --components wm

# Step 5: Install additional components
./install.sh --components terminal,shell,editor

# Step 6: Configure display manager
# Add Hyprland session to your display manager
sudo cp /usr/share/wayland-sessions/hyprland.desktop /usr/share/xsessions/

# Step 7: Log out and select Hyprland session
```

### Example 3: Minimal Development Setup

```bash
# Install only essential development tools
./install.sh --components terminal,shell,editor,dev-tools

# This installs:
# - Kitty terminal
# - Zsh with Starship prompt
# - Neovim with configuration
# - Git, Docker, and language tools
```

## Advanced Configuration

### Custom Component Selection File

Create a configuration file to automate component selection:

```bash
# Create configuration directory
mkdir -p ~/.config/modular-install

# Create component selection file
cat > ~/.config/modular-install/components.conf << EOF
# Modular Install Framework Configuration
# Lines starting with # are comments

# Terminal configuration
terminal=kitty
terminal_theme=catppuccin-mocha

# Shell configuration
shell=zsh
shell_plugins=autosuggestions,syntax-highlighting,history-substring-search
prompt=starship

# Editor configuration
editor=neovim
editor_plugins=lsp,treesitter,telescope

# Window manager (only for supported distributions)
wm=hyprland
wm_bar=waybar
wm_launcher=wofi
wm_notifications=swaync

# Development tools
dev_tools=git,docker,nodejs,python,rust

# Hardware support
hardware=nvidia  # or amd, intel
hardware_laptop=asus-tuf  # or generic

# Additional options
backup_existing=true
create_symlinks=true
install_fonts=true
EOF

# Use the configuration file
./install.sh --config ~/.config/modular-install/components.conf
```

### Environment Variables Configuration

```bash
# Create environment configuration
cat > ~/.config/modular-install/environment << EOF
# Framework behavior

export BACKUP_CONFIGS=true

# Package manager preferences
export AUR_HELPER=yay
export PARALLEL_DOWNLOADS=5

# Hardware detection
export FORCE_NVIDIA=false
export SKIP_HARDWARE_DETECTION=false

# Dotfiles repository
export DOTFILES_REPO="https://github.com/yourusername/dotfiles"
export DOTFILES_BRANCH="main"

# Installation paths
export CONFIG_BACKUP_DIR="$HOME/.config/install-backups"
export LOG_LEVEL=INFO  # DEBUG, INFO, WARN, ERROR
EOF

# Source environment and run installation
source ~/.config/modular-install/environment
./install.sh
```

## Distribution-Specific Examples

### Arch Linux Examples

#### Complete Gaming Setup

```bash
# Install complete gaming environment
./install.sh --components wm,terminal,shell,dev-tools,hardware

# Post-installation gaming setup
# Enable multilib repository (done automatically)
# Install gaming packages
sudo pacman -S steam lutris wine-staging winetricks

# Configure NVIDIA for gaming (if applicable)
sudo systemctl enable optimus-manager
```

#### Minimal Server Setup

```bash
# Server-focused installation (no GUI)
./install.sh --components shell,editor,dev-tools

# This installs:
# - Zsh with server-optimized configuration
# - Neovim for editing
# - Git, Docker, and development tools
# - No window manager or GUI components
```

### Ubuntu Examples

#### Development Workstation

```bash
# Complete development environment
./install.sh --components wm,terminal,shell,editor,dev-tools

# Additional Ubuntu-specific setup
# Install additional applications via APT
sudo apt install code firefox
```

#### Hyprland-Only Installation

```bash
# Install only Hyprland environment
./install.sh --components wm

# Manual configuration for specific needs
# Configure GDM for Wayland
sudo sed -i 's/#WaylandEnable=false/WaylandEnable=true/' /etc/gdm3/custom.conf

# Add user to video group for hardware acceleration
sudo usermod -a -G video $USER
```

## Component-Specific Examples

### Terminal Configuration

#### Kitty Terminal Setup

```bash
# Install only Kitty terminal
./install.sh --components terminal

# Customize Kitty configuration
# Edit ~/.config/kitty/kitty.conf
cat >> ~/.config/kitty/kitty.conf << EOF
# Custom settings
font_size 12.0
background_opacity 0.9
window_padding_width 10
EOF

# Test Kitty configuration
kitty --config ~/.config/kitty/kitty.conf
```

#### Alacritty Alternative

```bash
# If you prefer Alacritty over Kitty
# Modify the component selection
export TERMINAL_PREFERENCE=alacritty
./install.sh --components terminal
```

### Shell Configuration

#### Zsh with Custom Plugins

```bash
# Install shell components
./install.sh --components shell

# Add custom Zsh plugins
git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting

# Update .zshrc to include new plugins
sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' ~/.zshrc
```

### Editor Configuration

#### Neovim with Language Servers

```bash
# Install editor components
./install.sh --components editor

# Install additional language servers
# For Python
pip install python-lsp-server

# For JavaScript/TypeScript
npm install -g typescript-language-server

# For Rust
rustup component add rust-analyzer

# For Go
go install golang.org/x/tools/gopls@latest
```

### Window Manager Configuration

#### Hyprland with Custom Keybindings

```bash
# Install window manager
./install.sh --components wm

# Add custom keybindings to Hyprland
cat >> ~/.config/hypr/hyprland.conf << EOF
# Custom keybindings
bind = SUPER, Return, exec, kitty
bind = SUPER, D, exec, wofi --show drun
bind = SUPER, Q, killactive
bind = SUPER SHIFT, E, exit
bind = SUPER, F, fullscreen
bind = SUPER, Space, togglefloating

# Workspace bindings
bind = SUPER, 1, workspace, 1
bind = SUPER, 2, workspace, 2
bind = SUPER, 3, workspace, 3
bind = SUPER, 4, workspace, 4
bind = SUPER, 5, workspace, 5
EOF
```

## Testing and Safety Examples

### Comprehensive Testing Workflow

```bash
# Step 1: Run installation
./install.sh > install-output.log 2>&1

# Step 2: Review installation results
less test-output.log

# Step 3: Run installation

# Step 4: Run actual installation
./install.sh

# Step 5: Validate installation
./install.sh validate

# Step 6: Install specific components
./install.sh --components terminal
```

### Backup and Recovery Testing

```bash
# Create system backup before installation
./install.sh backup --full

# Run installation with backup enabled
./install.sh --backup

# Test recovery process
./install.sh restore --backup-path ~/.config/install-backups/20240101_120000

# Validate recovery
./install.sh validate
```

### Component Isolation Testing

```bash
# Test each component individually
for component in terminal shell editor wm dev-tools; do
    echo "Installing component: $component"
    ./install.sh --components $component
    echo "---"
done

# Test dependency resolution
./install.sh --components wm --dry-run  # Should include terminal and shell
```

## Troubleshooting Guide

### Installation Issues

#### Problem: Permission Denied Errors

```bash
# Symptoms
# - "Permission denied" when creating directories
# - "Operation not permitted" when creating symlinks
# - Script fails with permission errors

# Diagnosis
whoami  # Should NOT be root
ls -la ~/.config  # Check ownership
sudo -l  # Verify sudo access

# Solutions
# Fix ownership if accidentally run as root
sudo chown -R $USER:$USER ~/.config ~/.local

# Ensure not running as root
if [[ $EUID -eq 0 ]]; then
    echo "Do not run as root. Use a regular user with sudo access."
    exit 1
fi

# Grant sudo access if needed
sudo usermod -a -G sudo $USER  # Ubuntu
sudo usermod -a -G wheel $USER  # Arch
```

#### Problem: Network/Download Failures

```bash
# Symptoms
# - Package downloads timeout
# - Repository connection failures
# - "Unable to fetch" errors

# Diagnosis
ping -c 3 8.8.8.8  # Test basic connectivity
curl -I https://archlinux.org  # Test HTTPS connectivity
systemctl status NetworkManager  # Check network service

# Solutions for Arch Linux
# Update mirror list
sudo reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
sudo pacman -Sy

# Clear package cache
sudo pacman -Scc

# Solutions for Ubuntu
# Change to faster mirror
sudo sed -i 's/archive.ubuntu.com/mirror.math.princeton.edu\/pub/' /etc/apt/sources.list
sudo apt update

# Fix broken packages
sudo apt --fix-broken install
```

#### Problem: Package Conflicts

```bash
# Symptoms
# - "Conflicting packages" errors
# - "Package already exists" warnings
# - Installation stops due to conflicts

# Diagnosis
# For Arch
pacman -Qdt  # List orphaned packages
pacman -Qm   # List AUR packages

# For Ubuntu
apt list --installed | grep -i conflict
dpkg --audit

# Solutions
# For Arch - resolve conflicts
sudo pacman -Rns $(pacman -Qtdq)  # Remove orphans
sudo pacman -S --overwrite="*" package-name  # Force overwrite

# For Ubuntu - fix broken dependencies
sudo apt autoremove
sudo apt autoclean
sudo dpkg --configure -a
```

### Hardware-Specific Issues

#### Problem: NVIDIA Driver Issues

```bash
# Symptoms
# - Black screen after installation
# - "No displays found" error
# - Graphics performance issues

# Diagnosis
lspci | grep -i nvidia  # Verify GPU presence
nvidia-smi  # Test driver functionality
dmesg | grep -i nvidia  # Check kernel messages

# Solutions
# Reinstall NVIDIA drivers (Arch)
sudo pacman -Rns nvidia nvidia-utils
sudo pacman -S nvidia-dkms nvidia-utils

# Rebuild initramfs
sudo mkinitcpio -P

# For Ubuntu
sudo ubuntu-drivers devices
sudo ubuntu-drivers autoinstall

# Configure Xorg (if needed)
sudo nvidia-xconfig

# Reboot required
sudo reboot
```

#### Problem: Hyprland Won't Start

```bash
# Symptoms
# - Hyprland crashes on startup
# - Black screen with cursor
# - "Failed to create backend" errors

# Diagnosis
journalctl --user -u hyprland -f  # Check Hyprland logs
echo $XDG_SESSION_TYPE  # Should be "wayland"
glxinfo | grep "OpenGL renderer"  # Check graphics

# Solutions
# Ensure Wayland support
export XDG_SESSION_TYPE=wayland
export GDK_BACKEND=wayland
export QT_QPA_PLATFORM=wayland

# For NVIDIA users
export GBM_BACKEND=nvidia-drm
export __GLX_VENDOR_LIBRARY_NAME=nvidia

# Check Hyprland configuration
hyprland --config ~/.config/hypr/hyprland.conf

# Reset to default configuration
mv ~/.config/hypr ~/.config/hypr.backup
./install.sh --components wm --force
```

### Configuration Issues

#### Problem: Dotfiles Not Applied

```bash
# Symptoms
# - Configuration files not found
# - Symlinks broken or missing
# - Applications using default configs

# Diagnosis
ls -la ~/.config/  # Check symlinks
file ~/.config/kitty/kitty.conf  # Verify symlink target
find ~/dotfiles -name "*.conf" -type f  # Check dotfiles structure

# Solutions
# Recreate symlinks
./install.sh --components terminal --force

# Manual symlink creation
ln -sf ~/dotfiles/kitty/.config/kitty ~/.config/kitty

# Fix broken symlinks
find ~/.config -type l -exec test ! -e {} \; -print | xargs rm
./install.sh restore
```

#### Problem: Services Not Working

```bash
# Symptoms
# - NetworkManager not connecting
# - Bluetooth not working
# - Docker daemon not running

# Diagnosis
systemctl status NetworkManager
systemctl status bluetooth
systemctl status docker

# Solutions
# Enable and start services
sudo systemctl enable --now NetworkManager
sudo systemctl enable --now bluetooth
sudo systemctl enable --now docker

# Add user to groups
sudo usermod -a -G docker $USER
sudo usermod -a -G bluetooth $USER

# Restart services
sudo systemctl restart NetworkManager
```

## Recovery Procedures

### Complete System Recovery

#### Boot Recovery (if system won't boot)

```bash
# Boot from live USB/CD
# Mount system partition
sudo mount /dev/sdXY /mnt

# For Arch Linux
sudo arch-chroot /mnt

# For Ubuntu
sudo chroot /mnt

# Remove problematic packages
pacman -Rns hyprland  # Arch
apt remove hyprland   # Ubuntu

# Restore backup
cp -r /path/to/backup/.config/* ~/.config/

# Fix bootloader
grub-mkconfig -o /boot/grub/grub.cfg
update-grub  # Ubuntu

# Exit chroot and reboot
exit
sudo reboot
```

#### Configuration Recovery

```bash
# Restore from automatic backup
./install.sh restore --latest

# Restore specific component
./install.sh restore --component terminal

# Manual restoration
cp -r ~/.config/install-backups/latest/.config/kitty ~/.config/

# Reset to defaults
rm -rf ~/.config/hypr
./install.sh --components wm --reset
```

### Partial Recovery

#### Reset Single Component

```bash
# Remove component configuration
rm -rf ~/.config/kitty

# Reinstall component
./install.sh --components terminal --force

# Validate installation
./install.sh validate --component terminal
```

#### Service Recovery

```bash
# Reset systemd services
sudo systemctl reset-failed
sudo systemctl daemon-reload

# Restart user services
systemctl --user daemon-reload
systemctl --user restart hyprland
```

### Emergency Procedures

#### Safe Mode Boot

```bash
# Add to kernel parameters in GRUB
# For emergency shell access
systemd.unit=emergency.target

# For rescue mode
systemd.unit=rescue.target

# For multi-user mode (no GUI)
systemd.unit=multi-user.target
```

#### Network Recovery

```bash
# Manual network configuration
sudo ip link set eth0 up
sudo dhcpcd eth0

# Or static IP
sudo ip addr add 192.168.1.100/24 dev eth0
sudo ip route add default via 192.168.1.1
```

This comprehensive guide covers most common scenarios and issues you might encounter. For additional help, consult the main README.md file, or check the project's issue tracker.