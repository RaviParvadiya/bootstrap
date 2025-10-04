#!/usr/bin/env bash

# Interactive component selection system
# Provides multi-select menus and dependency resolution

# Initialize all project paths
source "$(dirname "${BASH_SOURCE[0]}")/../core/init-paths.sh"

# Source required utilities
source "$CORE_DIR/common.sh"
source "$CORE_DIR/logger.sh"

# Global variables
# NOTE: use -g so these remain global when menu.sh is sourced via install.sh
declare -gA COMPONENTS=()
declare -gA COMPONENT_DEPS=()
declare -gA COMPONENT_CONFLICTS=()
declare -gA COMPONENT_OPTIONS=()
declare -gA COMPONENT_PACKAGES=()
declare -ga SELECTED_COMPONENTS=()
declare -g COMPONENT_METADATA_FILE="data/component-deps.json"

# Load component metadata from JSON file
load_component_metadata() {
    local metadata_file="$1"
    
    [[ ! -f "$metadata_file" ]] && { log_error "Component metadata file not found: $metadata_file"; return 1; }
    
    if ! command -v jq &> /dev/null; then
        log_error "jq is required for parsing component metadata"
        log_info "Please install jq: sudo pacman -S jq (Arch) or sudo apt install jq (Ubuntu)"
        return 1
    fi
    
    log_info "Loading component metadata from $metadata_file..."
    
    local components distro
    components=$(jq -r '.components | keys[]' "$metadata_file" 2>/dev/null) || {
        log_error "Failed to parse component metadata JSON"
        return 1
    }
    
    distro=$(detect_distro)
    
    while IFS= read -r component; do
        [[ -z "$component" ]] && continue
        
        # Load component description
        COMPONENTS["$component"]=$(jq -r ".components.\"$component\".description // \"No description available\"" "$metadata_file")
        
        # Load dependencies
        COMPONENT_DEPS["$component"]=$(jq -r ".components.\"$component\".dependencies[]? // empty" "$metadata_file" | tr '\n' ' ' | sed 's/ $//')
        
        # Load conflicts
        COMPONENT_CONFLICTS["$component"]=$(jq -r ".components.\"$component\".conflicts[]? // empty" "$metadata_file" | tr '\n' ' ' | sed 's/ $//')
        
        # Load options (if any)
        COMPONENT_OPTIONS["$component"]=$(jq -r ".components.\"$component\".options[]? // empty" "$metadata_file" | tr '\n' ' ' | sed 's/ $//')
        
        # Load packages for current distribution
        COMPONENT_PACKAGES["$component"]=$(jq -r ".components.\"$component\".packages.\"$distro\"[]? // empty" "$metadata_file" | tr '\n' ' ' | sed 's/ $//')
        
    done <<< "$components"
    
    log_success "Loaded ${#COMPONENTS[@]} components from metadata"
    return 0
}

# Display component selection menu
select_components() {
    load_component_metadata "$COMPONENT_METADATA_FILE" || { log_error "Failed to load component metadata"; return 1; }
    
    log_section "Component Selection"
    echo "Select components to install (use space to toggle, enter to confirm, 'd' for details):"
    echo
    
    local options=() selected=() current=0 show_details=false
    
    # Build options array from loaded metadata
    for component in "${!COMPONENTS[@]}"; do
        options+=("$component")
        selected+=(false)
    done
    
    # Sort options for consistent display
    IFS=$'\n' options=($(sort <<<"${options[*]}"))
    unset IFS
    
    # Interactive selection
    while true; do
        # Clear screen and display menu
        clear
        echo "=== Component Selection ==="
        echo "Use arrow keys to navigate, space to toggle, 'd' for details, enter to confirm:"
        echo
        
        # Display options
        for i in "${!options[@]}"; do
            local component="${options[$i]}"
            local status="[ ]"
            
            # Check if selected
            [[ "${selected[$i]}" == "true" ]] && status="[x]"
            
            # Highlight current option
            if [[ $i -eq $current ]]; then
                echo -e "${CYAN}> $status $component - ${COMPONENTS[$component]}${NC}"
                
                # Show component details if requested
                [[ "$show_details" == "true" ]] && show_component_details "$component"
            else
                echo "  $status $component - ${COMPONENTS[$component]}"
            fi
        done
        
        echo
        echo "Commands: [Space] Toggle | [d] Details | [Enter] Confirm | [q] Quit"
        
        # Reset details flag
        show_details=false
        
        # Read key input
        # Disable IFS splitting here to capture space/Enter keys correctly
        IFS= read -rsn1 key
        case "$key" in
            $'\x1b')  # Escape sequence
                IFS= read -rsn2 key
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
                selected[$current]=$([[ "${selected[$current]}" == "true" ]] && echo "false" || echo "true")
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
        [[ "${selected[$i]}" == "true" ]] && SELECTED_COMPONENTS+=("${options[$i]}")
    done
    
    check_conflicts && resolve_dependencies && display_selection_summary
}

