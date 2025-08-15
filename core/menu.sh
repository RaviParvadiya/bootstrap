#!/bin/bash

# Interactive component selection system
# Provides multi-select menus and dependency resolution

# Available components with descriptions
declare -A COMPONENTS=(
    ["terminal"]="Terminal emulators (Alacritty, Kitty)"
    ["shell"]="Shell configuration (Zsh, Starship)"
    ["editor"]="Text editors (Neovim, VS Code)"
    ["wm"]="Window manager (Hyprland, Waybar, Wofi)"
    ["dev-tools"]="Development tools (Git, Docker, Languages)"
    ["hardware"]="Hardware-specific configurations (NVIDIA, ASUS)"
)

# Component dependencies
declare -A COMPONENT_DEPS=(
    ["wm"]="terminal shell"
    ["dev-tools"]="editor"
    ["hardware"]=""
)

# Selected components array
SELECTED_COMPONENTS=()

# Display component selection menu
select_components() {
    log_section "Component Selection"
    
    echo "Select components to install (use space to toggle, enter to confirm):"
    echo
    
    local options=()
    local selected=()
    
    # Build options array
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
    
    while true; do
        # Clear screen and display menu
        clear
        echo "=== Component Selection ==="
        echo
        echo "Use arrow keys to navigate, space to toggle, enter to confirm:"
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
            else
                echo "  $status $component - $description"
            fi
        done
        
        echo
        echo "Dependencies will be automatically resolved."
        
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
    
    # Resolve dependencies
    resolve_dependencies
    
    # Display final selection
    display_selection_summary
}

# Resolve component dependencies
resolve_dependencies() {
    local resolved=()
    local to_process=("${SELECTED_COMPONENTS[@]}")
    
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
                if [[ ! " ${resolved[*]} " =~ " $dep " ]]; then
                    to_process+=("$dep")
                fi
            done
        fi
    done
    
    # Update selected components with resolved dependencies
    SELECTED_COMPONENTS=("${resolved[@]}")
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
    
    for component in "${SELECTED_COMPONENTS[@]}"; do
        local description="${COMPONENTS[$component]}"
        echo -e "  ${GREEN}✓${NC} $component - $description"
    done
    
    echo
    
    # Show estimated installation time and space
    local estimated_time=$((${#SELECTED_COMPONENTS[@]} * 5))
    local estimated_space=$((${#SELECTED_COMPONENTS[@]} * 100))
    
    echo "Estimated installation time: ${estimated_time} minutes"
    echo "Estimated disk space required: ${estimated_space} MB"
    echo
    
    if ! ask_yes_no "Proceed with installation?" "y"; then
        log_info "Installation cancelled by user"
        exit 0
    fi
}

# List all available components
list_all_components() {
    log_section "Available Components"
    
    echo "The following components are available for installation:"
    echo
    
    for component in $(printf '%s\n' "${!COMPONENTS[@]}" | sort); do
        local description="${COMPONENTS[$component]}"
        local deps="${COMPONENT_DEPS[$component]:-}"
        
        echo -e "${BLUE}$component${NC} - $description"
        if [[ -n "$deps" ]]; then
            echo "  Dependencies: $deps"
        fi
        echo
    done
}

# Validate component selection
validate_components() {
    local invalid_components=()
    
    for component in "${SELECTED_COMPONENTS[@]}"; do
        if [[ ! -v "COMPONENTS[$component]" ]]; then
            invalid_components+=("$component")
        fi
    done
    
    if [[ ${#invalid_components[@]} -gt 0 ]]; then
        log_error "Invalid components specified: ${invalid_components[*]}"
        log_info "Available components:"
        for component in "${!COMPONENTS[@]}"; do
            echo "  - $component"
        done
        return 1
    fi
    
    return 0
}

# Check for component conflicts
check_conflicts() {
    # Define conflicting components
    local -A conflicts=(
        ["terminal"]="Multiple terminal emulators selected"
    )
    
    # This is a placeholder for future conflict detection
    # Currently no conflicts defined
    return 0
}