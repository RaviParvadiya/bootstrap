# Package Management System

The modular install framework includes a comprehensive package management system that handles structured package lists with support for comments, sections, conditional installation, and multiple package sources.

## Features

- **Structured Package Lists**: Support for organized package lists with sections and comments
- **Conditional Installation**: Install packages based on system capabilities (GPU, laptop, VM, etc.)
- **Multiple Sources**: Support for different package managers (pacman, AUR, apt)
- **Cross-Distribution**: Works with both Arch Linux and Ubuntu
- **Validation**: Built-in validation for package list syntax and structure
- **Caching**: Intelligent caching of condition evaluations for performance

## Package List Format

### Basic Format
```
# Comments start with hash
package_name
package_name|condition
source:package_name
source:package_name|condition
```

### Sections
```
# --- Section Name ---
package1
package2
package3
```

### Sources
- `apt:package` - APT package (Ubuntu default)
- `aur:package` - AUR package (Arch only)
- No prefix defaults to distribution's primary package manager

### Conditions
- `nvidia` - NVIDIA GPU detected
- `amd` - AMD GPU detected
- `gaming` - Gaming packages (user prompt in interactive mode)
- `laptop` - Laptop hardware detected
- `vm` - Virtual machine environment
- `asus` - ASUS hardware detected

## File Structure

```
data/
├── arch-packages.lst     # Arch Linux packages (pacman)
├── ubuntu-packages.lst   # Ubuntu packages (apt)
├── aur-packages.lst      # AUR packages (Arch only)
├── component-deps.json   # Component dependency mapping
└── hardware-profiles.json # Hardware-specific configurations
```

## API Functions

### Core Functions

#### `init_package_manager()`
Initialize the package management system and clear caches.

#### `parse_package_list(file_path, [condition_filter])`
Parse a package list file and return structured package entries.

#### `check_package_condition(condition)`
Evaluate whether a package condition is met on the current system.

### Package Retrieval

#### `get_packages_for_distro(distro, [condition_filter])`
Get all packages for a specific distribution.

#### `get_packages_by_source(distro, source, [condition_filter])`
Get packages filtered by source (apt, aur, etc.).

#### `get_packages_by_section(distro, section, [condition_filter])`
Get packages filtered by section name.

### Installation

#### `install_packages_from_list(distro, source, packages...)`
Install packages using the appropriate package manager.

#### `install_all_packages(distro, [condition_filter])`
Install all packages for a distribution with optional filtering.

### Utilities

#### `list_packages(distro, [source], [section], [condition_filter])`
List available packages with optional filtering.

#### `validate_package_lists()`
Validate all package list files for syntax errors.

## Usage Examples

### Basic Usage
```bash
# Source the package manager
source core/package-manager.sh

# Initialize
init_package_manager

# Get all Arch packages
get_packages_for_distro "arch"

# Get only AUR packages
get_packages_by_source "arch" "aur"

# Install packages (dry-run mode)
DRY_RUN=true install_all_packages "arch"
```

### Conditional Installation
```bash
# Install only NVIDIA-related packages
get_packages_for_distro "arch" "nvidia"

# Install gaming packages (will prompt user)
get_packages_for_distro "arch" "gaming"
```

### Cross-Distribution
```bash
# Ubuntu APT packages
get_packages_by_source "ubuntu" "apt"

# Ubuntu APT packages only
get_packages_by_source "ubuntu" "apt"
```

## Testing

The package management system includes comprehensive tests:

```bash
# Run all tests
./tests/test-package-management.sh

# Run specific test suites
./tests/test-package-management.sh parsing
./tests/test-package-management.sh conditions
./tests/test-package-management.sh filtering
./tests/test-package-management.sh validation
```

## Integration

The package management system integrates with:

- **Distribution Handlers**: `distros/arch/` and `distros/ubuntu/`
- **Component System**: Maps components to required packages
- **Hardware Detection**: Automatically detects system capabilities
- **Logging System**: Comprehensive logging and error handling

## Configuration

### Environment Variables
- `DRY_RUN`: Enable dry-run mode (default: false)
- `VERBOSE`: Enable verbose logging (default: false)
- `SCRIPT_DIR`: Project root directory (auto-detected)

### Customization
- Add new conditions in `check_package_condition()`
- Add new package sources in `install_packages_from_list()`
- Modify package lists in `data/` directory
- Update hardware profiles in `data/hardware-profiles.json`

## Error Handling

The system includes robust error handling:

- **File Validation**: Checks for missing or unreadable files
- **Syntax Validation**: Validates package list format
- **Condition Evaluation**: Safe evaluation of system conditions
- **Package Installation**: Graceful handling of installation failures
- **Logging**: Comprehensive error logging and user feedback

## Performance

- **Caching**: Condition evaluations are cached for performance
- **Lazy Loading**: Package lists are parsed on-demand
- **Parallel Processing**: Support for parallel package installation
- **Memory Efficient**: Streams large package lists instead of loading entirely into memory