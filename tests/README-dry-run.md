# Dry-Run Testing Mode

The dry-run testing mode provides comprehensive preview capabilities for the modular install framework, allowing users to see exactly what operations would be performed without making any actual changes to the system.

## Features

### Core Functionality
- **Operation Preview**: Shows all planned operations without executing them
- **Detailed Logging**: Comprehensive logging of all planned operations with timestamps
- **Categorized Tracking**: Separates operations into packages, configurations, services, and commands
- **Interactive Summaries**: Formatted tables showing planned operations by category
- **Timeline View**: Chronological list of all planned operations

### Integration
- **Framework Integration**: Seamlessly integrates with the main installation framework
- **Function Overrides**: Automatically overrides system functions to track operations instead of executing them
- **Module Compatibility**: Works with all existing component modules without modification
- **Command Line Support**: Full command-line interface for different testing modes

## Usage

### Command Line Options

#### Basic Dry-Run Mode
```bash
# Preview full installation
./install.sh --dry-run install

# Preview specific components
./install.sh --dry-run --components terminal,shell install

# Interactive dry-run mode
./install.sh dry-run
```

#### Direct Dry-Run Script Usage
```bash
# Interactive mode with component selection
./tests/dry-run.sh interactive

# Test specific components
./tests/dry-run.sh test terminal shell

# Test individual component
./tests/dry-run.sh component hyprland

# Full installation test
./tests/dry-run.sh test
```

### Output Examples

#### Package Installation Preview
```
=== PACKAGES TO INSTALL ===
Package                                  Manager         Source
---------------------------------------- --------------- ----------
neovim                                   pacman          official
kitty                                    pacman          official
yay                                      yay             AUR
docker                                   pacman          official
```

#### Configuration Operations Preview
```
=== CONFIGURATION OPERATIONS ===
File/Directory                                     Operation       Details
-------------------------------------------------- --------------- ----------
/home/user/.config/nvim/init.lua                  symlink         dotfiles -> config
/home/user/.config/kitty/kitty.conf               backup          existing config
/home/user/.zshrc                                  create          new configuration
```

#### Service Operations Preview
```
=== SERVICE OPERATIONS ===
Service                        Operation       Details
------------------------------ --------------- ----------
docker                         enable          container runtime
bluetooth                      disable         power saving
NetworkManager                 enable          network management
```

#### Command Execution Preview
```
=== COMMANDS TO EXECUTE ===
  1. Clone dotfiles repository
  2. Install AUR helper (yay)
  3. Configure Git user settings
  4. Set up SSH keys
```

## Implementation Details

### Core Components

#### Tracking System
- **Operation Tracking**: Records all planned operations with metadata
- **Categorization**: Automatically categorizes operations by type
- **Metadata Storage**: Stores additional context for each operation
- **Timeline Management**: Maintains chronological order of operations

#### Function Overrides
The dry-run system overrides key system functions:

```bash
# Package managers
pacman() { track_package_install "$@"; }
apt-get() { track_package_install "$@"; }
yay() { track_package_install "$@"; }
snap() { track_package_install "$@"; }

# System operations
systemctl() { track_service_operation "$@"; }
create_symlink() { track_config_operation "$@"; }
```

#### Logging Integration
- **Dual Logging**: Console output and file logging
- **Timestamped Entries**: All operations include timestamps
- **Color-Coded Output**: Different colors for different operation types
- **Structured Format**: Consistent formatting for easy parsing

### File Structure

```
tests/
├── dry-run.sh              # Main dry-run implementation
├── test-dry-run.sh         # Unit tests for dry-run functionality
├── demo-dry-run.sh         # Demonstration script
└── README-dry-run.md       # This documentation
```

### Integration Points

#### Core Module Integration
- **Logger Integration**: Uses existing logging system with dry-run extensions
- **Common Functions**: Extends common utility functions with dry-run awareness
- **Menu System**: Integrates with component selection menus

#### Component Module Integration
- **Automatic Detection**: Automatically detects and overrides component installation functions
- **Metadata Extraction**: Extracts package lists and configuration details from components
- **Dependency Tracking**: Tracks component dependencies and conflicts

## Testing

### Unit Tests
Run the comprehensive test suite:
```bash
./tests/test-dry-run.sh
```

### Demo Mode
See dry-run functionality in action:
```bash
./tests/demo-dry-run.sh
```

### Integration Testing
Test with actual components:
```bash
# Test terminal components
./tests/dry-run.sh test terminal

# Test window manager setup
./tests/dry-run.sh test wm

# Test development tools
./tests/dry-run.sh test dev-tools
```

## Configuration

### Environment Variables
- `DRY_RUN=true`: Enable dry-run mode globally
- `VERBOSE=true`: Enable verbose dry-run output
- `DRY_RUN_LOG_FILE`: Custom log file location

### Customization
The dry-run system can be customized by modifying:
- **Tracking Functions**: Add custom operation types
- **Display Functions**: Modify output formatting
- **Override Functions**: Add support for additional commands

## Troubleshooting

### Common Issues

#### Function Override Conflicts
If you encounter issues with function overrides:
```bash
# Disable overrides manually
disable_dry_run_overrides

# Check for conflicting functions
declare -f function_name
```

#### Missing Component Scripts
If components aren't found during testing:
```bash
# Check component directory structure
ls -la components/*/

# Verify component script naming
find components/ -name "*.sh"
```

#### Log File Issues
If log files aren't created:
```bash
# Check permissions
ls -la /tmp/dry-run-*

# Verify log directory
echo $DRY_RUN_LOG_FILE
```

### Debug Mode
Enable debug output for troubleshooting:
```bash
export VERBOSE=true
export DRY_RUN=true
./tests/dry-run.sh test
```

## Requirements Compliance

This implementation satisfies the following requirements:

- **Requirement 6.1**: Dry-run mode shows planned operations without execution
- **Requirement 9.4**: Detailed operation logging and preview capabilities
- **Integration**: Works across all modules without modification
- **Safety**: Prevents any actual system changes during testing
- **Usability**: Provides clear, formatted output for easy review

## Future Enhancements

Potential improvements for the dry-run system:
- **JSON Output**: Machine-readable output format
- **Diff Preview**: Show configuration file changes
- **Resource Estimation**: Estimate disk space and time requirements
- **Dependency Visualization**: Graphical dependency trees
- **Rollback Planning**: Generate rollback scripts for operations