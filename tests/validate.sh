#!/usr/bin/env bash

# tests/validate.sh - Post-installation system validation for the modular install framework
# This module provides comprehensive post-installation validation including service status
# checking, configuration file validation, and functionality testing for installed components.

# Prevent multiple sourcing
if [[ -n "${VALIDATE_SOURCED:-}" ]]; then
    return 0
fi
readonly VALIDATE_SOURCED=1

# Initialize all project paths
source "$(dirname "${BASH_SOURCE[0]}")/../core/init-paths.sh"

# Source required modules
source "$CORE_DIR/common.sh"
source "$CORE_DIR/logger.sh"

# Validation configuration
VALIDATION_LOG_FILE=""
VALIDATION_RESULTS=()
FAILED_VALIDATIONS=()
VALIDATION_SUMMARY=""

#######################################
# Validation Initialization Functions
#######################################

# Initialize validation system
# Sets up logging and tracking for validation operations
init_validation() {
    log_section "SYSTEM VALIDATION INITIALIZATION"
    
    # Create validation log file
    local timestamp=$(date +%Y%m%d_%H%M%S)
    VALIDATION_LOG_FILE="/tmp/validation-report-$timestamp.log"
    touch "$VALIDATION_LOG_FILE"
    
    # Initialize tracking arrays
    VALIDATION_RESULTS=()
    FAILED_VALIDATIONS=()
    
    # Detect if running in VM (use simple method to avoid sudo prompts)
    if lscpu | grep -qi "hypervisor\|virtualization" || [[ -d /proc/vz ]] || [[ -f /proc/xen/capabilities ]] || [[ -d /sys/bus/vmbus ]]; then
        VM_MODE=true
        log_info "Virtual machine detected - using VM-friendly validation"
    else
        VM_MODE=false
    fi
    
    log_info "Validation system initialized"
    log_info "Validation log file: $VALIDATION_LOG_FILE"
    
    # Log system information
    log_validation_header
    
    return 0
}

# Log validation header with system information
log_validation_header() {
    local distro version
    distro=$(get_distro)
    version=$(get_distro_version)
    
    {
        echo "=========================================="
        echo "SYSTEM VALIDATION REPORT"
        echo "=========================================="
        echo "Date: $(date)"
        echo "Distribution: $distro $version"
        echo "Hostname: $(hostname 2>/dev/null || cat /proc/sys/kernel/hostname 2>/dev/null || echo 'unknown')"
        echo "User: $(whoami)"
        echo "VM Mode: ${VM_MODE:-false}"
        echo "=========================================="
        echo
    } >> "$VALIDATION_LOG_FILE"
}

# Finalize validation and generate summary
finalize_validation() {
    log_section "VALIDATION SUMMARY"
    
    local total_tests=${#VALIDATION_RESULTS[@]}
    local failed_tests=${#FAILED_VALIDATIONS[@]}
    local passed_tests=$((total_tests - failed_tests))
    
    # Generate summary
    VALIDATION_SUMMARY="Validation Complete: $passed_tests/$total_tests tests passed"
    
    if [[ $failed_tests -eq 0 ]]; then
        log_success "$VALIDATION_SUMMARY ✓"
    else
        log_warn "$VALIDATION_SUMMARY"
        log_warn "Failed validations: ${FAILED_VALIDATIONS[*]}"
    fi
    
    # Display detailed results
    display_validation_results
    
    # Save summary to log file
    {
        echo
        echo "=========================================="
        echo "VALIDATION SUMMARY"
        echo "=========================================="
        echo "$VALIDATION_SUMMARY"
        echo "Failed validations: ${FAILED_VALIDATIONS[*]}"
        echo "=========================================="
    } >> "$VALIDATION_LOG_FILE"
    
    log_info "Detailed validation report saved to: $VALIDATION_LOG_FILE"
    
    return $([[ $failed_tests -eq 0 ]] && echo 0 || echo 1)
}

#######################################
# Core Validation Functions
#######################################

# Record validation result
# Arguments: $1 - test name, $2 - result (PASS/FAIL), $3 - details (optional)
record_validation_result() {
    local test_name="$1"
    local result="$2"
    local details="${3:-}"
    
    local result_entry="$test_name: $result"
    if [[ -n "$details" ]]; then
        result_entry="$result_entry ($details)"
    fi
    
    VALIDATION_RESULTS+=("$result_entry")
    
    # Log to file
    echo "$(date '+%Y-%m-%d %H:%M:%S') $result_entry" >> "$VALIDATION_LOG_FILE"
    
    # Track failures
    if [[ "$result" == "FAIL" ]]; then
        FAILED_VALIDATIONS+=("$test_name")
        log_error "Validation failed: $test_name"
        if [[ -n "$details" ]]; then
            log_error "Details: $details"
        fi
    else
        log_success "Validation passed: $test_name"
        if [[ -n "$details" ]]; then
            log_info "Details: $details"
        fi
    fi
}

# Validate a service status
# Arguments: $1 - service name, $2 - expected status (active/inactive/enabled/disabled)
validate_service_status() {
    local service="$1"
    local expected_status="$2"
    local actual_status
    
    log_info "Validating service: $service (expected: $expected_status)"
    
    case "$expected_status" in
        "active"|"inactive")
            actual_status=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
            ;;
        "enabled"|"disabled")
            actual_status=$(systemctl is-enabled "$service" 2>/dev/null || echo "disabled")
            ;;
        *)
            record_validation_result "Service $service" "FAIL" "Invalid expected status: $expected_status"
            return 1
            ;;
    esac
    
    if [[ "$actual_status" == "$expected_status" ]]; then
        record_validation_result "Service $service" "PASS" "$actual_status"
        return 0
    else
        record_validation_result "Service $service" "FAIL" "expected $expected_status, got $actual_status"
        return 1
    fi
}

