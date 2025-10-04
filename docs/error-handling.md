# Error Handling and Recovery System

The Modular Install Framework includes a comprehensive error handling and recovery system designed to provide graceful degradation, automatic recovery, and rollback capabilities.

## Overview

The error handling system consists of several components:

- **Error Handler** (`core/error-handler.sh`): Core error categorization and handling logic
- **Error Wrappers** (`core/error-wrappers.sh`): Safe wrapper functions for common operations
- **Recovery System** (`core/recovery-system.sh`): Automated recovery mechanisms and checkpoints
- **Test Suite** (`tests/test-error-handling.sh`): Comprehensive testing of error scenarios

## Error Categories

The system categorizes errors into different types with specific handling policies:

| Category | Policy | Description |
|----------|--------|-------------|
| `critical` | stop | System incompatibility, missing permissions - stop immediately |
| `package` | continue | Failed installations, missing dependencies - continue with remaining |
| `config` | rollback | File conflicts, invalid configurations - attempt rollback |
| `network` | retry | Download failures, repository issues - retry with backoff |
| `permission` | prompt | Permission denied - prompt user for action |
| `validation` | warn | Validation failures - log warning and continue |

## Error Recovery Modes

The system supports three recovery modes:

### Graceful Mode (Default)
- Continues installation when possible
- Logs errors and attempts automatic recovery
- Suitable for most installations

### Strict Mode
- Stops on any error
- Requires manual intervention
- Suitable for critical environments

### Interactive Mode
- Prompts user for action on errors
- Allows manual decision making
- Suitable for supervised installations

## Usage Examples

### Basic Error Handling

```bash
# Source the error handling system
source "core/error-handler.sh"
source "core/error-wrappers.sh"

# Initialize error handling
init_error_handler

# Set recovery mode
set_error_recovery_mode "graceful"

# Use safe wrapper functions
safe_install_package "some-package"
safe_copy_file "/source/file" "/dest/file"
safe_create_symlink "/source" "/dest/link"
```

### Error Context Management

```bash
# Push context for better error reporting
push_error_context "component_install" "Installing terminal components"

# Your operations here
safe_install_package "alacritty"
safe_copy_file "configs/alacritty.yml" "$HOME/.config/alacritty/alacritty.yml"

# Pop context when done
pop_error_context
```

### Rollback Registration

```bash
# Register rollback actions before making changes
register_rollback_action "install_package_vim" \
    "sudo pacman -R vim --noconfirm" \
    "Remove vim package"

# Make the change
safe_install_package "vim"

# If error occurs, rollback can be performed automatically
```

### Recovery Checkpoints

```bash
# Create system checkpoint before major operations
create_checkpoint "pre_wm_install" "Before window manager installation"

# Perform operations
install_window_manager_components

# If something goes wrong, restore from checkpoint
restore_from_checkpoint "pre_wm_install"
```

## Safe Wrapper Functions

The system provides safe wrapper functions that include automatic error handling:

### Package Management
- `safe_install_package <package> [package_manager] [component]`
- `safe_install_packages <package1> <package2> ...`

### File Operations
- `safe_copy_file <source> <destination> [backup]`
- `safe_create_symlink <source> <destination> [force]`
- `safe_create_directory <path> [mode]`

### Service Management
- `safe_enable_service <service> [start_now]`

### Network Operations
- `safe_download_file <url> <destination> [max_retries]`

### Command Execution
- `safe_execute_command <command> <description> [allow_failure]`
- `safe_execute_with_timeout <timeout> <command> <description>`

### Validation
- `safe_validate <validation_function> <description> [critical]`

### Batch Operations
- `safe_batch_operation <operation_function> <description> <item1> <item2> ...`

## Error Handling Functions

### Manual Error Handling
```bash
# Handle specific error types
handle_package_error "package-name" "error message" "package-manager"
handle_config_error "/path/to/config" "error message" "operation"
handle_network_error "download" "error message" "url"
handle_permission_error "write" "/path" "error message"
handle_validation_error "system_check" "error message" "component"
```

### Generic Error Handling
```bash
# Generic error handling with category
handle_error "category" "error message" "operation" [severity]
```

## Recovery System

### Automatic Recovery
The system includes automatic recovery strategies for common failure scenarios:

```bash
# Attempt automatic recovery
attempt_auto_recovery "package_install_failed" "package-name" "error message"
```

