#!/usr/bin/env bash

# Interactive component selection system
# Provides multi-select menus and dependency resolution

# Source required utilities
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"

# Global variables
declare -A COMPONENTS=()
declare -A COMPONENT_DEPS=()
declare -A COMPONENT_CONFLICTS=()
declare -A COMPONENT_OPTIONS=()
declare -A COMPONENT_PACKAGES=()
SELECTED_COMPONENTS=()
COMPONENT_METADATA_FILE="data/component-deps.json"

# Load component metadata from JSON file
load_component_metadata() {
    local metadata_file="$1"
    
    if [[ ! -f "$metadata_file" ]]; then
        log_error "Component metadata file not found: $metadata_file"
        return 1
    fi
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        log_error "jq is required for parsing component metadata"
        log_info "Please install jq: sudo pacman -S jq (Arch) or sudo apt install jq (Ubuntu)"
        return 1
    fi
    
    log_info "Loading component metadata from $metadata_file..."
    
    # Parse JSON and populate arrays
    local components
    components=$(jq -r '.components | keys[]' "$metadata_file" 2>/dev/null)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to parse component metadata JSON"
        return 1
    fi
    
    while IFS= read -r component; do
        [[ -z "$component" ]] && continue
        
        # Load component description
        local description
        description=$(jq -r ".components.\"$component\".description // \"No description available\"" "$metadata_file")
        COMPONENTS["$component"]="$description"
        
        # Load dependencies
        local deps
        deps=$(jq -r ".components.\"$component\".dependencies[]? // empty" "$metadata_file" | tr '\n' ' ')
        COMPONENT_DEPS["$component"]="${deps% }"  # Remove trailing space
        
        # Load conflicts
        local conflicts
        conflicts=$(jq -r ".components.\"$component\".conflicts[]? // empty" "$metadata_file" | tr '\n' ' ')
        COMPONENT_CONFLICTS["$component"]="${conflicts% }"  # Remove trailing space
        
        # Load options (if any)
        local options
        options=$(jq -r ".components.\"$component\".options[]? // empty" "$metadata_file" | tr '\n' ' ')
        COMPONENT_OPTIONS["$component"]="${options% }"  # Remove trailing space
        
        # Load packages for current distribution
        local distro
        distro=$(detect_distro)
        local packages
        packages=$(jq -r ".components.\"$component\".packages.\"$distro\"[]? // empty" "$metadata_file" | tr '\n' ' ')
        COMPONENT_PACKAGES["$component"]="${packages% }"  # Remove trailing space
        
    done <<< "$components"
    
    log_success "Loaded ${#COMPONENTS[@]} components from metadata"
    return 0
}

# Display component selection menu
select_components() {
    # Load component metadata first
    if ! load_component_metadata "$COMPONENT_METADATA_FILE"; then
        log_error "Failed to load component metadata"
        return 1
    fi
    
    log_section "Component Selection"
    
    echo "Select components to install (use space to toggle, enter to confirm, 'd' for details):"
    echo
    
    local options=()
    local selected=()
    
    # Build options array from loaded metadata
    for component in "${!COMPONENTS[@]}"; do
        options+=("$component")
        selected+=(false)
    done
    
    # Sort options for consistent display
    IFS=$'\n' options=($(sort <<<"${options[*]}"))
    unset IFS
    
    # Interactive selection
    local current=0
    local key
    local show_details=false
    
    while true; do
        # Clear screen and display menu
        clear
        echo "=== Component Selection ==="
        echo
        echo "Use arrow keys to navigate, space to toggle, 'd' for details, enter to confirm:"
        echo
        
        # Display options
        for i in "${!options[@]}"; do
            local component="${options[$i]}"
            local description="${COMPONENTS[$component]}"
            local status="[ ]"
            
            # Check if selected
            if [[ "${selected[$i]}" == "true" ]]; then
                status="[x]"
            fi
            
            # Highlight current option
            if [[ $i -eq $current ]]; then
                echo -e "${CYAN}> $status $component - $description${NC}"
                
                # Show component details if requested
                if [[ "$show_details" == "true" ]]; then
                    show_component_details "$component"
                fi
            else
                echo "  $status $component - $description"
            fi
        done
        
        echo
        echo "Commands: [Space] Toggle | [d] Details | [Enter] Confirm | [q] Quit"
        
        # Reset details flag
        show_details=false
        
        # Read key input
        read -rsn1 key
        
        case "$key" in
            $'\x1b')  # Escape sequence
                read -rsn2 key
                case "$key" in
                    '[A')  # Up arrow
                        ((current > 0)) && ((current--))
                        ;;
                    '[B')  # Down arrow
                        ((current < ${#options[@]} - 1)) && ((current++))
                        ;;
                esac
                ;;
            ' ')  # Space - toggle selection
                if [[ "${selected[$current]}" == "true" ]]; then
                    selected[$current]="false"
                else
                    selected[$current]="true"
                fi
                ;;
            'd'|'D')  # Show details
                show_details=true
                ;;
            '')  # Enter - confirm selection
                break
                ;;
            'q'|'Q')  # Quit
                log_info "Installation cancelled by user"
                exit 0
                ;;
        esac
    done
    
    # Build selected components list
    SELECTED_COMPONENTS=()
    for i in "${!options[@]}"; do
        if [[ "${selected[$i]}" == "true" ]]; then
            SELECTED_COMPONENTS+=("${options[$i]}")
        fi
    done
    
    # Check for conflicts before resolving dependencies
    if ! check_conflicts; then
        return 1
    fi
    
    # Resolve dependencies
    resolve_dependencies
    
    # Display final selection
    display_selection_summary
}