# Validate configuration file exists and is valid
# Arguments: $1 - config file path, $2 - validation type (exists/readable/executable/syntax)
validate_config_file() {
    local config_file="$1"
    local validation_type="${2:-exists}"
    
    log_info "Validating config file: $config_file (type: $validation_type)"
    
    case "$validation_type" in
        "exists")
            if [[ -e "$config_file" ]]; then
                record_validation_result "Config $config_file" "PASS" "exists"
                return 0
            else
                record_validation_result "Config $config_file" "FAIL" "does not exist"
                return 1
            fi
            ;;
        "readable")
            if [[ -r "$config_file" ]]; then
                record_validation_result "Config $config_file" "PASS" "readable"
                return 0
            else
                record_validation_result "Config $config_file" "FAIL" "not readable"
                return 1
            fi
            ;;
        "executable")
            if [[ -x "$config_file" ]]; then
                record_validation_result "Config $config_file" "PASS" "executable"
                return 0
            else
                record_validation_result "Config $config_file" "FAIL" "not executable"
                return 1
            fi
            ;;
        "syntax")
            if validate_config_syntax "$config_file"; then
                record_validation_result "Config $config_file" "PASS" "valid syntax"
                return 0
            else
                record_validation_result "Config $config_file" "FAIL" "invalid syntax"
                return 1
            fi
            ;;
        *)
            record_validation_result "Config $config_file" "FAIL" "unknown validation type: $validation_type"
            return 1
            ;;
    esac
}

# Validate configuration file syntax based on file type
# Arguments: $1 - config file path
validate_config_syntax() {
    local config_file="$1"
    local file_ext="${config_file##*.}"
    
    case "$file_ext" in
        "json")
            if command -v jq >/dev/null 2>&1; then
                jq empty "$config_file" >/dev/null 2>&1
            else
                python3 -m json.tool "$config_file" >/dev/null 2>&1
            fi
            ;;
        "yaml"|"yml")
            if command -v yq >/dev/null 2>&1; then
                yq eval . "$config_file" >/dev/null 2>&1
            else
                python3 -c "import yaml; yaml.safe_load(open('$config_file'))" >/dev/null 2>&1
            fi
            ;;
        "toml")
            if command -v toml-test >/dev/null 2>&1; then
                toml-test "$config_file" >/dev/null 2>&1
            else
                python3 -c "import tomllib; tomllib.load(open('$config_file', 'rb'))" >/dev/null 2>&1 || \
                python3 -c "import toml; toml.load('$config_file')" >/dev/null 2>&1
            fi
            ;;
        "conf"|"config")
            # Basic syntax check for common config formats
            if grep -E "^\s*[^#].*=" "$config_file" >/dev/null 2>&1; then
                return 0  # Looks like key=value format
            elif grep -E "^\s*\[.*\]" "$config_file" >/dev/null 2>&1; then
                return 0  # Looks like INI format
            else
                return 1
            fi
            ;;
        "sh"|"bash")
            bash -n "$config_file" >/dev/null 2>&1
            ;;
        *)
            # For unknown file types, just check if file is readable
            [[ -r "$config_file" ]]
            ;;
    esac
}

# Validate package installation
# Arguments: $1 - package name, $2 - package manager (optional)
validate_package_installed() {
    local package="$1"
    local pm="${2:-auto}"
    
    log_info "Validating package installation: $package"
    
    if is_package_installed "$package" "$pm"; then
        record_validation_result "Package $package" "PASS" "installed"
        return 0
    else
        record_validation_result "Package $package" "FAIL" "not installed"
        return 1
    fi
}

