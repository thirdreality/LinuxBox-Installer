#!/bin/bash
#
# Zigbee2MQTT BLZ Reset Script
# Purpose: Reset Zigbee hardware via GPIO before service restart
# Version: 1.0.0
#

set -e

LOG_FILE="/var/log/zigbee2mqtt_blz_reset.log"

# Helper function for logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to check if gpioset command is available
check_gpio_tools() {
    if ! command -v gpioset &> /dev/null; then
        log "ERROR: gpioset command not found. Please install gpiod tools:"
        log "  sudo apt-get install gpiod"
        exit 1
    fi
}

# Function to perform GPIO reset sequence
gpio_reset_sequence() {
    log "Starting Zigbee GPIO reset sequence..."
    
    gpioset 0 3=1
    sleep 0.2

    # GPIO 0:3 = 0 (reset pin low)
    gpioset 0 3=0
    sleep 0.2
    
    # GPIO 0:1 = 1 (boot pin high)
    gpioset 0 1=1
    sleep 0.2
    
    # GPIO 0:1 = 0 (boot pin low)
    gpioset 0 1=0
    sleep 0.2
    
    # GPIO 0:1 = 1 (boot pin high)
    gpioset 0 1=1
    sleep 0.5
    
    log "Zigbee GPIO reset sequence completed"
}

# Main execution
log "Starting Zigbee2MQTT BLZ reset process..."

# Check prerequisites
check_gpio_tools

# Perform GPIO reset
gpio_reset_sequence

log "Zigbee2MQTT BLZ reset process completed"
