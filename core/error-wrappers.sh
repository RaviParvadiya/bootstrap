#!/usr/bin/env bash

# core/error-wrappers.sh - Error handling wrapper functions
# Provides convenient wrappers for common operations with integrated error handling
# Requirements: 10.1, 10.2, 6.2

# Prevent multiple sourcing
if [[ -n "${ERROR_WRAPPERS_SOURCED:-}" ]]; then
    return 0
fi
readonly ERROR_WRAPPERS_SOURCED=1

# Initialize all project paths (only if not already initialized)
if [[ -z "${PATHS_SOURCED:-}" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/init-paths.sh"
fi

# Only source if not already sourced
if [[ -z "${ERROR_HANDLER_SOURCED:-}" ]]; then
    source "$CORE_DIR/error-handler.sh"
fi
if [[ -z "${COMMON_SOURCED:-}" ]]; then
    source "$CORE_DIR/common.sh"
fi
if [[ -z "${LOGGER_SOURCED:-}" ]]; then
    source "$CORE_DIR/logger.sh"
fi

#######################################
# Package Management Wrappers
#######################################

# Safe package installation with error handling
# Arguments: $1 - package name, $2 - package manager (optional), $3 - component (optional)
safe_install_package() {
    local package="$1"
    local package_manager="${2:-auto}"
    local component="${3:-unknown}"
    
    if [[ -z "$package" ]]; then
        handle_error "package" "Package name is required" "safe_install_package"
        return 1
    fi
    
    push_error_context "package_install" "Installing package: $package"
    
    # Register rollback action for package removal
    local distro
    distro=$(get_distro)
    case "$distro" in
        "arch")
            register_rollback_action "install_package_$package" \
                "sudo pacman -Rns --noconfirm '$package' 2>/dev/null || true" \
                "Remove package: $package"
            ;;
        "ubuntu")
            register_rollback_action "install_package_$package" \
                "sudo apt-get remove -y '$package' 2>/dev/null || true" \
                "Remove package: $package"
            ;;
    esac
    
    # Attempt installation with retry logic
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        log_info "Installing package: $package (attempt $attempt/$max_attempts)"
        
        if install_package "$package" "$package_manager"; then
            log_success "Package installed successfully: $package"
            pop_error_context
            return 0
        else
            local error_msg="Package installation failed (attempt $attempt/$max_attempts)"
            
            if [[ $attempt -eq $max_attempts ]]; then
                handle_package_error "$package" "$error_msg" "$package_manager"
                pop_error_context
                return 1
            else
                log_warn "$error_msg, retrying..."
                ((attempt++))
                
                # Progressive delay between retries
                local delay=$((attempt * 2))
                if [[ "$DRY_RUN" != "true" ]]; then
                    sleep $delay
                fi
            fi
        fi
    done
    
    pop_error_context
    return 1
}