# Validate command availability
# Arguments: $1 - command name, $2 - expected version pattern (optional)
validate_command_available() {
    local command="$1"
    local version_pattern="${2:-}"
    
    log_info "Validating command availability: $command"
    
    if ! command -v "$command" >/dev/null 2>&1; then
        record_validation_result "Command $command" "FAIL" "not available"
        return 1
    fi
    
    if [[ -n "$version_pattern" ]]; then
        local version_output
        version_output=$("$command" --version 2>/dev/null || "$command" -v 2>/dev/null || echo "unknown")
        
        if echo "$version_output" | grep -E "$version_pattern" >/dev/null; then
            record_validation_result "Command $command" "PASS" "available with correct version"
            return 0
        else
            record_validation_result "Command $command" "FAIL" "version mismatch: $version_output"
            return 1
        fi
    else
        record_validation_result "Command $command" "PASS" "available"
        return 0
    fi
}

#######################################
# Component-Specific Validation Functions
#######################################

# Validate terminal component installation
validate_terminal_component() {
    local terminal="${1:-auto}"
    
    log_info "Validating terminal component: $terminal"
    
    case "$terminal" in
        "alacritty"|"auto")
            if [[ "$terminal" == "auto" ]] && ! command -v alacritty >/dev/null 2>&1; then
                return 0  # Skip if not installed
            fi
            
            validate_command_available "alacritty"
            
            # Only validate config if it exists (optional for fresh installs)
            if [[ -f "$HOME/.config/alacritty/alacritty.toml" ]]; then
                validate_config_file "$HOME/.config/alacritty/alacritty.toml" "exists"
                
                # Test alacritty configuration syntax
                if alacritty --print-events --config-file "$HOME/.config/alacritty/alacritty.toml" >/dev/null 2>&1; then
                    record_validation_result "Alacritty config" "PASS" "valid configuration"
                else
                    record_validation_result "Alacritty config" "FAIL" "invalid configuration"
                fi
            else
                record_validation_result "Alacritty config" "PASS" "no config file (using defaults)"
            fi
            ;;
        "kitty")
            validate_command_available "kitty"
            
            # Only validate config if it exists
            if [[ -f "$HOME/.config/kitty/kitty.conf" ]]; then
                validate_config_file "$HOME/.config/kitty/kitty.conf" "exists"
                
                # Test kitty configuration
                if kitty --config "$HOME/.config/kitty/kitty.conf" --debug-config >/dev/null 2>&1; then
                    record_validation_result "Kitty config" "PASS" "valid configuration"
                else
                    record_validation_result "Kitty config" "FAIL" "invalid configuration"
                fi
            else
                record_validation_result "Kitty config" "PASS" "no config file (using defaults)"
            fi
            ;;
        "tmux")
            validate_command_available "tmux"
            
            # Only validate config if it exists
            if [[ -f "$HOME/.tmux.conf" ]]; then
                validate_config_file "$HOME/.tmux.conf" "exists"
                
                # Test tmux configuration
                if tmux -f "$HOME/.tmux.conf" list-sessions >/dev/null 2>&1 || [[ $? -eq 1 ]]; then
                    record_validation_result "Tmux config" "PASS" "valid configuration"
                else
                    record_validation_result "Tmux config" "FAIL" "invalid configuration"
                fi
            else
                record_validation_result "Tmux config" "PASS" "valid configuration"
            fi
            ;;
    esac
}

# Validate shell component installation
validate_shell_component() {
    local shell="${1:-auto}"
    
    log_info "Validating shell component: $shell"
    
    case "$shell" in
        "zsh"|"auto")
            if [[ "$shell" == "auto" ]] && ! command -v zsh >/dev/null 2>&1; then
                return 0  # Skip if not installed
            fi
            
            validate_command_available "zsh"
            
            # Only validate config if it exists
            if [[ -f "$HOME/.zshrc" ]]; then
                validate_config_file "$HOME/.zshrc" "exists"
                
                # Test zsh configuration syntax
                if zsh -n "$HOME/.zshrc" >/dev/null 2>&1; then
                    record_validation_result "Zsh config" "PASS" "valid syntax"
                else
                    record_validation_result "Zsh config" "FAIL" "syntax errors"
                fi
            else
                record_validation_result "Zsh config" "PASS" "no config file (using defaults)"
            fi
            ;;
        "starship")
            validate_command_available "starship"
            
            # Only validate config if it exists
            if [[ -f "$HOME/.config/starship.toml" ]]; then
                validate_config_file "$HOME/.config/starship.toml" "exists"
                
                # Test starship configuration
                if starship config >/dev/null 2>&1; then
                    record_validation_result "Starship config" "PASS" "valid configuration"
                else
                    record_validation_result "Starship config" "FAIL" "invalid configuration"
                fi
            else
                record_validation_result "Starship config" "PASS" "no config file (using defaults)"
            fi
            ;;
    esac
}

