#!/bin/bash

# ASUS TUF specific configurations
# Handles ASUS TUF Dash F15 specific tweaks and optimizations

# Configure ASUS TUF specific settings
configure_asus_tuf() {
    log_info "Configuring ASUS TUF specific settings..."
    
    # Install ASUS utilities
    install_asus_utilities
    
    # Configure power management
    configure_asus_power_management
    
    # Configure keyboard and function keys
    configure_asus_keyboard
    
    # Configure thermal management
    configure_asus_thermal
    
    log_success "ASUS TUF configuration completed"
}

# Install ASUS-specific utilities
install_asus_utilities() {
    log_info "Installing ASUS utilities..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install ASUS utilities"
        return 0
    fi
    
    # Install from AUR
    local asus_packages=(
        "asusctl"
        "supergfxctl"
        "rog-control-center"
    )
    
    if command_exists yay; then
        yay -S --noconfirm "${asus_packages[@]}"
    else
        log_warn "AUR helper not available, skipping ASUS utilities"
        return 1
    fi
    
    log_success "ASUS utilities installed"
}

# Configure power management for ASUS TUF
configure_asus_power_management() {
    log_info "Configuring ASUS power management..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would configure ASUS power management"
        return 0
    fi
    
    # Configure TLP for better battery life
    install_pacman_packages "tlp" "tlp-rdw"
    
    # Create TLP configuration for ASUS TUF
    sudo tee /etc/tlp.d/01-asus-tuf.conf > /dev/null << 'EOF'
# ASUS TUF specific TLP configuration

# CPU scaling governor
CPU_SCALING_GOVERNOR_ON_AC=performance
CPU_SCALING_GOVERNOR_ON_BAT=powersave

# CPU energy performance policy
CPU_ENERGY_PERF_POLICY_ON_AC=performance
CPU_ENERGY_PERF_POLICY_ON_BAT=power

# CPU boost
CPU_BOOST_ON_AC=1
CPU_BOOST_ON_BAT=0

# Platform profile
PLATFORM_PROFILE_ON_AC=performance
PLATFORM_PROFILE_ON_BAT=low-power

# Runtime power management
RUNTIME_PM_ON_AC=on
RUNTIME_PM_ON_BAT=auto

# USB autosuspend
USB_AUTOSUSPEND=1

# WiFi power saving
WIFI_PWR_ON_AC=off
WIFI_PWR_ON_BAT=on
EOF
    
    log_info "TLP service available but not auto-started"
    log_info "Enable with: sudo systemctl enable tlp"
    
    log_success "ASUS power management configured"
}

# Configure ASUS keyboard and function keys
configure_asus_keyboard() {
    log_info "Configuring ASUS keyboard settings..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would configure ASUS keyboard"
        return 0
    fi
    
    # Configure keyboard backlight
    sudo tee /etc/udev/rules.d/99-asus-keyboard.rules > /dev/null << 'EOF'
# ASUS keyboard backlight permissions
SUBSYSTEM=="leds", KERNEL=="asus::kbd_backlight", ACTION=="add", RUN+="/bin/chmod 666 /sys/class/leds/asus::kbd_backlight/brightness"
EOF
    
    # Configure function key behavior
    echo 'options asus_wmi fnlock_default=0' | sudo tee /etc/modprobe.d/asus-wmi.conf
    
    log_success "ASUS keyboard configured"
}

# Configure thermal management
configure_asus_thermal() {
    log_info "Configuring ASUS thermal management..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would configure ASUS thermal management"
        return 0
    fi
    
    # Install thermal monitoring tools
    install_pacman_packages "lm_sensors" "thermald"
    
    # Configure thermald for ASUS
    sudo tee /etc/thermald/thermal-conf.xml > /dev/null << 'EOF'
<?xml version="1.0"?>
<ThermalConfiguration>
  <Platform>
    <Name>ASUS TUF Gaming</Name>
    <ProductName>*TUF*</ProductName>
    <Preference>QUIET</Preference>
    <ThermalZones>
      <ThermalZone>
        <Type>cpu</Type>
        <TripPoints>
          <TripPoint>
            <SensorType>cpu</SensorType>
            <Temperature>75000</Temperature>
            <type>passive</type>
            <CoolingDevice>
              <index>1</index>
              <type>intel_pstate</type>
              <influence>100</influence>
              <SamplingPeriod>1</SamplingPeriod>
            </CoolingDevice>
          </TripPoint>
        </TripPoints>
      </ThermalZone>
    </ThermalZones>
  </Platform>
</ThermalConfiguration>
EOF
    
    log_info "Thermald service available but not auto-started"
    log_info "Enable with: sudo systemctl enable thermald"
    
    log_success "ASUS thermal management configured"
}

# Create ASUS control scripts
create_asus_scripts() {
    log_info "Creating ASUS control scripts..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create ASUS control scripts"
        return 0
    fi
    
    local script_dir="$HOME/.local/bin"
    mkdir -p "$script_dir"
    
    # GPU switching script
    cat > "$script_dir/gpu-switch" << 'EOF'
#!/bin/bash
# GPU switching utility for ASUS TUF

case "$1" in
    nvidia)
        sudo optimus-manager --switch nvidia --no-confirm
        ;;
    intel)
        sudo optimus-manager --switch intel --no-confirm
        ;;
    hybrid)
        sudo optimus-manager --switch hybrid --no-confirm
        ;;
    status)
        optimus-manager --print-mode
        ;;
    *)
        echo "Usage: $0 {nvidia|intel|hybrid|status}"
        echo "Current mode: $(optimus-manager --print-mode)"
        ;;
esac
EOF
    
    # Performance profile script
    cat > "$script_dir/performance-profile" << 'EOF'
#!/bin/bash
# Performance profile switcher for ASUS TUF

case "$1" in
    performance)
        echo "performance" | sudo tee /sys/firmware/acpi/platform_profile
        sudo cpupower frequency-set -g performance
        ;;
    balanced)
        echo "balanced" | sudo tee /sys/firmware/acpi/platform_profile
        sudo cpupower frequency-set -g schedutil
        ;;
    quiet)
        echo "quiet" | sudo tee /sys/firmware/acpi/platform_profile
        sudo cpupower frequency-set -g powersave
        ;;
    status)
        echo "Platform profile: $(cat /sys/firmware/acpi/platform_profile)"
        echo "CPU governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
        ;;
    *)
        echo "Usage: $0 {performance|balanced|quiet|status}"
        ;;
esac
EOF
    
    chmod +x "$script_dir/gpu-switch" "$script_dir/performance-profile"
    
    log_success "ASUS control scripts created"
}