# Show detailed information about a component
show_component_details() {
    local component="$1"
    
    echo
    echo -e "${YELLOW}--- Component Details: $component ---${NC}"
    echo "Description: ${COMPONENTS[$component]}"
    echo "Dependencies: ${COMPONENT_DEPS[$component]:-None}"
    
    local conflicts="${COMPONENT_CONFLICTS[$component]:-}"
    [[ -n "$conflicts" ]] && echo -e "${RED}Conflicts with: $conflicts${NC}"
    
    local options="${COMPONENT_OPTIONS[$component]:-}"
    [[ -n "$options" ]] && echo "Available options: $options"
    
    local packages="${COMPONENT_PACKAGES[$component]:-}"
    echo "Packages: ${packages:-None (configuration only)}"
    
    echo -e "${YELLOW}--- End Details ---${NC}"
    echo
}

# Resolve component dependencies
resolve_dependencies() {
    local resolved=() to_process=("${SELECTED_COMPONENTS[@]}") added_deps=()
    
    log_info "Resolving component dependencies..."
    
    # Process dependencies recursively
    while [[ ${#to_process[@]} -gt 0 ]]; do
        local component="${to_process[0]}"
        to_process=("${to_process[@]:1}")  # Remove first element
        
        # Skip if already resolved
        [[ " ${resolved[*]} " =~ " $component " ]] && continue
        
        # Add component to resolved list
        resolved+=("$component")
        
        # Add dependencies to processing queue
        local deps="${COMPONENT_DEPS[$component]:-}"
        [[ -n "$deps" ]] && for dep in $deps; do
            if [[ ! " ${resolved[*]} " =~ " $dep " ]] && [[ ! " ${to_process[*]} " =~ " $dep " ]]; then
                to_process+=("$dep")
                added_deps+=("$dep")
                log_info "Added dependency: $dep (required by $component)"
            fi
        done
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
        ask_yes_no "Continue anyway?" || { log_info "Installation cancelled"; exit 0; }
        return 0
    fi
    
    echo "The following components will be installed:"
    echo
    
    # Calculate total packages
    local total_packages=0
    
    for component in "${SELECTED_COMPONENTS[@]}"; do
        local packages="${COMPONENT_PACKAGES[$component]:-}"
        local package_count=0
        
        if [[ -n "$packages" ]]; then
            package_count=$(echo "$packages" | wc -w)
            total_packages=$((total_packages + package_count))
        fi
        
        echo -e "  ${GREEN}✓${NC} $component - ${COMPONENTS[$component]}"
        
        # Show package count if any
        [[ $package_count -gt 0 ]] && echo "    Packages ($package_count): $packages"
        
        # Show options if any
        local options="${COMPONENT_OPTIONS[$component]:-}"
        [[ -n "$options" ]] && echo "    Available options: $options"
    done
    
    echo
    echo "Total components: ${#SELECTED_COMPONENTS[@]}"
    echo "Total packages: $total_packages"
    
    # Show estimated installation time and space
    local estimated_time=$((${#SELECTED_COMPONENTS[@]} * 3 + total_packages / 10))
    local estimated_space=$((total_packages * 50 + ${#SELECTED_COMPONENTS[@]} * 20))
    
    echo "Estimated installation time: ${estimated_time} minutes"
    echo "Estimated disk space required: ${estimated_space} MB"
    
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
    local selected=" ${SELECTED_COMPONENTS[*]} "
    
    [[ "$selected" =~ " hardware " ]] && warnings+=("Hardware configuration will be applied - ensure you're on the correct system")
    [[ "$selected" =~ " wm " ]] && warnings+=("Window manager installation may require logout/reboot to take effect")
    [[ "$selected" =~ " dev-tools " ]] && warnings+=("Development tools may require additional configuration after installation")
    
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
    load_component_metadata "$COMPONENT_METADATA_FILE" || { log_error "Failed to load component metadata"; return 1; }
    
    log_section "Available Components"
    echo "The following components are available for installation:"
    echo
    
    for component in $(printf '%s\n' "${!COMPONENTS[@]}" | sort); do
        echo -e "${BLUE}$component${NC} - ${COMPONENTS[$component]}"
        
        local deps="${COMPONENT_DEPS[$component]:-}"
        [[ -n "$deps" ]] && echo "  Dependencies: $deps"
        
        local conflicts="${COMPONENT_CONFLICTS[$component]:-}"
        [[ -n "$conflicts" ]] && echo -e "  ${RED}Conflicts: $conflicts${NC}"
        
        local options="${COMPONENT_OPTIONS[$component]:-}"
        [[ -n "$options" ]] && echo "  Options: $options"
        
        local packages="${COMPONENT_PACKAGES[$component]:-}"
        [[ -n "$packages" ]] && echo "  Packages ($(echo "$packages" | wc -w)): $packages"
        
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
    local conflict_messages=()
    
    log_info "Checking for component conflicts..."
    
    # Check each selected component for conflicts
    for component in "${SELECTED_COMPONENTS[@]}"; do
        local component_conflicts="${COMPONENT_CONFLICTS[$component]:-}"
        
        if [[ -n "$component_conflicts" ]]; then
            # Check if any conflicting components are also selected
            for conflict in $component_conflicts; do
                [[ " ${SELECTED_COMPONENTS[*]} " =~ " $conflict " ]] && conflict_messages+=("$component conflicts with $conflict")
            done
        fi
    done
    
    # Handle conflicts if found
    if [[ ${#conflict_messages[@]} -gt 0 ]]; then
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
    echo "${COMPONENT_PACKAGES[$1]:-}"
}

# Check if a component is selected
is_component_selected() {
    [[ " ${SELECTED_COMPONENTS[*]} " =~ " $1 " ]]
}

# Add component programmatically (for scripted installations)
add_component() {
    local component="$1"
    
    if [[ -v "COMPONENTS[$component]" ]]; then
        [[ ! " ${SELECTED_COMPONENTS[*]} " =~ " $component " ]] && {
            SELECTED_COMPONENTS+=("$component")
            log_info "Added component: $component"
        }
    else
        log_error "Unknown component: $component"
        return 1
    fi
}

# Remove component programmatically
remove_component() {
    local component="$1" new_selection=()
    
    for selected in "${SELECTED_COMPONENTS[@]}"; do
        [[ "$selected" != "$component" ]] && new_selection+=("$selected")
    done
    
    SELECTED_COMPONENTS=("${new_selection[@]}")
    log_info "Removed component: $component"
}

# Export selected components for use by other scripts
export_selection() {
    local export_file="${1:-/tmp/selected_components.txt}"
    
    [[ ${#SELECTED_COMPONENTS[@]} -eq 0 ]] && { log_warn "No components selected to export"; return 1; }
    
    {
        echo "# Selected components - $(date)"
        echo "# Generated by modular install framework"
        echo
        printf '%s\n' "${SELECTED_COMPONENTS[@]}"
    } > "$export_file"
    
    log_success "Selected components exported to: $export_file"
}

# Import component selection from file
import_selection() {
    local import_file="$1"
    
    [[ ! -f "$import_file" ]] && { log_error "Import file not found: $import_file"; return 1; }
    
    init_menu_system || return 1
    
    SELECTED_COMPONENTS=()
    
    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        
        if [[ -v "COMPONENTS[$line]" ]]; then
            SELECTED_COMPONENTS+=("$line")
            log_info "Imported component: $line"
        else
            log_warn "Skipping unknown component: $line"
        fi
    done < "$import_file"
    
    resolve_dependencies
    log_success "Imported ${#SELECTED_COMPONENTS[@]} components from $import_file"
}

# Quick selection presets
select_preset() {
    local preset="$1"
    
    init_menu_system || return 1
    
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
    
    resolve_dependencies
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

EOF
}