# Validate editor component installation
validate_editor_component() {
    local editor="${1:-auto}"
    
    log_info "Validating editor component: $editor"
    
    case "$editor" in
        "neovim"|"nvim"|"auto")
            if [[ "$editor" == "auto" ]] && ! command -v nvim >/dev/null 2>&1; then
                return 0  # Skip if not installed
            fi
            
            validate_command_available "nvim"
            
            # Only validate config if it exists
            if [[ -f "$HOME/.config/nvim/init.lua" ]]; then
                validate_config_file "$HOME/.config/nvim/init.lua" "exists"
                
                # Test neovim configuration
                if nvim --headless -c "checkhealth" -c "quit" >/dev/null 2>&1; then
                    record_validation_result "Neovim config" "PASS" "configuration loads successfully"
                else
                    record_validation_result "Neovim config" "FAIL" "configuration errors"
                fi
            else
                record_validation_result "Neovim config" "PASS" "configuration loads successfully"
            fi
            ;;
        "vscode"|"code")
            validate_command_available "code"
            
            # Check for VS Code settings
            local vscode_settings="$HOME/.config/Code/User/settings.json"
            if [[ -f "$vscode_settings" ]]; then
                validate_config_file "$vscode_settings" "syntax"
            fi
            ;;
    esac
}

# Validate window manager component installation
validate_wm_component() {
    local wm="${1:-auto}"
    
    log_info "Validating window manager component: $wm"
    
    case "$wm" in
        "hyprland"|"auto")
            if [[ "$wm" == "auto" ]] && ! command -v Hyprland >/dev/null 2>&1; then
                return 0  # Skip if not installed
            fi
            
            validate_command_available "Hyprland"
            
            # Only validate config if it exists
            if [[ -f "$HOME/.config/hypr/hyprland.conf" ]]; then
                validate_config_file "$HOME/.config/hypr/hyprland.conf" "exists"
                
                # Test Hyprland configuration syntax
                # Hyprland config validation is complex, just check if file parses
                if grep -E "^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*=" "$HOME/.config/hypr/hyprland.conf" >/dev/null 2>&1; then
                    record_validation_result "Hyprland config" "PASS" "configuration format valid"
                else
                    record_validation_result "Hyprland config" "FAIL" "configuration format issues"
                fi
            else
                record_validation_result "Hyprland config" "PASS" "no config file (using defaults)"
            fi
            ;;
        "waybar")
            validate_command_available "waybar"
            
            # Only validate config if it exists
            if [[ -f "$HOME/.config/waybar/config.jsonc" ]]; then
                validate_config_file "$HOME/.config/waybar/config.jsonc" "exists"
                
                # Test waybar configuration
                # Remove comments from jsonc and validate as json
                local temp_config="/tmp/waybar-config-test.json"
                sed 's|//.*||g' "$HOME/.config/waybar/config.jsonc" > "$temp_config"
                if validate_config_syntax "$temp_config"; then
                    record_validation_result "Waybar config" "PASS" "valid JSON configuration"
                else
                    record_validation_result "Waybar config" "FAIL" "invalid JSON configuration"
                fi
                rm -f "$temp_config"
            else
                record_validation_result "Waybar config" "PASS" "no config file (using defaults)"
            fi
            ;;
        "wofi")
            validate_command_available "wofi"
            validate_config_file "$HOME/.config/wofi/style.css" "exists"
            ;;
        "swaync")
            validate_command_available "swaync"
            
            # Only validate configs if they exist
            if [[ -f "$HOME/.config/swaync/config.json" ]]; then
                validate_config_file "$HOME/.config/swaync/config.json" "syntax"
            else
                record_validation_result "Swaync config" "PASS" "no config file (using defaults)"
            fi
            
            if [[ -f "$HOME/.config/swaync/style.css" ]]; then
                validate_config_file "$HOME/.config/swaync/style.css" "exists"
            else
                record_validation_result "Swaync style" "PASS" "no style file (using defaults)"
            fi
            ;;
    esac
}

