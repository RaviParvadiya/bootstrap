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

declare -ga SELECTED_COMPONENTS=()
declare -ga ADDED_DEPENDENCIES=()
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
    done <<< "$components"
    
    log_success "Loaded ${#COMPONENTS[@]} components from metadata"
    return 0
}

# Display component selection menu
select_components() {
    load_component_metadata "$COMPONENT_METADATA_FILE" || { log_error "Failed to load component metadata"; return 1; }
    
    local options=() selected=() current=0
    
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
        echo "Use arrow keys to navigate, space to toggle, enter to confirm:"
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
            else
                echo "  $status $component - ${COMPONENTS[$component]}"
            fi
        done
        
        echo
        echo "Commands: [Space] Toggle | [Enter] Confirm | [q] Quit"
        
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
    
    resolve_dependencies && display_selection_summary
}

# Resolve component dependencies and track what was user-selected vs auto-added
resolve_dependencies() {
    local user_selected=("${SELECTED_COMPONENTS[@]}")  # Store original user selection
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
                # Only track as added dependency if not originally selected by user
                if [[ ! " ${user_selected[*]} " =~ " $dep " ]]; then
                    added_deps+=("$dep")
                    log_info "Added dependency: $dep (required by $component)"
                fi
            fi
        done
    done
    
    # Update selected components with resolved dependencies
    SELECTED_COMPONENTS=("${resolved[@]}")
    
    # Store the added dependencies for display in summary
    ADDED_DEPENDENCIES=("${added_deps[@]}")
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
    
    log_info "The following components will be installed:"
    
    # Show user-selected components
    echo
    echo "Selected by you:"
    for component in "${SELECTED_COMPONENTS[@]}"; do
        # Check if this was added as a dependency
        if [[ " ${ADDED_DEPENDENCIES[*]} " =~ " $component " ]]; then
            continue  # Skip dependencies, show them separately
        fi
        echo -e "  ${GREEN}✓${NC} $component - ${COMPONENTS[$component]}"
    done
    
    # Show automatically added dependencies
    if [[ ${#ADDED_DEPENDENCIES[@]} -gt 0 ]]; then
        echo
        echo "Added as dependencies:"
        for dep in "${ADDED_DEPENDENCIES[@]}"; do
            echo -e "  ${CYAN}+${NC} $dep - ${COMPONENTS[$dep]} ${YELLOW}(dependency)${NC}"
        done
    fi
    
    echo
    echo "Total components: ${#SELECTED_COMPONENTS[@]}"
    
    # Show estimated installation time
    local estimated_time=$((${#SELECTED_COMPONENTS[@]} * 5))
    
    echo "Estimated installation time: ${estimated_time} minutes"
    
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