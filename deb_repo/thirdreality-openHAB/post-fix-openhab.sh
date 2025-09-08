#!/bin/bash
#
# Post-installation script for ThirdReality Zigbee2MQTT
# Purpose: Install dependencies, configure mosquitto and zigbee2mqtt
# Version: 1.1.0
#

# Exit on error, but allow commands with || true to continue
set -e

# Constants


# Helper functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Post-installation completed successfully"
exit 0