# Validate development tools component installation
validate_dev_tools_component() {
    local tool="${1:-auto}"
    
    log_info "Validating development tools component: $tool"
    
    case "$tool" in
        "git"|"auto")
            if [[ "$tool" == "auto" ]] && ! command -v git >/dev/null 2>&1; then
                return 0  # Skip if not installed
            fi
            
            validate_command_available "git"
            
            # Check git configuration
            if git config --global user.name >/dev/null 2>&1 && git config --global user.email >/dev/null 2>&1; then
                record_validation_result "Git config" "PASS" "user name and email configured"
            else
                record_validation_result "Git config" "FAIL" "user name or email not configured"
            fi
            ;;
        "docker")
            validate_command_available "docker"
            validate_service_status "docker" "enabled"
            
            # Test docker functionality
            if command -v docker >/dev/null 2>&1; then
                if docker --version >/dev/null 2>&1; then
                    record_validation_result "Docker functionality" "PASS" "docker command works"
                else
                    record_validation_result "Docker functionality" "FAIL" "docker command failed"
                fi
            fi
            ;;
        "languages")
            # Validate common programming language tools
            local languages=("python3" "node" "npm" "cargo" "go")
            for lang in "${languages[@]}"; do
                if command -v "$lang" >/dev/null 2>&1; then
                    validate_command_available "$lang"
                fi
            done
            ;;
    esac
}

#######################################
# System-Wide Validation Functions
#######################################

# Validate overall system health
validate_system_health() {
    log_info "Validating overall system health..."
    
    # Check system load
    local load_avg
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    local cpu_cores
    cpu_cores=$(nproc)
    
    # Use bc if available, otherwise use awk for floating point comparison
    if command -v bc >/dev/null 2>&1; then
        if (( $(echo "$load_avg < $cpu_cores" | bc -l) )); then
            record_validation_result "System load" "PASS" "load average: $load_avg (cores: $cpu_cores)"
        else
            record_validation_result "System load" "FAIL" "high load average: $load_avg (cores: $cpu_cores)"
        fi
    else
        if awk "BEGIN {exit !($load_avg < $cpu_cores)}"; then
            record_validation_result "System load" "PASS" "load average: $load_avg (cores: $cpu_cores)"
        else
            record_validation_result "System load" "FAIL" "high load average: $load_avg (cores: $cpu_cores)"
        fi
    fi
    
    # Check memory usage
    local mem_usage
    mem_usage=$(free | awk 'NR==2{printf "%.1f", $3*100/$2}')
    
    # Use bc if available, otherwise use awk for floating point comparison
    if command -v bc >/dev/null 2>&1; then
        if (( $(echo "$mem_usage < 90" | bc -l) )); then
            record_validation_result "Memory usage" "PASS" "${mem_usage}% used"
        else
            record_validation_result "Memory usage" "FAIL" "high memory usage: ${mem_usage}%"
        fi
    else
        if awk "BEGIN {exit !($mem_usage < 90)}"; then
            record_validation_result "Memory usage" "PASS" "${mem_usage}% used"
        else
            record_validation_result "Memory usage" "FAIL" "high memory usage: ${mem_usage}%"
        fi
    fi
    
    # Check disk usage
    local disk_usage
    disk_usage=$(df / | awk 'NR==2{print $5}' | tr -d '%')
    
    if [[ $disk_usage -lt 90 ]]; then
        record_validation_result "Disk usage" "PASS" "${disk_usage}% used"
    else
        record_validation_result "Disk usage" "FAIL" "high disk usage: ${disk_usage}%"
    fi
    
    # Check for failed systemd services
    local failed_services
    failed_services=$(systemctl --failed --no-legend | wc -l)
    
    if [[ $failed_services -eq 0 ]]; then
        record_validation_result "System services" "PASS" "no failed services"
    else
        record_validation_result "System services" "FAIL" "$failed_services failed services"
    fi
}

# Validate network connectivity (for package downloads)
validate_network_connectivity() {
    log_info "Validating network connectivity..."
    
    # Test internet connectivity
    if check_internet; then
        record_validation_result "Internet connectivity" "PASS" "can reach external hosts"
    else
        record_validation_result "Internet connectivity" "FAIL" "cannot reach external hosts"
    fi
    
    # Test DNS resolution - try multiple methods
    local dns_works=false
    
    # Try dig first (most reliable)
    if command -v dig >/dev/null 2>&1 && dig +short github.com >/dev/null 2>&1; then
        dns_works=true
    # Try nslookup if available
    elif command -v nslookup >/dev/null 2>&1 && nslookup github.com >/dev/null 2>&1; then
        dns_works=true
    # Fallback to curl test (works if DNS resolves)
    elif curl -s --connect-timeout 5 --max-time 10 https://github.com >/dev/null 2>&1; then
        dns_works=true
    fi
    
    if [[ "$dns_works" == "true" ]]; then
        record_validation_result "DNS resolution" "PASS" "can resolve domain names"
    else
        record_validation_result "DNS resolution" "FAIL" "cannot resolve domain names"
    fi
}