### Recovery Strategies
- **Package Installation**: Update repos, try alternative sources, skip optional packages
- **Configuration**: Backup and overwrite, merge configs, skip configuration
- **Network**: Retry with backoff, try alternative mirrors, continue offline
- **Permissions**: Fix permissions, run as sudo, skip operation
- **Services**: Check dependencies, restart service, disable service

### Checkpoint Management
```bash
# Create checkpoint
create_checkpoint "checkpoint_name" "description"

# List available checkpoints
list_checkpoints

# Restore from checkpoint
restore_from_checkpoint "checkpoint_name"

# Clean up old checkpoints
cleanup_old_checkpoints 5  # Keep 5 most recent
```

## Configuration

### Environment Variables
- `ERROR_RECOVERY_MODE`: Set recovery mode (graceful, strict, interactive)
- `ERROR_ROLLBACK_ENABLED`: Enable/disable rollback functionality (true/false)
- `DRY_RUN`: Enable dry-run mode for testing (true/false)

### Error Categories Configuration
Error handling policies can be customized by modifying the `ERROR_CATEGORIES` array in `core/error-handler.sh`.

## Testing

### Run Error Handling Tests
```bash
# Run all tests in dry-run mode
./tests/test-error-handling.sh

# Run specific test
./tests/test-error-handling.sh package

# Run with real operations (be careful!)
./tests/test-error-handling.sh --real-run

# Test different recovery modes
./tests/test-error-handling.sh -m strict rollback
```

### Available Tests
- `package`: Package installation error handling
- `config`: Configuration file error handling
- `network`: Network operation error handling
- `permission`: Permission error handling
- `validation`: Validation error handling
- `rollback`: Rollback system functionality
- `recovery`: Recovery system and checkpoints
- `batch`: Batch operation error handling
- `modes`: Different error recovery modes
- `context`: Error context stack management

## Integration with Existing Code

### Updating Existing Functions
Replace direct operations with safe wrapper functions:

```bash
# Before
pacman -S some-package
cp source dest
ln -s source dest

# After
safe_install_package "some-package"
safe_copy_file "source" "dest"
safe_create_symlink "source" "dest"
```

### Adding Error Context
Wrap operations in error context:

```bash
# Before
install_component() {
    install_package "package"
    copy_config "config"
}

# After
install_component() {
    push_error_context "component" "Installing component"
    
    safe_install_package "package"
    safe_copy_file "config" "$HOME/.config/app/config"
    
    pop_error_context
}
```

## Error Reporting

### Error Summary
```bash
# Show error summary
show_error_summary
```

### Generate Error Report
```bash
# Generate detailed error report
generate_error_report [output_file]
```

### Recovery Status
```bash
# Show recovery system status
show_recovery_status
```

## Best Practices

1. **Always use safe wrapper functions** for operations that can fail
2. **Set appropriate error context** before performing operations
3. **Register rollback actions** before making system changes
4. **Create checkpoints** before major installation phases
5. **Test error scenarios** using the test suite
6. **Choose appropriate recovery mode** for your use case
7. **Monitor error logs** and reports for issues

## Troubleshooting

### Common Issues

**Error: "jq is required for JSON parsing"**
- Install jq: `sudo pacman -S jq` (Arch) or `sudo apt install jq` (Ubuntu)

**Error: "Permission denied"**
- Ensure user has sudo privileges
- Check file permissions and ownership

**Error: "Rollback failed"**
- Check rollback commands are valid
- Verify rollback actions were registered correctly

### Debug Mode
Enable detailed logging for error information:
```bash
# Check log files for detailed information
tail -f /tmp/modular-install-*.log
```

### Log Files
Error handling creates several log files:
- Error log: `/tmp/modular-install-errors-TIMESTAMP.log`
- Recovery log: `/tmp/modular-install-recovery-actions.log`
- Main log: `/tmp/modular-install-TIMESTAMP.log`

## Advanced Usage

### Custom Recovery Strategies
Add custom recovery strategies by extending the `RECOVERY_STRATEGIES` array and implementing corresponding functions in `core/recovery-system.sh`.

### Custom Error Categories
Add new error categories by extending the `ERROR_CATEGORIES` array in `core/error-handler.sh`.

### Integration with External Tools
The error handling system can be integrated with external monitoring and alerting tools by parsing the generated error reports and logs.