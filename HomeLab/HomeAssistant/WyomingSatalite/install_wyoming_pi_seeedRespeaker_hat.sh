#!/usr/bin/env bash

# Copyright (c) 2023 Nick Persing
# License: MIT
# Description: Wyoming Satellite Installation Script

# Define colors for logging
color() {
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
}

# Logging functions
msg_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2  # Log to stderr
}

msg_ok() {
    echo -e "${GREEN}[OK]${NC} $1" >&2  # Log to stderr
}

msg_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2  # Log to stderr
}

msg_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2  # Log to stderr
    exit 1
}

# Error handling
catch_errors() {
    if [ $? -ne 0 ]; then
        msg_error "An error occurred. Exiting."
    fi
}

# Check if running as root
check_root() {
    if [ "$EUID" -eq 0 ]; then
        msg_error "Please do not run this script as root. Run it as a regular user and provide sudo permissions when prompted."
    fi
}

# Function to select an audio device
select_audio_device() {
    local type=$1
    local devices
    local device

    if [ "$type" == "input" ]; then
        msg_info "Listing input devices..."
        devices=$(arecord -L | grep -E '^hw|^plughw' | awk '{print $1}')
    elif [ "$type" == "output" ]; then
        msg_info "Listing output devices..."
        devices=$(aplay -L | grep -E '^hw|^plughw' | awk '{print $1}')
    else
        msg_error "Invalid device type. Use 'input' or 'output'."
    fi

    if [ -z "$devices" ]; then
        msg_error "No $type devices found. Please check your audio hardware."
    fi

    echo "Available $type devices:" >&2  # Log to stderr
    select device in $devices; do
        if [ -n "$device" ]; then
            echo "$device"  # Return only the selected device to stdout
            return
        else
            msg_warn "Invalid selection. Please try again." >&2  # Log to stderr
        fi
    done
}
# Update OS
update_os() {
    msg_info "Updating OS packages..."
    sudo apt-get update -y && sudo apt-get upgrade -y
    catch_errors
    msg_ok "OS updated successfully."
}

# Install dependencies
install_dependencies() {
    msg_info "Installing dependencies..."
    sudo apt-get install -y git python3-venv python3-spidev python3-gpiozero
    catch_errors
    msg_ok "Dependencies installed successfully."
}

# Clone Wyoming Satellite repository
clone_repository() {
    if [ -d "$INSTALL_DIR" ]; then
        msg_warn "Repository already exists at $INSTALL_DIR. Skipping clone."
    else
        msg_info "Cloning Wyoming Satellite repository..."
        git clone https://github.com/rhasspy/wyoming-satellite.git "$INSTALL_DIR"
        catch_errors
        msg_ok "Repository cloned successfully."
    fi
}

# Install Respeaker drivers (if applicable)
install_respeaker_drivers() {
    msg_info "Installing Respeaker drivers..."
    sudo bash "$INSTALL_DIR/etc/install-respeaker-drivers.sh"
    catch_errors
    msg_ok "Respeaker drivers installed successfully."

    msg_warn "The system will now reboot to apply changes. Please rerun this script after reboot to complete the setup."
    sudo reboot
}

# Set up Python virtual environment
setup_venv() {
    if [ -d "$INSTALL_DIR/.venv" ]; then
        msg_warn "Virtual environment already exists at $INSTALL_DIR/.venv. Skipping setup."
    else
        msg_info "Setting up Python virtual environment..."
        python3 -m venv "$INSTALL_DIR/.venv"
        catch_errors
        msg_ok "Virtual environment created successfully."
    fi

    msg_info "Installing Python dependencies..."
    source "$INSTALL_DIR/.venv/bin/activate"
    pip install --upgrade pip wheel setuptools
    pip install -f 'https://synesthesiam.github.io/prebuilt-apps/' -r "$INSTALL_DIR/requirements.txt" -r "$INSTALL_DIR/requirements_audio_enhancement.txt" -r "$INSTALL_DIR/requirements_vad.txt"
    catch_errors
    msg_ok "Python dependencies installed successfully."
}