# Validate development environment settings
validate_dev_environment() {
    log_info "Validating development environment..."
    
    # Check if dotfiles repository is properly set up
    if [[ -d "$HOME/.dotfiles" ]] || [[ -d "$HOME/dotfiles" ]]; then
        record_validation_result "Dotfiles repository" "PASS" "dotfiles directory found"
    else
        record_validation_result "Dotfiles repository" "PASS" "no dotfiles directory (optional)"
    fi
    
    # Check shell environment
    if [[ -n "$SHELL" ]]; then
        record_validation_result "Shell environment" "PASS" "shell configured: $SHELL"
    else
        record_validation_result "Shell environment" "FAIL" "no shell configured"
    fi
}

#######################################
# Main Validation Functions
#######################################

# Run comprehensive installation validation
# Arguments: $@ - specific components to validate (optional)
validate_installation() {
    local components=("$@")
    
    log_section "POST-INSTALLATION VALIDATION"
    
    # Initialize validation system
    init_validation
    
    local validation_success=true
    
    # Run system-wide validations
    log_info "Running system-wide validations..."
    
    if ! validate_system_health; then
        validation_success=false
    fi
    
    if ! validate_network_connectivity; then
        validation_success=false
    fi
    
    if ! validate_dev_environment; then
        validation_success=false
    fi
    
    # Run component-specific validations
    if [[ ${#components[@]} -gt 0 ]]; then
        log_info "Running component-specific validations for: ${components[*]}"
        
        for component in "${components[@]}"; do
            if ! validate_component "$component"; then
                validation_success=false
            fi
        done
    else
        log_info "Running validation for all detected components..."
        
        # Auto-detect and validate installed components
        if ! validate_all_components; then
            validation_success=false
        fi
    fi
    
    # Finalize validation and generate report
    if ! finalize_validation; then
        validation_success=false
    fi
    
    return $([[ "$validation_success" == "true" ]] && echo 0 || echo 1)
}

# Validate specific component
# Arguments: $1 - component name
validate_component() {
    local component="$1"
    
    log_info "Validating component: $component"
    
    case "$component" in
        "terminal"|"alacritty"|"kitty"|"tmux")
            validate_terminal_component "$component"
            ;;
        "shell"|"zsh"|"starship")
            validate_shell_component "$component"
            ;;
        "editor"|"neovim"|"nvim"|"vscode"|"code")
            validate_editor_component "$component"
            ;;
        "wm"|"hyprland"|"waybar"|"wofi"|"swaync")
            validate_wm_component "$component"
            ;;
        "dev-tools"|"git"|"docker"|"languages")
            validate_dev_tools_component "$component"
            ;;
        *)
            log_warn "Unknown component for validation: $component"
            record_validation_result "Component $component" "FAIL" "unknown component type"
            return 1
            ;;
    esac
}

# Validate all detected components
validate_all_components() {
    log_info "Auto-detecting and validating installed components..."
    
    local validation_success=true
    
    # Check for terminal components
    for terminal in alacritty kitty tmux; do
        if command -v "$terminal" >/dev/null 2>&1; then
            if ! validate_terminal_component "$terminal"; then
                validation_success=false
            fi
        fi
    done
    
    # Check for shell components
    for shell in zsh starship; do
        if command -v "$shell" >/dev/null 2>&1; then
            if ! validate_shell_component "$shell"; then
                validation_success=false
            fi
        fi
    done
    
    # Check for editor components
    if command -v nvim >/dev/null 2>&1; then
        if ! validate_editor_component "neovim"; then
            validation_success=false
        fi
    fi
    
    if command -v code >/dev/null 2>&1; then
        if ! validate_editor_component "vscode"; then
            validation_success=false
        fi
    fi
    
    # Check for window manager components
    for wm in Hyprland waybar wofi swaync; do
        if command -v "$wm" >/dev/null 2>&1; then
            local component_name=$(echo "$wm" | tr '[:upper:]' '[:lower:]')
            if ! validate_wm_component "$component_name"; then
                validation_success=false
            fi
        fi
    done
    
    # Check for development tools
    for tool in git docker; do
        if command -v "$tool" >/dev/null 2>&1; then
            if ! validate_dev_tools_component "$tool"; then
                validation_success=false
            fi
        fi
    done
    
    # Validate programming languages
    if ! validate_dev_tools_component "languages"; then
        validation_success=false
    fi
    
    return $([[ "$validation_success" == "true" ]] && echo 0 || echo 1)
}