# Show detailed information about a component
show_component_details() {
    local component="$1"
    
    echo
    echo -e "${YELLOW}--- Component Details: $component ---${NC}"
    
    # Description
    echo "Description: ${COMPONENTS[$component]}"
    
    # Dependencies
    local deps="${COMPONENT_DEPS[$component]:-}"
    if [[ -n "$deps" ]]; then
        echo "Dependencies: $deps"
    else
        echo "Dependencies: None"
    fi
    
    # Conflicts
    local conflicts="${COMPONENT_CONFLICTS[$component]:-}"
    if [[ -n "$conflicts" ]]; then
        echo -e "${RED}Conflicts with: $conflicts${NC}"
    fi
    
    # Options (if any)
    local options="${COMPONENT_OPTIONS[$component]:-}"
    if [[ -n "$options" ]]; then
        echo "Available options: $options"
    fi
    
    # Packages
    local packages="${COMPONENT_PACKAGES[$component]:-}"
    if [[ -n "$packages" ]]; then
        echo "Packages: $packages"
    else
        echo "Packages: None (configuration only)"
    fi
    
    echo -e "${YELLOW}--- End Details ---${NC}"
    echo
}

# Resolve component dependencies
resolve_dependencies() {
    local resolved=()
    local to_process=("${SELECTED_COMPONENTS[@]}")
    local added_deps=()
    
    log_info "Resolving component dependencies..."
    
    # Process dependencies recursively
    while [[ ${#to_process[@]} -gt 0 ]]; do
        local component="${to_process[0]}"
        to_process=("${to_process[@]:1}")  # Remove first element
        
        # Skip if already resolved
        if [[ " ${resolved[*]} " =~ " $component " ]]; then
            continue
        fi
        
        # Add component to resolved list
        resolved+=("$component")
        
        # Add dependencies to processing queue
        local deps="${COMPONENT_DEPS[$component]:-}"
        if [[ -n "$deps" ]]; then
            for dep in $deps; do
                if [[ ! " ${resolved[*]} " =~ " $dep " ]] && [[ ! " ${to_process[*]} " =~ " $dep " ]]; then
                    to_process+=("$dep")
                    added_deps+=("$dep")
                    log_info "Added dependency: $dep (required by $component)"
                fi
            done
        fi
    done
    
    # Update selected components with resolved dependencies
    SELECTED_COMPONENTS=("${resolved[@]}")
    
    # Notify user of added dependencies
    if [[ ${#added_deps[@]} -gt 0 ]]; then
        echo
        log_info "The following dependencies were automatically added:"
        for dep in "${added_deps[@]}"; do
            echo "  - $dep: ${COMPONENTS[$dep]}"
        done
        echo
    fi
}

# Display selection summary
display_selection_summary() {
    clear
    log_section "Installation Summary"
    
    if [[ ${#SELECTED_COMPONENTS[@]} -eq 0 ]]; then
        log_warn "No components selected for installation"
        if ask_yes_no "Continue anyway?"; then
            return 0
        else
            log_info "Installation cancelled"
            exit 0
        fi
    fi
    
    echo "The following components will be installed:"
    echo
    
    # Calculate total packages
    local total_packages=0
    local distro
    distro=$(detect_distro)
    
    for component in "${SELECTED_COMPONENTS[@]}"; do
        local description="${COMPONENTS[$component]}"
        local packages="${COMPONENT_PACKAGES[$component]:-}"
        local package_count=0
        
        if [[ -n "$packages" ]]; then
            package_count=$(echo "$packages" | wc -w)
            total_packages=$((total_packages + package_count))
        fi
        
        echo -e "  ${GREEN}✓${NC} $component - $description"
        
        # Show package count if any
        if [[ $package_count -gt 0 ]]; then
            echo "    Packages ($package_count): $packages"
        fi
        
        # Show options if any
        local options="${COMPONENT_OPTIONS[$component]:-}"
        if [[ -n "$options" ]]; then
            echo "    Available options: $options"
        fi
    done
    
    echo
    echo "Total components: ${#SELECTED_COMPONENTS[@]}"
    echo "Total packages: $total_packages"
    
    # Show estimated installation time and space
    local estimated_time=$((${#SELECTED_COMPONENTS[@]} * 3 + total_packages / 10))
    local estimated_space=$((total_packages * 50 + ${#SELECTED_COMPONENTS[@]} * 20))
    
    echo "Estimated installation time: ${estimated_time} minutes"
    echo "Estimated disk space required: ${estimated_space} MB"
    echo
    
    # Show any warnings
    show_installation_warnings
    
    if ! ask_yes_no "Proceed with installation?" "y"; then
        log_info "Installation cancelled by user"
        exit 0
    fi
}

# Show installation warnings
show_installation_warnings() {
    local warnings=()
    
    # Check for hardware component
    if [[ " ${SELECTED_COMPONENTS[*]} " =~ " hardware " ]]; then
        warnings+=("Hardware configuration will be applied - ensure you're on the correct system")
    fi
    
    # Check for window manager
    if [[ " ${SELECTED_COMPONENTS[*]} " =~ " wm " ]]; then
        warnings+=("Window manager installation may require logout/reboot to take effect")
    fi
    
    # Check for development tools
    if [[ " ${SELECTED_COMPONENTS[*]} " =~ " dev-tools " ]]; then
        warnings+=("Development tools may require additional configuration after installation")
    fi
    
    if [[ ${#warnings[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Warnings:${NC}"
        for warning in "${warnings[@]}"; do
            echo -e "  ${YELLOW}⚠${NC} $warning"
        done
        echo
    fi
}

# List all available components
list_all_components() {
    # Load component metadata first
    if ! load_component_metadata "$COMPONENT_METADATA_FILE"; then
        log_error "Failed to load component metadata"
        return 1
    fi
    
    log_section "Available Components"
    
    echo "The following components are available for installation:"
    echo
    
    for component in $(printf '%s\n' "${!COMPONENTS[@]}" | sort); do
        local description="${COMPONENTS[$component]}"
        local deps="${COMPONENT_DEPS[$component]:-}"
        local conflicts="${COMPONENT_CONFLICTS[$component]:-}"
        local options="${COMPONENT_OPTIONS[$component]:-}"
        local packages="${COMPONENT_PACKAGES[$component]:-}"
        
        echo -e "${BLUE}$component${NC} - $description"
        
        if [[ -n "$deps" ]]; then
            echo "  Dependencies: $deps"
        fi
        
        if [[ -n "$conflicts" ]]; then
            echo -e "  ${RED}Conflicts: $conflicts${NC}"
        fi
        
        if [[ -n "$options" ]]; then
            echo "  Options: $options"
        fi
        
        if [[ -n "$packages" ]]; then
            local package_count=$(echo "$packages" | wc -w)
            echo "  Packages ($package_count): $packages"
        fi
        
        echo
    done
}

# Validate component selection
validate_components() {
    # Load component metadata if not already loaded
    if [[ ${#COMPONENTS[@]} -eq 0 ]]; then
        if ! load_component_metadata "$COMPONENT_METADATA_FILE"; then
            log_error "Failed to load component metadata for validation"
            return 1
        fi
    fi
    
    local invalid_components=()
    
    for component in "${SELECTED_COMPONENTS[@]}"; do
        if [[ ! -v "COMPONENTS[$component]" ]]; then
            invalid_components+=("$component")
        fi
    done
    
    if [[ ${#invalid_components[@]} -gt 0 ]]; then
        log_error "Invalid components specified: ${invalid_components[*]}"
        log_info "Available components:"
        for component in $(printf '%s\n' "${!COMPONENTS[@]}" | sort); do
            echo "  - $component"
        done
        return 1
    fi
    
    return 0
}

# Select options for components that have multiple choices
select_component_options() {
    local component="$1"
    local options="${COMPONENT_OPTIONS[$component]:-}"
    
    if [[ -z "$options" ]]; then
        return 0  # No options to select
    fi
    
    echo
    log_section "Component Options: $component"
    
    local options_array=($options)
    local selected_option=""
    
    if [[ ${#options_array[@]} -eq 1 ]]; then
        # Only one option, auto-select it
        selected_option="${options_array[0]}"
        log_info "Auto-selected: $selected_option"
    else
        # Multiple options, let user choose
        echo "Select an option for $component:"
        echo
        
        for i in "${!options_array[@]}"; do
            echo "  $((i+1)). ${options_array[$i]}"
        done
        
        echo
        while true; do
            read -p "Enter your choice (1-${#options_array[@]}): " choice
            
            if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#options_array[@]} ]]; then
                selected_option="${options_array[$((choice-1))]}"
                break
            else
                echo "Invalid choice. Please enter a number between 1 and ${#options_array[@]}."
            fi
        done
    fi
    
    log_success "Selected $selected_option for $component"
    
    # Store the selection (could be used later for installation)
    export "${component^^}_SELECTED_OPTION=$selected_option"
}

# Process all component options after selection
process_component_options() {
    log_info "Processing component options..."
    
    for component in "${SELECTED_COMPONENTS[@]}"; do
        select_component_options "$component"
    done
}

# Initialize menu system
init_menu_system() {
    # Set default metadata file path if not set
    if [[ -z "$COMPONENT_METADATA_FILE" ]]; then
        COMPONENT_METADATA_FILE="data/component-deps.json"
    fi
    
    # Load component metadata
    if ! load_component_metadata "$COMPONENT_METADATA_FILE"; then
        log_error "Failed to initialize menu system"
        return 1
    fi
    
    log_success "Menu system initialized with ${#COMPONENTS[@]} components"
    return 0
}

# Main menu interface function
run_interactive_menu() {
    log_section "Modular Install Framework"
    
    # Initialize the menu system
    if ! init_menu_system; then
        return 1
    fi
    
    # Run component selection
    if ! select_components; then
        return 1
    fi
    
    # Process component options
    process_component_options
    
    log_success "Component selection completed"
    log_info "Selected components: ${SELECTED_COMPONENTS[*]}"
    
    return 0
}

# Check for component conflicts
check_conflicts() {
    local conflicts_found=()
    local conflict_messages=()
    
    log_info "Checking for component conflicts..."
    
    # Check each selected component for conflicts
    for component in "${SELECTED_COMPONENTS[@]}"; do
        local component_conflicts="${COMPONENT_CONFLICTS[$component]:-}"
        
        if [[ -n "$component_conflicts" ]]; then
            # Check if any conflicting components are also selected
            for conflict in $component_conflicts; do
                if [[ " ${SELECTED_COMPONENTS[*]} " =~ " $conflict " ]]; then
                    conflicts_found+=("$component <-> $conflict")
                    conflict_messages+=("$component conflicts with $conflict")
                fi
            done
        fi
    done
    
    # Handle conflicts if found
    if [[ ${#conflicts_found[@]} -gt 0 ]]; then
        echo
        log_error "Component conflicts detected:"
        
        for message in "${conflict_messages[@]}"; do
            echo -e "  ${RED}✗${NC} $message"
        done
        
        echo
        echo "Please resolve conflicts by deselecting one of the conflicting components."
        
        if ask_yes_no "Return to component selection?"; then
            # Recursive call to re-select components
            select_components
            return $?
        else
            log_info "Installation cancelled due to conflicts"
            return 1
        fi
    fi
    
    return 0
}

# Get selected components (for external use)
get_selected_components() {
    printf '%s\n' "${SELECTED_COMPONENTS[@]}"
}

# Get component packages for a specific component
get_component_packages() {
    local component="$1"
    echo "${COMPONENT_PACKAGES[$component]:-}"
}

# Check if a component is selected
is_component_selected() {
    local component="$1"
    [[ " ${SELECTED_COMPONENTS[*]} " =~ " $component " ]]
}

# Add component programmatically (for scripted installations)
add_component() {
    local component="$1"
    
    if [[ -v "COMPONENTS[$component]" ]]; then
        if [[ ! " ${SELECTED_COMPONENTS[*]} " =~ " $component " ]]; then
            SELECTED_COMPONENTS+=("$component")
            log_info "Added component: $component"
        fi
    else
        log_error "Unknown component: $component"
        return 1
    fi
}

# Remove component programmatically
remove_component() {
    local component="$1"
    local new_selection=()
    
    for selected in "${SELECTED_COMPONENTS[@]}"; do
        if [[ "$selected" != "$component" ]]; then
            new_selection+=("$selected")
        fi
    done
    
    SELECTED_COMPONENTS=("${new_selection[@]}")
    log_info "Removed component: $component"
}

# Export selected components for use by other scripts
export_selection() {
    local export_file="${1:-/tmp/selected_components.txt}"
    
    if [[ ${#SELECTED_COMPONENTS[@]} -eq 0 ]]; then
        log_warn "No components selected to export"
        return 1
    fi
    
    {
        echo "# Selected components - $(date)"
        echo "# Generated by modular install framework"
        echo
        for component in "${SELECTED_COMPONENTS[@]}"; do
            echo "$component"
        done
    } > "$export_file"
    
    log_success "Selected components exported to: $export_file"
}

# Import component selection from file
import_selection() {
    local import_file="$1"
    
    if [[ ! -f "$import_file" ]]; then
        log_error "Import file not found: $import_file"
        return 1
    fi
    
    # Initialize menu system first
    if ! init_menu_system; then
        return 1
    fi
    
    SELECTED_COMPONENTS=()
    
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue
        
        # Validate component exists
        if [[ -v "COMPONENTS[$line]" ]]; then
            SELECTED_COMPONENTS+=("$line")
            log_info "Imported component: $line"
        else
            log_warn "Skipping unknown component: $line"
        fi
    done < "$import_file"
    
    # Resolve dependencies for imported selection
    resolve_dependencies
    
    log_success "Imported ${#SELECTED_COMPONENTS[@]} components from $import_file"
}

# Quick selection presets
select_preset() {
    local preset="$1"
    
    # Initialize menu system first
    if ! init_menu_system; then
        return 1
    fi
    
    case "$preset" in
        "minimal")
            SELECTED_COMPONENTS=("terminal" "shell")
            log_info "Selected minimal preset: terminal + shell"
            ;;
        "desktop")
            SELECTED_COMPONENTS=("terminal" "shell" "wm")
            log_info "Selected desktop preset: terminal + shell + window manager"
            ;;
        "developer")
            SELECTED_COMPONENTS=("terminal" "shell" "editor" "dev-tools")
            log_info "Selected developer preset: terminal + shell + editor + dev-tools"
            ;;
        "full")
            SELECTED_COMPONENTS=("${!COMPONENTS[@]}")
            log_info "Selected full preset: all components"
            ;;
        *)
            log_error "Unknown preset: $preset"
            log_info "Available presets: minimal, desktop, developer, full"
            return 1
            ;;
    esac
    
    # Resolve dependencies
    resolve_dependencies
    
    # Display selection
    display_selection_summary
}

# Print usage information
print_menu_usage() {
    cat << EOF
Modular Install Framework - Component Selection

Usage:
  Interactive mode:
    source core/menu.sh && run_interactive_menu
  
  Preset selection:
    source core/menu.sh && select_preset <preset>
  
  Programmatic selection:
    source core/menu.sh && init_menu_system
    add_component "terminal"
    add_component "shell"
    resolve_dependencies
    display_selection_summary

Available presets:
  minimal   - Terminal and shell only
  desktop   - Minimal + window manager
  developer - Terminal, shell, editor, dev-tools
  full      - All available components

Functions:
  init_menu_system()           - Initialize the menu system
  select_components()          - Interactive component selection
  list_all_components()        - List all available components
  validate_components()        - Validate current selection
  resolve_dependencies()       - Resolve component dependencies
  check_conflicts()            - Check for component conflicts
  display_selection_summary()  - Show installation summary
  export_selection()           - Export selection to file
  import_selection()           - Import selection from file

Environment variables:
  COMPONENT_METADATA_FILE      - Path to component metadata JSON
  DRY_RUN                      - Enable dry-run mode
  VERBOSE                      - Enable verbose logging

EOF
}