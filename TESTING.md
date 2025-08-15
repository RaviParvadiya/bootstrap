# Testing Guide

This document provides comprehensive testing procedures and safety guidelines for the Modular Install Framework.

## Testing Philosophy

The framework follows a "safety-first" approach with multiple testing modes to ensure reliable operation without breaking existing systems.

## Testing Modes

### 1. Dry-Run Mode

Preview all operations without making any changes to the system.

```bash
# Basic dry-run
./install.sh --dry-run

# Dry-run with specific components
./install.sh --dry-run --components terminal,shell

# Verbose dry-run for detailed output
./install.sh --dry-run --verbose
```

**What it does:**
- Shows all packages that would be installed
- Displays configuration files that would be created/modified
- Lists services that would be configured
- Provides installation time estimates

**What it doesn't do:**
- Install any packages
- Modify any files
- Change system configuration
- Enable any services

### 2. VM Testing Mode

Safe testing in virtual machine environments.

```bash
# VM-safe installation
./install.sh --test

# VM mode with dry-run
./install.sh --test --dry-run
```

**VM Mode Features:**
- Automatically detects VM environments
- Skips hardware-specific configurations
- Installs VM guest agents
- Optimizes for virtual hardware
- Avoids GPU-specific setups

### 3. Component Testing

Test individual components in isolation.

```bash
# Test only terminal components
./install.sh --components terminal --dry-run

# Test dependency resolution
./install.sh --components wm --dry-run  # Will include terminal and shell
```

## Pre-Testing Checklist

Before running any tests, ensure:

- [ ] System is backed up (important data)
- [ ] Running on a non-production system
- [ ] Internet connection is stable
- [ ] Sufficient disk space (5GB+ recommended)
- [ ] User has sudo privileges
- [ ] Not running as root user

## VM Testing Setup

### Recommended VM Configuration

**Minimum Requirements:**
- 4GB RAM
- 20GB disk space
- 2 CPU cores
- Network connectivity

**Recommended VM Software:**
- VirtualBox
- VMware
- QEMU/KVM
- Hyper-V

### VM Setup Steps

1. **Create VM with target OS:**
   ```bash
   # For Arch Linux
   # Download Arch ISO and install base system
   
   # For Ubuntu
   # Download Ubuntu 20.04+ ISO and install
   ```

2. **Install VM guest additions:**
   ```bash
   # VirtualBox
   sudo pacman -S virtualbox-guest-utils  # Arch
   sudo apt install virtualbox-guest-utils  # Ubuntu
   
   # VMware
   sudo pacman -S open-vm-tools  # Arch
   sudo apt install open-vm-tools  # Ubuntu
   ```

3. **Take VM snapshot before testing:**
   - Create snapshot named "pre-install"
   - This allows easy rollback after testing

4. **Clone framework and test:**
   ```bash
   git clone <repository-url>
   cd modular-install-framework
   ./install.sh --test --dry-run
   ```

## Testing Procedures

### 1. Basic Functionality Test

```bash
# Test script execution
./install.sh --help

# Test distribution detection
./install.sh --dry-run | grep "Detected distribution"

# Test component listing
./install.sh list
```

### 2. Dry-Run Testing

```bash
# Full dry-run test
./install.sh --dry-run --verbose > dry-run-output.log 2>&1

# Verify no changes were made
# Check that no packages were installed
# Verify no configuration files were modified
```

### 3. Component Dependency Testing

```bash
# Test dependency resolution
./install.sh --components wm --dry-run

# Should show:
# - terminal (dependency)
# - shell (dependency)  
# - wm (selected)
```

### 4. Hardware Detection Testing

```bash
# Test NVIDIA detection
lspci | grep -i nvidia
./install.sh --components hardware --dry-run

# Test VM detection
./install.sh --test --dry-run
```

### 5. Error Handling Testing

```bash
# Test with no internet (disconnect network)
./install.sh --dry-run

# Test with insufficient permissions
# (This should fail gracefully)

# Test with unsupported distribution
# (Mock /etc/os-release for testing)
```

## Validation Procedures

### Post-Installation Validation

After running the installation (in VM), validate:

1. **Package Installation:**
   ```bash
   # Arch Linux
   pacman -Q | grep -E "(git|curl|zsh|kitty)"
   
   # Ubuntu
   dpkg -l | grep -E "(git|curl|zsh|kitty)"
   ```

2. **Configuration Files:**
   ```bash
   # Check dotfiles symlinks
   ls -la ~/.config/
   
   # Verify configuration integrity
   # Test application startup
   ```

3. **Service Status:**
   ```bash
   # Verify no services auto-started
   systemctl list-units --state=running --user
   systemctl list-units --state=running --system
   ```

4. **Hardware Configuration:**
   ```bash
   # NVIDIA (if applicable)
   nvidia-smi
   
   # Check kernel modules
   lsmod | grep nvidia
   ```

## Automated Testing

### Test Scripts

The framework includes automated test scripts:

```bash
# Run all tests
./tests/run-all-tests.sh

# Individual test categories
./tests/dry-run.sh
./tests/vm-test.sh
./tests/validate.sh
```

### Continuous Integration

For development, set up CI/CD with:

1. **VM-based testing** on multiple distributions
2. **Dry-run validation** for all components
3. **Dependency resolution testing**
4. **Hardware detection mocking**

## Safety Guidelines

### Before Testing

1. **Never test on production systems**
2. **Always start with dry-run mode**
3. **Use VM environments for initial testing**
4. **Create system backups**
5. **Document test procedures**

### During Testing

1. **Monitor system resources**
2. **Check logs for errors**
3. **Validate each step**
4. **Stop on critical errors**
5. **Document any issues**

### After Testing

1. **Validate installation completeness**
2. **Test application functionality**
3. **Check system stability**
4. **Document results**
5. **Clean up test artifacts**

## Rollback Procedures

### VM Rollback

```bash
# Restore VM snapshot
# Use VM software to restore "pre-install" snapshot
```

### System Rollback

```bash
# Restore from backup (if backup was created)
./install.sh restore --backup-path /path/to/backup

# Manual rollback steps
# Remove installed packages
# Restore configuration files
# Reset services
```

## Common Test Scenarios

### Scenario 1: Fresh Arch Installation

```bash
# Test complete Arch setup
./install.sh --dry-run
./install.sh --test  # In VM
```

### Scenario 2: Ubuntu Hyprland Setup

```bash
# Test Ubuntu Hyprland installation
./install.sh --components wm --dry-run
./install.sh --components wm --test  # In VM
```

### Scenario 3: Selective Component Installation

```bash
# Test minimal installation
./install.sh --components terminal,shell --dry-run
```

### Scenario 4: Hardware-Specific Testing

```bash
# Test NVIDIA configuration
./install.sh --components hardware --dry-run

# Test ASUS TUF configuration
./install.sh --components hardware --dry-run
```

## Troubleshooting Test Issues

### Common Test Problems

1. **Network timeouts**: Use local mirrors or cached packages
2. **Permission errors**: Verify sudo configuration
3. **Disk space**: Ensure adequate free space
4. **VM performance**: Allocate sufficient resources

### Debug Mode

```bash
# Enable maximum verbosity
./install.sh --verbose --dry-run

# Check log files
tail -f /tmp/modular-install-*.log
```

## Test Reporting

### Test Report Template

```
Test Date: YYYY-MM-DD
Test Environment: [VM/Physical]
Distribution: [Arch/Ubuntu]
Components Tested: [list]
Test Mode: [dry-run/vm/full]

Results:
- [ ] Script execution successful
- [ ] Component selection working
- [ ] Dependency resolution correct
- [ ] Hardware detection accurate
- [ ] No unintended changes made

Issues Found:
[List any issues]

Recommendations:
[Any recommendations]
```

## Best Practices

1. **Test incrementally** - Start with dry-run, then VM, then limited real testing
2. **Document everything** - Keep detailed test logs
3. **Use version control** - Track changes to test procedures
4. **Automate where possible** - Create reusable test scripts
5. **Test edge cases** - Network failures, permission issues, etc.
6. **Validate thoroughly** - Don't just check if it runs, check if it works correctly

## Contributing to Testing

When contributing to the framework:

1. Add tests for new features
2. Update test documentation
3. Ensure VM compatibility
4. Test on multiple distributions
5. Include dry-run support in all new features