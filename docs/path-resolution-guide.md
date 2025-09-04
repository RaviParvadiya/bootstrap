# Path Resolution Guide

This guide explains how to properly handle file paths in the modular install framework, following DRY principles.

## The Problem

Previously, each script had to calculate its own paths:

```bash
# This was repeated in every script - violates DRY principle
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$SCRIPT_DIR/core"
# ... more path definitions
```

## The Solution

We now have centralized path resolution that works from any script location.

### For Scripts in Project Root

```bash
#!/usr/bin/env bash
# install.sh, update.sh, etc.

# Initialize all project paths
source "$(dirname "${BASH_SOURCE[0]}")/core/init-paths.sh"

# Now you can use all path variables:
source "$CORE_DIR/common.sh"
source "$CORE_DIR/logger.sh"
```

### For Scripts in Subdirectories

```bash
#!/usr/bin/env bash
# tests/vm-test.sh, components/terminal/install.sh, etc.

# Initialize all project paths
source "$(dirname "${BASH_SOURCE[0]}")/../core/init-paths.sh"

# Now you can use all path variables:
source "$CORE_DIR/common.sh"
source "$TESTS_DIR/validate.sh"
```

### For Scripts in Deep Subdirectories

```bash
#!/usr/bin/env bash
# components/terminal/alacritty/config.sh, etc.

# Initialize all project paths
source "$(dirname "${BASH_SOURCE[0]}")/../../core/init-paths.sh"

# Now you can use all path variables:
source "$CORE_DIR/common.sh"
source "$COMPONENTS_DIR/common/utils.sh"
```

## Available Path Variables

After sourcing `init-paths.sh`, these variables are available:

- `$SCRIPT_DIR` - Project root directory
- `$CORE_DIR` - Core utilities directory
- `$DISTROS_DIR` - Distribution-specific scripts
- `$COMPONENTS_DIR` - Component installation scripts
- `$CONFIGS_DIR` - Configuration management scripts
- `$DATA_DIR` - Data files (package lists, etc.)
- `$TESTS_DIR` - Test scripts and utilities
- `$DOCS_DIR` - Documentation directory
- `$DOTFILES_DIR` - Dotfiles directory

## How It Works

1. **Smart Root Detection**: The system automatically finds the project root by looking for `install.sh`
2. **Relative Path Calculation**: Works from any subdirectory depth
3. **Single Source of Truth**: All path logic is in `core/paths.sh`
4. **Validation**: Automatically validates that required directories exist
5. **Export**: All paths are exported for use in child processes

## Benefits

- **DRY Principle**: Path calculation logic exists in only one place
- **Consistency**: All scripts use the same path resolution method
- **Flexibility**: Works regardless of where the script is called from
- **Maintainability**: Easy to add new paths or modify existing ones
- **Error Prevention**: Automatic validation prevents missing directory errors

## Migration Guide

To migrate existing scripts:

1. Replace the old path calculation block:
   ```bash
   # OLD - Remove this
   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   CORE_DIR="$SCRIPT_DIR/core"
   # ... etc
   ```

2. Add the new initialization:
   ```bash
   # NEW - Add this
   source "$(dirname "${BASH_SOURCE[0]}")/../core/init-paths.sh"
   ```

3. Update any hardcoded relative paths to use the variables:
   ```bash
   # OLD
   source "../core/common.sh"
   
   # NEW
   source "$CORE_DIR/common.sh"
   ```

## Testing

The path resolution system includes built-in validation. If paths are incorrect, you'll get clear error messages indicating what's missing and where the system thinks it should be.