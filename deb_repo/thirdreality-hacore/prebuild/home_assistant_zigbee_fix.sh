#!/bin/bash
# Script for homeassistant-core-matter

CONFIG_DIR="/var/lib/homeassistant"
VENV_PATH="/srv/homeassistant/bin/activate"
ZHA_CONF="${CONFIG_DIR}/zha.conf"
ZIGPY_BACKUP_FILE="${CONFIG_DIR}/zigpy-backup.json"
DEVICE_REGISTRY="/var/lib/homeassistant/homeassistant/.storage/core.device_registry"
ZIGPY_CHANNEL=15

# Function to execute zigpy command and retrieve IEEE address
function fix_zigpy_ieee_from_device {
    if [ ! -f "$ZHA_CONF" ]; then
        if [[ -e "/dev/ttyAML3" ]]; then
            local TMP_INFO="/tmp/zigpy_info.tmp"
            echo "[INFO] Detecting Zigbee radio type..."
                        
            # Try BLZ first
            if zigpy radio --baudrate 2000000 blz /dev/ttyAML3 info > "$TMP_INFO" 2>&1; then
                echo "[INFO] BLZ radio detected, checking current channel..."

                echo "[INFO] Detection complete, saving configuration..."
                cat "$TMP_INFO" > "$ZHA_CONF"
                echo "BLZ radio detected. Output saved to $ZHA_CONF"
                echo "Radio Type: blz" >> "$ZHA_CONF"
                rm -f "$TMP_INFO"
                sync
            elif zigpy radio zigate /dev/ttyAML3 info > "$TMP_INFO" 2>&1; then
                echo "[INFO] ZiGate radio detected, checking current channel..."

                echo "[INFO] Detection complete, saving configuration..."
                cat "$TMP_INFO" > "$ZHA_CONF"
                echo "ZiGate radio detected. Output saved to $ZHA_CONF"
                echo "Radio Type: zigate" >> "$ZHA_CONF"
                rm -f "$TMP_INFO"
                sync
            else
                echo "Error: Failed to detect any supported radio type"
                rm -rf "$ZHA_CONF" > /dev/null 2>&1 || true
                rm -f "$TMP_INFO"
                return 1
            fi
        else
            echo "Error: Device /dev/ttyAML3 not found"
            rm -rf "$ZHA_CONF"
            return 1
        fi
    fi
}

# Check and activate the virtual environment
[[ ! -f "$VENV_PATH" ]] && {
    echo "Error: Virtual environment not found at $VENV_PATH"
    return 1
}

source "$VENV_PATH"

rm -rf "$ZHA_CONF" > /dev/null 2>&1 || true
fix_zigpy_ieee_from_device

sync

deactivate

