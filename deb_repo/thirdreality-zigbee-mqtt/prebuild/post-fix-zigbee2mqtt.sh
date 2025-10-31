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
THIRDREALITY_ARCHIVES="/usr/lib/thirdreality/archives_zigbee2mqtt"
THIRDREALITY_CONF="/lib/thirdreality/conf"
MOSQUITTO_DIR="/etc/mosquitto"
ZIGBEE2MQTT_DIR="/opt/zigbee2mqtt/data"
LOG_FILE="/var/log/thirdreality-zigbee-mqtt-install.log"

# Helper functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}


install_mosquitto_packages() {
    local MOS_PACKAGES=("libdlt2_*.deb" "libmosquitto1_*.deb" "mosquitto-clients_*.deb" "mosquitto_*.deb")
    for pkg in "${MOS_PACKAGES[@]}"; do
        local pkg_files=(${DEFAULT_APT_CACHE}/${pkg})
        if [ ${#pkg_files[@]} -gt 0 ] && [ -f "${pkg_files[0]}" ]; then
            log "安装 $pkg ..."
            dpkg -i ${DEFAULT_APT_CACHE}/${pkg} 2>&1 | tee -a "$LOG_FILE" || true
        fi
    done
    apt-get install -f -y 2>&1 | tee -a "$LOG_FILE"
}

install_libsystemd_dev() {
    local pkg_file=$(ls $DEFAULT_APT_CACHE/libsystemd-dev_*.deb 2>/dev/null | head -n 1)
    if [ -n "$pkg_file" ]; then
        local new_ver=$(dpkg-deb -f "$pkg_file" Version)
        local cur_ver=$(dpkg-query -W -f='${Version}' libsystemd-dev 2>/dev/null)
        log "libsystemd-dev 目标版本: $new_ver，已装版本: $cur_ver"
        if [ -z "$cur_ver" ]; then
            dpkg -i "$pkg_file"
        elif dpkg --compare-versions "$cur_ver" lt "$new_ver"; then
            apt-get remove --purge -y libsystemd-dev
            dpkg -i "$pkg_file"
        else
            log "libsystemd-dev 已是新版本, 跳过"
        fi
    fi
}

install_nodejs() {
    local pkg_file=$(ls $DEFAULT_APT_CACHE/nodejs_*.deb 2>/dev/null | head -n 1)
    if [ -n "$pkg_file" ]; then
        local new_ver=$(dpkg-deb -f "$pkg_file" Version)
        local cur_ver=$(dpkg-query -W -f='${Version}' nodejs 2>/dev/null)
        log "nodejs 目标版本: $new_ver，已装版本: $cur_ver"
        if [ -z "$cur_ver" ]; then
            dpkg -i "$pkg_file"
        elif dpkg --compare-versions "$cur_ver" lt "$new_ver"; then
            apt-get remove --purge -y nodejs npm
            dpkg -i "$pkg_file"
        else
            log "nodejs 已是新版本, 跳过"
        fi
    fi
}

verify_installation() {
    log "Verifying installation..."
    
    local missing_commands=()
    
    if ! command -v node &> /dev/null; then
        missing_commands+=("node")
    fi
    
    if ! command -v mosquitto &> /dev/null; then
        missing_commands+=("mosquitto")
    fi
    
    if ! command -v mosquitto_passwd &> /dev/null; then
        missing_commands+=("mosquitto_passwd")
    fi
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        log "ERROR: Missing commands after installation: ${missing_commands[*]}"
        return 1
    fi
    
    log "All required commands are available"
    
    # 记录版本信息
    log "Installed versions:"
    log "  Node.js: $(node --version)"
    log "  npm: $(npm --version)"
    log "  mosquitto: $(mosquitto -h 2>&1 | head -1)"
    
    return 0
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

    if [ ! -f "$MOSQUITTO_DIR/passwd" ]; then
        log "Setting up mosquitto password"
        mosquitto_passwd -b -c "$MOSQUITTO_DIR/passwd" thirdreality thirdreality
    else
        log "mosquitto passwd file already exists, skipping creation"
    fi

    if [ ! -f "$MOSQUITTO_DIR/mosquitto.conf" ]; then
        if [ -f "$THIRDREALITY_CONF/mosquitto.conf.default" ]; then
            log "Installing mosquitto configuration"
            cp "$THIRDREALITY_CONF/mosquitto.conf.default" "$MOSQUITTO_DIR/mosquitto.conf"
        else
            log "WARNING: Default mosquitto configuration template not found"
        fi
    else
        log "mosquitto.conf already exists, skipping copy"
    fi
}

configure_zigbee2mqtt() {
    if [ ! -f "$THIRDREALITY_CONF/configuration.yaml.default" ]; then
        log "WARNING: Default zigbee2mqtt configuration template not found"
        return
    fi

    if [ ! -d "$ZIGBEE2MQTT_DIR" ]; then
        log "Creating $ZIGBEE2MQTT_DIR directory"
        mkdir -p "$ZIGBEE2MQTT_DIR"
    fi

    if [ ! -f "$ZIGBEE2MQTT_DIR/configuration.yaml" ]; then
        log "Installing zigbee2mqtt configuration"
        cp "$THIRDREALITY_CONF/configuration.yaml.default" "$ZIGBEE2MQTT_DIR/configuration.yaml"
    else
        log "zigbee2mqtt configuration file already exists, skipping copy"
    fi

    if [ -f "/usr/lib/node_modules/pnpm/bin/pnpm.cjs" ]; then
        ln -snf /usr/lib/node_modules/pnpm/bin/pnpm.cjs /usr/bin/pnpm
    fi    
}

stop_services() {
    log "Stop services for manual control"
    systemctl stop zigbee2mqtt.service > /dev/null 2>&1 || log "WARNING: Failed to stop zigbee2mqtt.service"
    systemctl stop mosquitto.service > /dev/null 2>&1 || log "WARNING: Failed to stop mosquitto.service"
}

# Function to check Home Assistant integration mode
check_ha_integration_mode() {
    local ha_config_file="/var/lib/homeassistant/homeassistant/.storage/core.config_entries"
    
    if [ ! -f "$ha_config_file" ]; then
        log "INFO: Home Assistant config file not found, defaulting to disable services"
        return 1  # Default to disable if config not found
    fi
    
    # Check if ZHA integration is enabled
    if grep -q '"domain":"zha"' "$ha_config_file"; then
        log "INFO: ZHA integration detected in Home Assistant config"
        return 1  # ZHA mode - disable zigbee2mqtt services
    fi
    
    # Check if MQTT integration is enabled
    if grep -q '"domain":"mqtt"' "$ha_config_file"; then
        log "INFO: MQTT integration detected in Home Assistant config"
        return 0  # MQTT mode - enable zigbee2mqtt services
    fi
    
    log "INFO: No ZHA or MQTT integration found, defaulting to disable services"
    return 1  # Default to disable if neither found
}

# Function to check if thirdreality-hacore is installed
check_hacore_installed() {
    # Check if thirdreality-hacore package is installed
    if dpkg -l | grep -q "^ii.*thirdreality-hacore"; then
        log "INFO: thirdreality-hacore is installed"
        return 0  # hacore is installed
    else
        log "INFO: thirdreality-hacore is not installed - standalone mode"
        return 1  # hacore is not installed
    fi
}

# Function to disable services (ZHA mode)
disable_services() {
    log "Disabling zigbee2mqtt service for ZHA mode (keeping mosquitto running)"
    
    # Always enable and start mosquitto (needed for other services)
    systemctl enable mosquitto.service > /dev/null 2>&1 || log "WARNING: Failed to enable mosquitto.service"
    systemctl start mosquitto.service > /dev/null 2>&1 || log "WARNING: Failed to start mosquitto.service"
    
    # Disable and stop zigbee2mqtt only
    systemctl disable zigbee2mqtt.service > /dev/null 2>&1 || log "WARNING: Failed to disable zigbee2mqtt.service"
    systemctl stop zigbee2mqtt.service > /dev/null 2>&1 || log "WARNING: Failed to stop zigbee2mqtt.service"
    
    # Verify mosquitto is running
    if systemctl is-active --quiet mosquitto.service; then
        log "INFO: Mosquitto service is running (as required)"
    else
        log "WARNING: Mosquitto service may not be running properly"
    fi
}

# Function to enable and start services (MQTT mode)
enable_and_start_services() {
    log "Enabling and starting services for MQTT/Zigbee2MQTT mode"
    
    # Enable services
    systemctl enable mosquitto.service > /dev/null 2>&1 || log "WARNING: Failed to enable mosquitto.service"
    systemctl enable zigbee2mqtt.service > /dev/null 2>&1 || log "WARNING: Failed to enable zigbee2mqtt.service"
    
    # Start services
    systemctl start mosquitto.service > /dev/null 2>&1 || log "WARNING: Failed to start mosquitto.service"
    sleep 2  # Wait for mosquitto to start before starting zigbee2mqtt
    systemctl start zigbee2mqtt.service > /dev/null 2>&1 || log "WARNING: Failed to start zigbee2mqtt.service"
    
    # Check service status
    if systemctl is-active --quiet mosquitto.service; then
        log "INFO: Mosquitto service started successfully"
    else
        log "WARNING: Mosquitto service may not be running properly"
    fi
    
    if systemctl is-active --quiet zigbee2mqtt.service; then
        log "INFO: Zigbee2MQTT service started successfully"
    else
        log "WARNING: Zigbee2MQTT service may not be running properly"
    fi
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

# 调用顺序替换为：
install_mosquitto_packages
install_libsystemd_dev
install_nodejs

# Clean up apt cache after installation
rm -rf ${DEFAULT_APT_CACHE}/*.deb

stop_services

configure_mosquitto
configure_zigbee2mqtt


SKIP_AUTO_CONFIGRATION=false
if [ -d "/mnt/R3Backup" ] && [ ! -f "/mnt/R3Backup/.enable-backup" ] && [ -f "/mnt/R3Backup/.enable-restore" ]; then
	BACKUP_FILES=$(ls /mnt/R3Backup/setting_*.tar.gz 2>/dev/null | wc -l)
	if [ "$BACKUP_FILES" -gt 0 ]; then
		echo "[INFO] Found $BACKUP_FILES backup setting files in /mnt/R3Backup/ with .enable-restore flag, skipping channel change operation"
		SKIP_AUTO_CONFIGRATION=true
	fi
fi

if [ "$SKIP_AUTO_CONFIGRATION" = "false" ]; then
    # Determine service action based on thirdreality-hacore installation and Home Assistant integration mode
    if ! check_hacore_installed; then
        if [ ! -f "$ZIGBEE2MQTT_DIR/configuration.yaml" ]; then
            log "Installing zigbee2mqtt configuration"
            cp "$THIRDREALITY_CONF/configuration_blz.yaml.default" "$ZIGBEE2MQTT_DIR/configuration.yaml"
        else
            log "INFO: Default zigbee2mqtt configuration already exists"
        fi
        # Standalone mode - enable and start services
        # Start the local MQTT service to ensure zigbee2mqtt can start;
        # if connecting to the MQTT server fails, zigbee2mqtt will fail to start
        enable_and_start_services
        log "Post-installation completed successfully - services enabled for standalone mode"
    else
        # hacore is installed - check Home Assistant integration mode
        if check_ha_integration_mode; then
            # MQTT integration detected - enable and start services
            enable_and_start_services
            log "Post-installation completed successfully - services enabled for MQTT mode"
        else
            # ZHA integration detected or no config found - disable services
            disable_services
            log "Post-installation completed successfully - services disabled for ZHA mode"
        fi
    fi
fi

exit 0

