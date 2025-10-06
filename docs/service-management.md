# Service Management and System Integration

This document describes the service management and system integration functionality implemented in the modular install framework.

## Overview

The service management system provides a unified approach to handling systemd services across different Linux distributions while adhering to the **no-auto-start policy**. This means services are configured and registered but never automatically enabled or started without explicit user consent.

## Architecture

### Core Components

1. **Core Service Manager** (`core/service-manager.sh`)
   - Universal service management functions
   - Service registry management
   - System integration configuration
   - Cross-distribution compatibility

2. **Distribution-Specific Modules**
   - `distros/arch/services.sh` - Arch Linux service management
   - `distros/ubuntu/services.sh` - Ubuntu service management

3. **Service Registry**
   - Temporary file-based registry tracking all configured services
   - Stores service metadata, status, and auto-start policies

## Key Principles

### No-Auto-Start Policy

**Requirement 3.1**: Services are configured but never automatically enabled or started.

- Services are registered with metadata but remain disabled
- Users must manually enable services they want to use
- Clear instructions provided for manual service management
- Respects the principle of user control over system services

### Selective Service Control

**Requirement 3.2**: Users have full control over which services to enable.

- Interactive service management (when requested)
- Dependency checking and warnings
- Service status reporting
- Component-based service grouping

### Service Status Reporting

**Requirement 3.3**: Comprehensive service status reporting and management utilities.

- Real-time service status checking
- Service registry with metadata
- Component-based service filtering
- System integration status reporting

### System Integration

**Requirement 3.4**: Desktop environment and system integration setup.

- Wayland/X11 session configuration
- Desktop portal setup
- Environment variable configuration
- User group management

## Service Registry Format

Services are registered in a structured format:

```
service_name|description|priority|component|distro|status|auto_start_policy
```

### Fields

- **service_name**: Systemd service name (without .service suffix)
- **description**: Human-readable service description
- **priority**: `required`, `recommended`, or `optional`
- **component**: Component that registered the service
- **distro**: Distribution where service was registered
- **status**: Current service status (`available`, `enabled`, `disabled`, `not-available`)
- **auto_start_policy**: Service start policy (`never`, `manual`, `conditional`)

### Auto-Start Policies

- **never**: Service should never be auto-started (e.g., SSH server, Docker)
- **manual**: Service requires explicit user action to start
- **conditional**: Service may be started if certain conditions are met (e.g., NetworkManager on Ubuntu)

## System Integration Registry

System integrations are tracked separately:

```
integration_type|name|description|status|component
```

### Integration Types

- **desktop_session**: Desktop environment session files
- **display_manager**: Display manager configurations
- **environment_var**: Environment variable configurations
- **user_group**: User group memberships
- **desktop_portal**: XDG desktop portal configurations

## Usage Examples

### Basic Service Registration

```bash
# Register a service with the framework
register_service "docker" "Docker container runtime" "optional" "docker" "never"
```

### Service Status Checking

```bash
# Check if a service is available
if is_service_available "docker"; then
    echo "Docker service is available"
fi

# Get comprehensive service status
status=$(get_service_status "docker")
echo "Docker status: $status"  # Output: available,disabled,stopped
```

### Manual Service Management

```bash
# Enable a service with user confirmation
enable_service "docker" false

# Disable a service
disable_service "docker" true  # true = also stop the service
```

### System Integration

```bash
# Configure desktop environment integration
configure_desktop_integration "hyprland" "wm"

# Add user to system groups
add_user_to_groups "video" "audio" "input" "render"

# Register system integration
register_system_integration "user_group" "docker" "User added to docker group" "docker"
```

### Service Status Display

```bash
# Show all registered services
show_service_status
```

## Distribution-Specific Implementation

### Arch Linux Services

Common services configured on Arch Linux:

- **Wayland Services**: xdg-desktop-portal, xdg-desktop-portal-hyprland
- **System Services**: systemd-timesyncd, NetworkManager
- **Optional Services**: docker, bluetooth, cups, sshd
- **Audio Services**: pipewire, pipewire-pulse, wireplumber
- **Security Services**: ufw, firewalld

### Ubuntu Services

Common services configured on Ubuntu:

