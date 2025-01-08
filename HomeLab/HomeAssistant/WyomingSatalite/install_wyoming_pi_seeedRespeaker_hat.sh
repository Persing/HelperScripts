#!/usr/bin/env bash

# Copyright (c) 2023 Your Name
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
    echo -e "${BLUE}[INFO]${NC} $1"
}

msg_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

msg_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

msg_error() {
    echo -e "${RED}[ERROR]${NC} $1"
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
    msg_info "Cloning Wyoming Satellite repository..."
    git clone https://github.com/rhasspy/wyoming-satellite.git "$INSTALL_DIR"
    catch_errors
    msg_ok "Repository cloned successfully."
}

# Set up Python virtual environment
setup_venv() {
    msg_info "Setting up Python virtual environment..."
    python3 -m venv "$INSTALL_DIR/.venv"
    source "$INSTALL_DIR/.venv/bin/activate"
    pip install --upgrade pip wheel setuptools
    pip install -f 'https://synesthesiam.github.io/prebuilt-apps/' -r "$INSTALL_DIR/requirements.txt" -r "$INSTALL_DIR/requirements_audio_enhancement.txt" -r "$INSTALL_DIR/requirements_vad.txt"
    catch_errors
    msg_ok "Virtual environment set up successfully."
}

# Configure audio devices
configure_audio() {
    msg_info "Configuring audio devices..."

    msg_info "Listing input devices..."
    arecord -L

    msg_info "Listing output devices..."
    aplay -L

    msg_warn "Please manually configure the input and output devices in the service file."
    msg_warn "Edit the service file at /etc/systemd/system/wyoming-satellite.service and update the --mic-command and --snd-command flags."
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
ExecStart=$INSTALL_DIR/script/run --name 'my satellite' --uri 'tcp://0.0.0.0:10700' --mic-command 'arecord -D plughw:CARD=seeed2micvoicec,DEV=0 -r 16000 -c 1 -f S16_LE -t raw' --snd-command 'aplay -D plughw:CARD=seeed2micvoicec,DEV=0 -r 22050 -c 1 -f S16_LE -t raw'
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

# Set up LED control service
setup_led_service() {
    msg_info "Setting up LED control service..."
    sudo bash -c "cat > /etc/systemd/system/2mic_leds.service <<EOF
[Unit]
Description=2Mic LEDs

[Service]
Type=simple
ExecStart=$INSTALL_DIR/examples/.venv/bin/python3 $INSTALL_DIR/examples/2mic_service.py --uri 'tcp://127.0.0.1:10500'
WorkingDirectory=$INSTALL_DIR/examples
Restart=always
RestartSec=1

[Install]
WantedBy=default.target
EOF"
    sudo systemctl enable --now 2mic_leds.service
    catch_errors
    msg_ok "LED control service set up successfully."
}

# Main function
main() {
    color
    check_root

    # Set installation directory
    INSTALL_DIR="~/wyoming-satellite"
    export INSTALL_DIR

    msg_info "Starting Wyoming Satellite installation..."
    update_os
    install_dependencies
    clone_repository
    setup_venv
    configure_audio
    setup_service
    setup_led_service
    msg_ok "Wyoming Satellite installation and configuration complete!"
}

# Run the script
main