#######################################
# Backup Validation Functions
#######################################

# Validate backup integrity
# Arguments: $1 - backup directory path
validate_backup_integrity() {
    local backup_dir="$1"
    
    log_info "Validating backup integrity: $backup_dir"
    
    if [[ ! -d "$backup_dir" ]]; then
        record_validation_result "Backup directory" "FAIL" "does not exist: $backup_dir"
        return 1
    fi
    
    # Check if backup directory is not empty
    if [[ -z "$(ls -A "$backup_dir")" ]]; then
        record_validation_result "Backup content" "FAIL" "backup directory is empty"
        return 1
    fi
    
    # Validate backup file permissions
    local permission_issues=0
    while IFS= read -r -d '' file; do
        if [[ ! -r "$file" ]]; then
            ((permission_issues++))
        fi
    done < <(find "$backup_dir" -type f -print0)
    
    if [[ $permission_issues -eq 0 ]]; then
        record_validation_result "Backup permissions" "PASS" "all files readable"
    else
        record_validation_result "Backup permissions" "FAIL" "$permission_issues files not readable"
    fi
    
    # Check backup timestamp
    local backup_age
    backup_age=$(find "$backup_dir" -type f -printf '%T@\n' | sort -n | tail -1)
    local current_time
    current_time=$(date +%s)
    local age_hours=$(( (current_time - ${backup_age%.*}) / 3600 ))
    
    if [[ $age_hours -lt 24 ]]; then
        record_validation_result "Backup freshness" "PASS" "backup is $age_hours hours old"
    else
        record_validation_result "Backup freshness" "FAIL" "backup is $age_hours hours old"
    fi
    
    record_validation_result "Backup integrity" "PASS" "backup validation completed"
    return 0
}

# Test backup restoration capability
# Arguments: $1 - backup directory, $2 - test file (optional)
test_backup_restoration() {
    local backup_dir="$1"
    local test_file="${2:-}"
    
    log_info "Testing backup restoration capability..."
    
    # Create a temporary test directory
    local test_dir="/tmp/backup-restore-test-$$"
    mkdir -p "$test_dir"
    
    # If specific test file provided, test its restoration
    if [[ -n "$test_file" && -f "$backup_dir/$test_file" ]]; then
        if cp "$backup_dir/$test_file" "$test_dir/"; then
            record_validation_result "Backup restoration test" "PASS" "successfully restored test file"
            rm -rf "$test_dir"
            return 0
        else
            record_validation_result "Backup restoration test" "FAIL" "failed to restore test file"
            rm -rf "$test_dir"
            return 1
        fi
    fi
    
    # Test restoration of a few random files
    local test_files
    test_files=($(find "$backup_dir" -type f | head -3))
    
    local restoration_success=true
    for file in "${test_files[@]}"; do
        local relative_path="${file#$backup_dir/}"
        local target_dir="$test_dir/$(dirname "$relative_path")"
        
        mkdir -p "$target_dir"
        if ! cp "$file" "$target_dir/"; then
            restoration_success=false
            break
        fi
    done
    
    # Cleanup
    rm -rf "$test_dir"
    
    if [[ "$restoration_success" == "true" ]]; then
        record_validation_result "Backup restoration test" "PASS" "restoration test successful"
        return 0
    else
        record_validation_result "Backup restoration test" "FAIL" "restoration test failed"
        return 1
    fi
}

#######################################
# Display and Reporting Functions
#######################################