- **Wayland Services**: xdg-desktop-portal, xdg-desktop-portal-hyprland
- **System Services**: systemd-timesyncd, NetworkManager (usually pre-enabled)
- **Optional Services**: docker, bluetooth, cups, ssh
- **Audio Services**: pipewire, pulseaudio
- **Security Services**: ufw (Ubuntu's default firewall)

## Service Management Commands

### Enable Services

```bash
# Enable and start a service
sudo systemctl enable <service_name>
sudo systemctl start <service_name>

# Enable without starting
sudo systemctl enable <service_name>
```

### Disable Services

```bash
# Disable and stop a service
sudo systemctl disable <service_name>
sudo systemctl stop <service_name>

# Disable without stopping
sudo systemctl disable <service_name>
```

### Check Service Status

```bash
# Detailed service status
systemctl status <service_name>

# Check if service is enabled
systemctl is-enabled <service_name>

# Check if service is running
systemctl is-active <service_name>
```

## Component-Specific Services

### Hyprland/Wayland Components

Services typically needed for Wayland desktop environments:

- `xdg-desktop-portal` - Desktop integration portal
- `xdg-desktop-portal-hyprland` - Hyprland-specific portal
- `xdg-desktop-portal-gtk` - GTK portal for file dialogs

User groups: `video`, `input`, `render`

### Docker Components

Services for container runtime:

- `docker` - Docker daemon
- `containerd` - Container runtime

User groups: `docker`

### Audio Components

Services for audio functionality:

- `pipewire` - Modern audio server
- `pipewire-pulse` - PulseAudio compatibility
- `wireplumber` - PipeWire session manager

User groups: `audio`

### Bluetooth Components

Services for Bluetooth connectivity:

- `bluetooth` - Bluetooth daemon

User groups: `bluetooth` (if exists)

### Printing Components

Services for printing functionality:

- `cups` - Common Unix Printing System
- `cups-browsed` - Printer discovery

User groups: `lp` (Arch), `lpadmin` (Ubuntu)

## Security Considerations

### SSH Configuration

When SSH service is configured, security settings are automatically applied:

- Root login disabled (`PermitRootLogin no`)
- Empty passwords disabled (`PermitEmptyPasswords no`)
- Password authentication configured appropriately per distribution

### Firewall Services

Firewall services are registered but never auto-enabled:

- Users must explicitly enable firewall protection
- Multiple firewall options supported (ufw, firewalld, iptables)
- Clear instructions provided for firewall setup

## Testing

### Service Management Tests

Run the service management test suite:

```bash
./tests/simple-service-test.sh
```

This test verifies:

- Service registry initialization
- Service registration functionality
- System integration registration
- Service status checking
- Cross-distribution compatibility

### Manual Testing

Test service management manually:

```bash
# Source the service manager
source core/service-manager.sh

# Initialize and test
register_service "test-service" "Test service" "optional" "test" "never"
show_service_status
```

## Troubleshooting

### Common Issues

1. **Service Not Found**
   - Verify service is installed: `systemctl list-unit-files | grep <service>`
   - Check service name spelling (without .service suffix)

2. **Permission Denied**
   - Ensure user has sudo privileges
   - Some operations require root access

3. **Service Won't Start**
   - Check service dependencies: `systemctl list-dependencies <service>`
   - Review service logs: `journalctl -u <service>`

### Debug Mode

Enable debug logging for troubleshooting:

```bash
# Check service status and logs
systemctl --user status service-name
journalctl --user -u service-name
```

## Integration with Main Installation

The service management system is integrated into the main installation process:

### Arch Linux Integration

```bash
# In distros/arch/arch-main.sh
arch_configure_services "${selected_components[@]}"
```

### Ubuntu Integration

```bash
# In distros/ubuntu/ubuntu-main.sh
ubuntu_configure_services "${selected_components[@]}"
```

Both integrations:

1. Configure services for installed components
2. Register services in the global registry
3. Set up system integrations (desktop sessions, user groups)
4. Display service summary with management instructions
5. Respect the no-auto-start policy

## Future Enhancements

Potential improvements to the service management system:

1. **Interactive Service Manager**: TUI for service management
2. **Service Dependencies**: Automatic dependency resolution
3. **Service Profiles**: Predefined service configurations
4. **Service Monitoring**: Health checking and alerting
5. **Configuration Templates**: Service-specific configuration management

## Conclusion

The service management system provides a robust, distribution-agnostic approach to handling system services while maintaining user control and system security. By adhering to the no-auto-start policy and providing comprehensive service tracking, users can make informed decisions about which services to enable on their systems.