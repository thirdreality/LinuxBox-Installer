#!/bin/bash
#
# Post-installation script for ThirdReality Zigbee2MQTT
# Purpose: Install dependencies, configure mosquitto and zigbee2mqtt
# Version: 1.1.0
#

# Exit on error, but allow commands with || true to continue
set -e

# Constants
DEFAULT_APT_CACHE="/var/cache/apt/archives"
THIRDREALITY_ARCHIVES="/usr/lib/thirdreality/archives"
THIRDREALITY_CONF="/lib/thirdreality/conf"
MOSQUITTO_DIR="/etc/mosquitto"
ZIGBEE2MQTT_DIR="/opt/zigbee2mqtt/data"
LOG_FILE="/var/log/thirdreality-zigbee-mqtt-install.log"

# Helper functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

install_packages() {
    log "Installing dependencies for mosquitto and zigbee2mqtt..."
    
    # Define packages in the original installation order
    local PACKAGES=(
        "libdlt2_*.deb"
        "libmosquitto1_*.deb"
        "mosquitto-clients_*.deb"
        "mosquitto_*.deb"
        "libsystemd-dev_*.deb"
        "nodejs_*.deb"
    )
    
    # Install packages in the defined order using a for loop
    for pkg in "${PACKAGES[@]}"; do
        local pkg_files=(${DEFAULT_APT_CACHE}/${pkg})
        if [ ${#pkg_files[@]} -gt 0 ] && [ -f "${pkg_files[0]}" ]; then
            log "Installing ${pkg}..."
            dpkg -i ${DEFAULT_APT_CACHE}/${pkg} > /dev/null 2>&1 || true
        else
            log "WARNING: No matching files found for ${pkg}"
        fi
    done
    
    # Fix any dependency issues
    log "Fixing dependencies..."
    apt-get install -f -y > /dev/null 2>&1 || log "WARNING: Some dependencies could not be fixed"
}

configure_mosquitto() {
    if [ ! -f "/usr/bin/mosquitto_passwd" ]; then
        log "WARNING: mosquitto_passwd not found, skipping password setup"
        return
    fi
    
    if [ ! -d "$MOSQUITTO_DIR" ]; then
        log "Creating $MOSQUITTO_DIR directory"
        mkdir -p "$MOSQUITTO_DIR"
    fi
    
    # Set up password
    log "Setting up mosquitto password"
    mosquitto_passwd -b -c "$MOSQUITTO_DIR/passwd" thirdreality thirdreality
    
    # Copy default config if available
    if [ -f "$THIRDREALITY_CONF/mosquitto.conf.default" ]; then
        log "Installing mosquitto configuration"
        cp "$THIRDREALITY_CONF/mosquitto.conf.default" "$MOSQUITTO_DIR/mosquitto.conf"
    else
        log "WARNING: Default mosquitto configuration not found"
    fi
}

configure_zigbee2mqtt() {
    if [ ! -f "$THIRDREALITY_CONF/configuration.yaml.default" ]; then
        log "WARNING: Default zigbee2mqtt configuration not found"
        return
    fi
    
    if [ ! -d "$ZIGBEE2MQTT_DIR" ]; then
        log "Creating $ZIGBEE2MQTT_DIR directory"
        mkdir -p "$ZIGBEE2MQTT_DIR"
    fi
    
    log "Installing zigbee2mqtt configuration"
    cp "$THIRDREALITY_CONF/configuration.yaml.default" "$ZIGBEE2MQTT_DIR/configuration.yaml"

    if [ -f "/usr/lib/node_modules/pnpm/bin/pnpm.cjs" ]; then
        ln -snf /usr/lib/node_modules/pnpm/bin/pnpm.cjs /usr/bin/pnpm
    fi    
}

stop_services() {
    log "Stop services for manual control"
    systemctl stop zigbee2mqtt.service > /dev/null 2>&1 || log "WARNING: Failed to stop zigbee2mqtt.service"
    systemctl stop mosquitto.service > /dev/null 2>&1 || log "WARNING: Failed to stop mosquitto.service"
}

disable_services() {
    log "Disabling services for manual control"
    systemctl disable mosquitto.service > /dev/null 2>&1 || log "WARNING: Failed to disable mosquitto.service"
    systemctl disable zigbee2mqtt.service > /dev/null 2>&1 || log "WARNING: Failed to disable zigbee2mqtt.service"
}

# Main execution
if [ ! -d "$THIRDREALITY_ARCHIVES" ]; then
    log "ERROR: ThirdReality archives directory not found at $THIRDREALITY_ARCHIVES"
    exit 1
fi

# Clean apt cache
rm -rf ${DEFAULT_APT_CACHE}/*.deb

# Copy package files to apt cache
log "Copying package files to apt cache"
cp "$THIRDREALITY_ARCHIVES"/*.deb "$DEFAULT_APT_CACHE/" || log "WARNING: Failed to copy some package files"

# Install packages
install_packages

# Clean up apt cache after installation
rm -rf ${DEFAULT_APT_CACHE}/*.deb

stop_services

# Configure services
configure_mosquitto
configure_zigbee2mqtt
disable_services

log "Post-installation completed successfully"
exit 0