# Safe installation of multiple packages
# Arguments: $@ - array of package names
safe_install_packages() {
    local packages=("$@")
    local failed_packages=()
    local success_count=0
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        handle_error "package" "No packages specified for installation" "safe_install_packages"
        return 1
    fi
    
    push_error_context "package_batch" "Installing ${#packages[@]} packages"
    
    log_info "Installing packages: ${packages[*]}"
    
    for package in "${packages[@]}"; do
        if safe_install_package "$package"; then
            ((success_count++))
        else
            failed_packages+=("$package")
            
            # Check if we should continue or abort
            if [[ "$ERROR_RECOVERY_MODE" == "strict" ]]; then
                log_error "Aborting package installation due to strict mode"
                pop_error_context
                return 1
            fi
        fi
    done
    
    # Report results
    if [[ ${#failed_packages[@]} -gt 0 ]]; then
        local error_msg="Failed to install ${#failed_packages[@]} packages: ${failed_packages[*]}"
        handle_error "package" "$error_msg" "safe_install_packages"
        log_info "Successfully installed: $success_count/${#packages[@]} packages"
        pop_error_context
        return 1
    else
        log_success "All packages installed successfully ($success_count packages)"
        pop_error_context
        return 0
    fi
}

#######################################
# File Operation Wrappers
#######################################

# Safe file copy with error handling and backup
# Arguments: $1 - source, $2 - destination, $3 - backup (optional, default=true)
safe_copy_file() {
    local source="$1"
    local destination="$2"
    local create_backup="${3:-true}"
    
    if [[ -z "$source" || -z "$destination" ]]; then
        handle_error "config" "Source and destination are required" "safe_copy_file"
        return 1
    fi
    
    if [[ ! -f "$source" ]]; then
        handle_config_error "$source" "Source file does not exist" "copy"
        return 1
    fi
    
    push_error_context "file_copy" "Copying: $source -> $destination"
    
    # Create destination directory if needed
    local dest_dir
    dest_dir=$(dirname "$destination")
    if [[ ! -d "$dest_dir" ]]; then
        if ! safe_create_directory "$dest_dir"; then
            pop_error_context
            return 1
        fi
    fi
    
    # Create backup if file exists and backup is requested
    if [[ -f "$destination" && "$create_backup" == "true" ]]; then
        local backup_file="${destination}.backup.$(date +%Y%m%d_%H%M%S)"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would backup: $destination -> $backup_file"
        else
            if ! cp "$destination" "$backup_file"; then
                handle_config_error "$destination" "Failed to create backup" "backup"
                pop_error_context
                return 1
            fi
            log_info "Created backup: $backup_file"
        fi
        
        # Register rollback action
        register_rollback_action "copy_file_$destination" \
            "mv '$backup_file' '$destination' 2>/dev/null || true" \
            "Restore backup: $destination"
    else
        # Register rollback action to remove file
        register_rollback_action "copy_file_$destination" \
            "rm -f '$destination' 2>/dev/null || true" \
            "Remove copied file: $destination"
    fi
    
    # Perform the copy
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would copy: $source -> $destination"
    else
        if ! cp "$source" "$destination"; then
            handle_config_error "$source" "Failed to copy file to $destination" "copy"
            pop_error_context
            return 1
        fi
    fi
    
    log_success "File copied successfully: $destination"
    pop_error_context
    return 0
}

# Safe symlink creation with error handling
# Arguments: $1 - source, $2 - destination, $3 - force (optional, default=false)
safe_create_symlink() {
    local source="$1"
    local destination="$2"
    local force="${3:-false}"
    
    if [[ -z "$source" || -z "$destination" ]]; then
        handle_error "config" "Source and destination are required" "safe_create_symlink"
        return 1
    fi
    
    if [[ ! -e "$source" ]]; then
        handle_config_error "$source" "Source does not exist" "symlink"
        return 1
    fi
    
    push_error_context "symlink" "Creating symlink: $destination -> $source"
    
    # Create destination directory if needed
    local dest_dir
    dest_dir=$(dirname "$destination")
    if [[ ! -d "$dest_dir" ]]; then
        if ! safe_create_directory "$dest_dir"; then
            pop_error_context
            return 1
        fi
    fi
    
    # Handle existing destination
    if [[ -e "$destination" || -L "$destination" ]]; then
        if [[ -L "$destination" ]]; then
            local current_target
            current_target=$(readlink "$destination")
            if [[ "$current_target" == "$source" ]]; then
                log_info "Symlink already exists and is correct: $destination"
                pop_error_context
                return 0
            fi
        fi
        
        if [[ "$force" == "true" ]]; then
            # Backup existing file/link
            local backup_file="${destination}.backup.$(date +%Y%m%d_%H%M%S)"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would backup existing: $destination -> $backup_file"
            else
                if ! mv "$destination" "$backup_file"; then
                    handle_config_error "$destination" "Failed to backup existing file" "symlink"
                    pop_error_context
                    return 1
                fi
                log_info "Backed up existing file: $backup_file"
            fi
            
            # Register rollback action
            register_rollback_action "symlink_$destination" \
                "rm -f '$destination' && mv '$backup_file' '$destination' 2>/dev/null || true" \
                "Restore backup and remove symlink: $destination"
        else
            handle_config_error "$destination" "Destination already exists (use force=true to overwrite)" "symlink"
            pop_error_context
            return 1
        fi
    else
        # Register rollback action to remove symlink
        register_rollback_action "symlink_$destination" \
            "rm -f '$destination' 2>/dev/null || true" \
            "Remove symlink: $destination"
    fi
    
    # Create the symlink
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create symlink: $destination -> $source"
    else
        if ! ln -s "$source" "$destination"; then
            handle_config_error "$source" "Failed to create symlink to $destination" "symlink"
            pop_error_context
            return 1
        fi
    fi
    
    log_success "Symlink created successfully: $destination -> $source"
    pop_error_context
    return 0
}

# Safe directory creation with error handling
# Arguments: $1 - directory path, $2 - mode (optional)
safe_create_directory() {
    local directory="$1"
    local mode="${2:-755}"
    
    if [[ -z "$directory" ]]; then
        handle_error "config" "Directory path is required" "safe_create_directory"
        return 1
    fi
    
    if [[ -d "$directory" ]]; then
        log_debug "Directory already exists: $directory"
        return 0
    fi
    
    push_error_context "directory" "Creating directory: $directory"
    
    # Register rollback action
    register_rollback_action "create_directory_$directory" \
        "rmdir '$directory' 2>/dev/null || true" \
        "Remove directory: $directory"
    
    # Create the directory
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create directory: $directory (mode: $mode)"
    else
        if ! mkdir -p "$directory"; then
            handle_config_error "$directory" "Failed to create directory" "mkdir"
            pop_error_context
            return 1
        fi
        
        # Set permissions if specified
        if [[ "$mode" != "755" ]]; then
            if ! chmod "$mode" "$directory"; then
                handle_config_error "$directory" "Failed to set directory permissions" "chmod"
                pop_error_context
                return 1
            fi
        fi
    fi
    
    log_success "Directory created successfully: $directory"
    pop_error_context
    return 0
}

#######################################
# Service Management Wrappers
#######################################

# Safe service enable with error handling
# Arguments: $1 - service name, $2 - start immediately (optional, default=false)
safe_enable_service() {
    local service_name="$1"
    local start_now="${2:-false}"
    
    if [[ -z "$service_name" ]]; then
        handle_error "critical" "Service name is required" "safe_enable_service"
        return 1
    fi
    
    push_error_context "service" "Enabling service: $service_name"
    
    # Check if service exists
    if ! systemctl list-unit-files "${service_name}.service" >/dev/null 2>&1; then
        handle_error "critical" "Service does not exist: $service_name" "safe_enable_service"
        pop_error_context
        return 1
    fi
    
    # Check if already enabled
    if systemctl is-enabled "${service_name}.service" >/dev/null 2>&1; then
        log_info "Service already enabled: $service_name"
        pop_error_context
        return 0
    fi
    
    # Register rollback action
    register_rollback_action "enable_service_$service_name" \
        "sudo systemctl disable '$service_name' 2>/dev/null || true" \
        "Disable service: $service_name"
    
    # Enable the service
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would enable service: $service_name"
        if [[ "$start_now" == "true" ]]; then
            log_info "[DRY RUN] Would start service: $service_name"
        fi
    else
        if ! sudo systemctl enable "$service_name"; then
            handle_error "critical" "Failed to enable service: $service_name" "safe_enable_service"
            pop_error_context
            return 1
        fi
        
        # Start service if requested
        if [[ "$start_now" == "true" ]]; then
            if ! sudo systemctl start "$service_name"; then
                handle_error "package" "Failed to start service: $service_name" "safe_enable_service"
                # Don't return error here, service is enabled even if start failed
            else
                log_success "Service started: $service_name"
            fi
        fi
    fi
    
    log_success "Service enabled successfully: $service_name"
    pop_error_context
    return 0
}

#######################################
# Network Operation Wrappers
#######################################

# Safe download with error handling and retry
# Arguments: $1 - URL, $2 - destination, $3 - max retries (optional, default=3)
safe_download_file() {
    local url="$1"
    local destination="$2"
    local max_retries="${3:-3}"
    
    if [[ -z "$url" || -z "$destination" ]]; then
        handle_error "network" "URL and destination are required" "safe_download_file"
        return 1
    fi
    
    push_error_context "download" "Downloading: $url"
    
    # Create destination directory if needed
    local dest_dir
    dest_dir=$(dirname "$destination")
    if [[ ! -d "$dest_dir" ]]; then
        if ! safe_create_directory "$dest_dir"; then
            pop_error_context
            return 1
        fi
    fi
    
    # Register rollback action
    register_rollback_action "download_$destination" \
        "rm -f '$destination' 2>/dev/null || true" \
        "Remove downloaded file: $destination"
    
    # Attempt download with retries
    local attempt=1
    while [[ $attempt -le $max_retries ]]; do
        log_info "Downloading file (attempt $attempt/$max_retries): $url"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would download: $url -> $destination"
            pop_error_context
            return 0
        fi
        
        # Try different download tools
        local download_success=false
        
        if command -v curl >/dev/null 2>&1; then
            if curl -fsSL -o "$destination" "$url"; then
                download_success=true
            fi
        elif command -v wget >/dev/null 2>&1; then
            if wget -q -O "$destination" "$url"; then
                download_success=true
            fi
        else
            handle_network_error "download" "No download tool available (curl or wget)" "$url"
            pop_error_context
            return 1
        fi
        
        if [[ "$download_success" == "true" ]]; then
            log_success "File downloaded successfully: $destination"
            pop_error_context
            return 0
        else
            local error_msg="Download failed (attempt $attempt/$max_retries)"
            
            if [[ $attempt -eq $max_retries ]]; then
                handle_network_error "download" "$error_msg" "$url"
                pop_error_context
                return 1
            else
                log_warn "$error_msg, retrying..."
                ((attempt++))
                
                # Progressive delay between retries
                local delay=$((attempt * 2))
                sleep $delay
            fi
        fi
    done
    
    pop_error_context
    return 1
}

#######################################
# Command Execution Wrappers
#######################################

# Safe command execution with error handling
# Arguments: $1 - command, $2 - description, $3 - allow failure (optional, default=false)
safe_execute_command() {
    local command="$1"
    local description="$2"
    local allow_failure="${3:-false}"
    
    if [[ -z "$command" ]]; then
        handle_error "critical" "Command is required" "safe_execute_command"
        return 1
    fi
    
    local desc="${description:-$command}"
    push_error_context "command" "Executing: $desc"
    
    log_info "Executing command: $desc"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would execute: $command"
        pop_error_context
        return 0
    fi
    
    # Execute command and capture output
    local output
    local exit_code
    
    if output=$(eval "$command" 2>&1); then
        exit_code=0
        log_success "Command executed successfully: $desc"
        if [[ -n "$output" && "$VERBOSE" == "true" ]]; then
            log_debug "Command output: $output"
        fi
    else
        exit_code=$?
        
        if [[ "$allow_failure" == "true" ]]; then
            log_warn "Command failed but failure is allowed: $desc (exit code: $exit_code)"
            if [[ -n "$output" ]]; then
                log_debug "Command output: $output"
            fi
        else
            handle_error "critical" "Command failed: $desc (exit code: $exit_code)" "safe_execute_command"
            if [[ -n "$output" ]]; then
                log_error "Command output: $output"
            fi
            pop_error_context
            return $exit_code
        fi
    fi
    
    pop_error_context
    return $exit_code
}

# Safe command execution with timeout
# Arguments: $1 - timeout (seconds), $2 - command, $3 - description
safe_execute_with_timeout() {
    local timeout="$1"
    local command="$2"
    local description="$3"
    
    if [[ -z "$timeout" || -z "$command" ]]; then
        handle_error "critical" "Timeout and command are required" "safe_execute_with_timeout"
        return 1
    fi
    
    local desc="${description:-$command}"
    push_error_context "command_timeout" "Executing with timeout ($timeout s): $desc"
    
    log_info "Executing command with timeout ($timeout s): $desc"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would execute with timeout: $command"
        pop_error_context
        return 0
    fi
    
    # Execute command with timeout
    if timeout "$timeout" bash -c "$command"; then
        log_success "Command completed within timeout: $desc"
        pop_error_context
        return 0
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            handle_error "critical" "Command timed out after $timeout seconds: $desc" "safe_execute_with_timeout"
        else
            handle_error "critical" "Command failed: $desc (exit code: $exit_code)" "safe_execute_with_timeout"
        fi
        pop_error_context
        return $exit_code
    fi
}

#######################################
# Validation Wrappers
#######################################

# Safe validation with error handling
# Arguments: $1 - validation function, $2 - description, $3 - critical (optional, default=false)
safe_validate() {
    local validation_func="$1"
    local description="$2"
    local critical="${3:-false}"
    
    if [[ -z "$validation_func" ]]; then
        handle_error "validation" "Validation function is required" "safe_validate"
        return 1
    fi
    
    local desc="${description:-$validation_func}"
    push_error_context "validation" "Validating: $desc"
    
    log_info "Running validation: $desc"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would run validation: $validation_func"
        pop_error_context
        return 0
    fi
    
    # Execute validation function
    if "$validation_func"; then
        log_success "Validation passed: $desc"
        pop_error_context
        return 0
    else
        local error_msg="Validation failed: $desc"
        
        if [[ "$critical" == "true" ]]; then
            handle_validation_error "$validation_func" "$error_msg" "critical"
        else
            handle_validation_error "$validation_func" "$error_msg" "warning"
        fi
        
        pop_error_context
        return 1
    fi
}

#######################################
# Batch Operation Wrappers
#######################################

# Safe batch operation with error handling
# Arguments: $1 - operation function, $2 - description, $@ - items to process
safe_batch_operation() {
    local operation_func="$1"
    local description="$2"
    shift 2
    local items=("$@")
    
    if [[ -z "$operation_func" ]]; then
        handle_error "critical" "Operation function is required" "safe_batch_operation"
        return 1
    fi
    
    if [[ ${#items[@]} -eq 0 ]]; then
        handle_error "critical" "No items specified for batch operation" "safe_batch_operation"
        return 1
    fi
    
    local desc="${description:-batch operation}"
    push_error_context "batch" "Batch operation: $desc (${#items[@]} items)"
    
    log_info "Starting batch operation: $desc (${#items[@]} items)"
    
    local success_count=0
    local failed_count=0
    local failed_items=()
    
    for item in "${items[@]}"; do
        log_info "Processing item: $item"
        
        if "$operation_func" "$item"; then
            ((success_count++))
            log_success "Item processed successfully: $item"
        else
            ((failed_count++))
            failed_items+=("$item")
            log_error "Item processing failed: $item"
            
            # Check if we should continue or abort
            if [[ "$ERROR_RECOVERY_MODE" == "strict" ]]; then
                log_error "Aborting batch operation due to strict mode"
                pop_error_context
                return 1
            fi
        fi
    done
    
    # Report results
    log_info "Batch operation completed: $success_count successful, $failed_count failed"
    
    if [[ $failed_count -gt 0 ]]; then
        local error_msg="Batch operation had $failed_count failures: ${failed_items[*]}"
        handle_error "package" "$error_msg" "safe_batch_operation"
        pop_error_context
        return 1
    else
        log_success "All items processed successfully in batch operation"
        pop_error_context
        return 0
    fi
}

# Export functions for use in other modules
export -f safe_install_package
export -f safe_install_packages
export -f safe_copy_file
export -f safe_create_symlink
export -f safe_create_directory
export -f safe_enable_service
export -f safe_download_file
export -f safe_execute_command
export -f safe_execute_with_timeout
export -f safe_validate
export -f safe_batch_operation