#!/bin/bash
# Script for homeassistant-core-matter

CONFIG_DIR="/var/lib/homeassistant"
VENV_PATH="/srv/homeassistant/bin/activate"
ZHA_CONF="${CONFIG_DIR}/zha.conf"
ZIGPY_BACKUP_FILE="${CONFIG_DIR}/zigpy-backup.json"
DEVICE_REGISTRY="/var/lib/homeassistant/homeassistant/.storage/core.device_registry"
ZIGPY_CHANNEL=15

# Function to execute zigpy command and retrieve IEEE address
function get_zigpy_ieee_from_device {
    if [ ! -f "$ZHA_CONF" ]; then
        if [[ -e "/dev/ttyAML3" ]]; then
            local TMP_INFO="/tmp/zigpy_info.tmp"
            echo "[INFO] Detecting Zigbee radio type..."
            
            # 检查是否存在 R3Backup 目录和设置文件，如果存在则跳过 change-channel 操作
            local SKIP_AUTO_CONFIGRATION=false
            if [ -d "/mnt/R3Backup" ] && [ ! -f "/mnt/R3Backup/.enable-backup" ] && [ -f "/mnt/R3Backup/.enable-restore" ]; then
                local BACKUP_FILES=$(ls /mnt/R3Backup/setting_*.tar.gz 2>/dev/null | wc -l)
                if [ "$BACKUP_FILES" -gt 0 ]; then
                    echo "[INFO] Found $BACKUP_FILES backup setting files in /mnt/R3Backup/ with .enable-restore flag, skipping channel change operation"
                    SKIP_AUTO_CONFIGRATION=true
                fi
            fi
            
            # Try BLZ first
            if zigpy radio --baudrate 2000000 blz /dev/ttyAML3 info > "$TMP_INFO" 2>&1; then
                echo "[INFO] BLZ radio detected, checking current channel..."
                # 修正channel字段提取逻辑，确保能正确获取Channel值
                local CHANNEL=$(grep -i '^channel:' "$TMP_INFO" | awk '{print $2}' | xargs)
                if [ "$CHANNEL" != "$ZIGPY_CHANNEL" ] && [ "$SKIP_AUTO_CONFIGRATION" = false ]; then
                    echo "[INFO] Current channel is $CHANNEL, switching to $ZIGPY_CHANNEL..."
                    zigpy radio --baudrate 2000000 blz /dev/ttyAML3 change-channel --channel $ZIGPY_CHANNEL
                    echo "[INFO] Channel switched, retrieving channel info again..."
                    zigpy radio --baudrate 2000000 blz /dev/ttyAML3 info > "$TMP_INFO" 2>&1
                    echo "[INFO] Channel switched, backuping configuration..."
                    zigpy radio --baudrate 2000000 blz /dev/ttyAML3 backup $ZIGPY_BACKUP_FILE

                    if [ -f "${CONFIG_DIR}/homeassistant/zigbee.db" ]; then
                        rm -rf "${CONFIG_DIR}/homeassistant/zigbee.db"
                    fi
                elif [ "$SKIP_AUTO_CONFIGRATION" = true ]; then
                    echo "[INFO] Skipping channel change due to backup files presence"
                else
                    echo "[INFO] Channel is already set to $ZIGPY_CHANNEL, no change needed"
                fi
                echo "[INFO] Detection complete, saving configuration..."
                cat "$TMP_INFO" > "$ZHA_CONF"
                echo "BLZ radio detected. Output saved to $ZHA_CONF"
                echo "Radio Type: blz" >> "$ZHA_CONF"
                rm -f "$TMP_INFO"
                sync
            elif zigpy radio zigate /dev/ttyAML3 info > "$TMP_INFO" 2>&1; then
                echo "[INFO] ZiGate radio detected, checking current channel..."
                # 修正channel字段提取逻辑，确保能正确获取Channel值
                local CHANNEL=$(grep -i '^channel:' "$TMP_INFO" | awk '{print $2}' | xargs)
                if [ "$CHANNEL" != "$ZIGPY_CHANNEL" ] && [ "$SKIP_AUTO_CONFIGRATION" = false ]; then
                    echo "[INFO] Current channel is $CHANNEL, switching to $ZIGPY_CHANNEL..."
                    zigpy radio zigate /dev/ttyAML3 change-channel --channel $ZIGPY_CHANNEL
                    echo "[INFO] Channel switched, retrieving channel info again..."
                    zigpy radio zigate /dev/ttyAML3 info > "$TMP_INFO" 2>&1
                elif [ "$SKIP_AUTO_CONFIGRATION" = true ]; then
                    echo "[INFO] Skipping channel change due to backup files presence"
                else
                    echo "[INFO] Channel is already set to $ZIGPY_CHANNEL, no change needed"
                fi
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

# Function to update IEEE addresses in the device registry
function enable_zha_for_home_assistant {
    if [[  -e "/srv/homeassistant/bin/home_assistant_zha_enable.py" ]]; then
        [[ ! -f "$DEVICE_REGISTRY" ]] && {
            echo "Error: Core device registry $DEVICE_REGISTRY does not exist."
            return 1
        }

        if [ ! -f "$ZHA_CONF" ]; then        
            echo "Error: ZIGBEE config $ZHA_CONF does not exist."
            return 1
        fi

        /srv/homeassistant/bin/home_assistant_zha_enable.py
        sync
    fi
}

# Check and activate the virtual environment
[[ ! -f "$VENV_PATH" ]] && {
    echo "Error: Virtual environment not found at $VENV_PATH"
    return 1
}

source "$VENV_PATH"

get_zigpy_ieee_from_device
enable_zha_for_home_assistant

sync

deactivate