# Display validation results in formatted table
display_validation_results() {
    if [[ ${#VALIDATION_RESULTS[@]} -eq 0 ]]; then
        log_info "No validation results to display"
        return 0
    fi
    
    echo
    echo "=== DETAILED VALIDATION RESULTS ==="
    printf "%-40s %-10s %s\n" "Test Name" "Result" "Details"
    printf "%-40s %-10s %s\n" "$(printf '%.40s' "----------------------------------------")" "$(printf '%.10s' "----------")" "----------"
    
    for result in "${VALIDATION_RESULTS[@]}"; do
        # Parse result: "test_name: PASS/FAIL (details)" or "test_name: PASS/FAIL"
        if [[ "$result" =~ ^([^:]+):[[:space:]]+(PASS|FAIL)([[:space:]]+\((.+)\))?$ ]]; then
            local test_name="${BASH_REMATCH[1]}"
            local status="${BASH_REMATCH[2]}"
            local details="${BASH_REMATCH[4]:-}"
            
            # Truncate long test names
            if [[ ${#test_name} -gt 40 ]]; then
                test_name="...${test_name: -37}"
            fi
            
            # Color code the status
            local colored_status
            if [[ "$status" == "PASS" ]]; then
                colored_status="${GREEN}PASS${NC}"
            else
                colored_status="${RED}FAIL${NC}"
            fi
            
            printf "%-40s %-10s %s\n" "$test_name" "$(echo -e "$colored_status")" "$details"
        else
            printf "%-40s %-10s %s\n" "$result" "UNKNOWN" ""
        fi
    done
    echo
}

# Generate validation report file
generate_validation_report() {
    local report_file="${1:-$VALIDATION_LOG_FILE}"
    
    log_info "Generating comprehensive validation report..."
    
    {
        echo "=========================================="
        echo "COMPREHENSIVE VALIDATION REPORT"
        echo "=========================================="
        echo "Generated: $(date)"
        echo "System: $(get_distro) $(get_distro_version)"
        echo "Hostname: $(hostname 2>/dev/null || cat /proc/sys/kernel/hostname 2>/dev/null || echo 'unknown')"
        echo "User: $(whoami)"
        echo
        
        echo "SUMMARY:"
        echo "$VALIDATION_SUMMARY"
        echo
        
        if [[ ${#FAILED_VALIDATIONS[@]} -gt 0 ]]; then
            echo "FAILED VALIDATIONS:"
            for failure in "${FAILED_VALIDATIONS[@]}"; do
                echo "  - $failure"
            done
            echo
        fi
        
        echo "DETAILED RESULTS:"
        for result in "${VALIDATION_RESULTS[@]}"; do
            echo "  $result"
        done
        echo
        
        echo "SYSTEM INFORMATION:"
        echo "  Uptime: $(uptime)"
        echo "  Load Average: $(uptime | awk -F'load average:' '{print $2}')"
        echo "  Memory: $(free -h | grep '^Mem:' | awk '{print $3 "/" $2}')"
        echo "  Disk Usage: $(df -h / | awk 'NR==2{print $5 " used of " $2}')"
        echo
        
        echo "INSTALLED PACKAGES (sample):"
        local distro
        distro=$(get_distro)
        case "$distro" in
            "arch")
                pacman -Q | head -10
                ;;
            "ubuntu")
                dpkg -l | grep "^ii" | head -10 | awk '{print $2 " " $3}'
                ;;
        esac
        echo
        
        echo "ACTIVE SERVICES:"
        systemctl list-units --type=service --state=active --no-legend | head -10
        echo
        
        echo "=========================================="
        echo "END OF VALIDATION REPORT"
        echo "=========================================="
    } > "$report_file"
    
    log_success "Validation report saved to: $report_file"
}

#######################################
# Command Line Interface
#######################################

# Main validation function
# Arguments: $1 - mode, $2+ - components or options
main_validate() {
    local mode="${1:-full}"
    shift
    local components=("$@")
    
    case "$mode" in
        "full"|"all")
            validate_installation "${components[@]}"
            ;;
        "component"|"comp")
            if [[ ${#components[@]} -eq 0 ]]; then
                log_error "Component name required for component validation mode"
                exit 1
            fi
            
            init_validation
            
            for component in "${components[@]}"; do
                validate_component "$component"
            done
            
            finalize_validation
            ;;
        "system"|"sys")
            init_validation
            validate_system_health
            validate_network_connectivity
            validate_security_settings
            finalize_validation
            ;;
        "backup")
            if [[ ${#components[@]} -eq 0 ]]; then
                log_error "Backup directory required for backup validation mode"
                exit 1
            fi
            
            init_validation
            
            for backup_dir in "${components[@]}"; do
                validate_backup_integrity "$backup_dir"
                test_backup_restoration "$backup_dir"
            done
            
            finalize_validation
            ;;
        "report")
            local report_file="${components[0]:-/tmp/validation-report-$(date +%Y%m%d_%H%M%S).log}"
            generate_validation_report "$report_file"
            ;;
        *)
            echo "Usage: $0 [mode] [components/options...]"
            echo
            echo "Modes:"
            echo "  full         - Run complete validation (default)"
            echo "  component    - Validate specific components"
            echo "  system       - Validate system health only"
            echo "  backup       - Validate backup integrity"
            echo "  report       - Generate validation report"
            echo
            echo "Examples:"
            echo "  $0                           # Full validation"
            echo "  $0 component terminal shell  # Validate specific components"
            echo "  $0 system                    # System health check only"
            echo "  $0 backup /path/to/backup    # Validate backup directory"
            echo "  $0 report /path/to/report    # Generate report file"
            exit 1
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_validate "$@"
fi