# Configure audio devices
configure_audio() {
    msg_info "Configuring audio devices..."

    input_device=$(select_audio_device "input")
    output_device=$(select_audio_device "output")

    msg_ok "Selected input device: $input_device"
    msg_ok "Selected output device: $output_device"
}

# Set up Wyoming Satellite service
setup_service() {
    msg_info "Setting up Wyoming Satellite service..."
    sudo bash -c "cat > /etc/systemd/system/wyoming-satellite.service <<EOF
[Unit]
Description=Wyoming Satellite
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/script/run --name 'my satellite' --uri 'tcp://0.0.0.0:10700' --mic-command 'arecord -D $input_device -r 16000 -c 1 -f S16_LE -t raw' --snd-command 'aplay -D $output_device -r 22050 -c 1 -f S16_LE -t raw'
WorkingDirectory=$INSTALL_DIR
Restart=always
RestartSec=1

[Install]
WantedBy=default.target
EOF"
    sudo systemctl enable --now wyoming-satellite.service
    catch_errors
    msg_ok "Wyoming Satellite service set up successfully."
}

# Set up LED control service (if applicable)
setup_led_service() {
    msg_info "Setting up LED control service..."
    sudo bash -c "cat > /etc/systemd/system/2mic_leds.service <<EOF
[Unit]
Description=2Mic LEDs

[Service]
Type=simple
ExecStart=$INSTALL_DIR/examples/.venv/bin/python3 
2mic_service.py --uri 'tcp://127.0.0.1:10500'
WorkingDirectory=$INSTALL_DIR/examples
Restart=always
RestartSec=1

[Install]
WantedBy=default.target
EOF"
    sudo systemctl enable --now 2mic_leds.service
    catch_errors
    msg_ok "LED control service set up successfully."

    # Update Wyoming Satellite service for LED integration
    msg_info "Updating Wyoming Satellite service for LED integration..."
    sudo bash -c "cat > /etc/systemd/system/wyoming-satellite.service <<EOF
[Unit]
Description=Wyoming Satellite
Wants=network-online.target
After=network-online.target
Requires=2mic_leds.service

[Service]
Type=simple
ExecStart=$INSTALL_DIR/script/run --name 'my satellite' --uri 'tcp://0.0.0.0:10700' --mic-command 'arecord -D $input_device -r 16000 -c 1 -f S16_LE -t raw' --snd-command 'aplay -D $output_device -r 22050 -c 1 -f S16_LE -t raw' --event-uri 'tcp://127.0.0.1:10500'
WorkingDirectory=$INSTALL_DIR
Restart=always
RestartSec=1

[Install]
WantedBy=default.target
EOF"
    sudo systemctl daemon-reload
    sudo systemctl restart wyoming-satellite.service
    catch_errors
    msg_ok "Wyoming Satellite service updated for LED integration."
}

# Reload and restart services
reload_services() {
    msg_info "Reloading and restarting services..."
    sudo systemctl daemon-reload
    sudo systemctl restart wyoming-satellite.service
    if "$SETUP_LED" =~ ^[Yy]$ ]]; then
        sudo systemctl restart 2mic_leds.service
    fi
    catch_errors
    msg_ok "Services reloaded and restarted successfully."
}

# Main function
main() {
    color
    check_root

    # Set installation directory
    INSTALL_DIR="$HOME/wyoming-satellite"  # Use $HOME instead of ~
    export INSTALL_DIR

    msg_info "Starting Wyoming Satellite installation..."

    # Prompt for driver installation
    read -p "Do you need to install Respeaker drivers? (y/n): " INSTALL_DRIVERS
    if [[ "$INSTALL_DRIVERS" =~ ^[Yy]$ ]]; then
        update_os
        install_dependencies
        clone_repository
        install_respeaker_drivers
    else
        update_os
        install_dependencies
        clone_repository
        setup_venv
        configure_audio
        setup_service
        reload_services

        # Prompt for LED service setup
        read -p "Do you want to set up the LED control service? (y/n): " SETUP_LED
        if [[ "$SETUP_LED" =~ ^[Yy]$ ]]; then
            setup_led_service
        else
            msg_info "Skipping LED control service setup."
        fi

        msg_ok "Wyoming Satellite installation and configuration complete!"
    fi
}

# Run the script
main