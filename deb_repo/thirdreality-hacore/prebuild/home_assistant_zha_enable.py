#!/srv/homeassistant/bin/python3
# -*- coding: utf-8 -*-

# home_assistant_zha_enable.py

import os
import re
import json
import sys
import subprocess
import uuid
from datetime import datetime, timezone

# Base path
BASE_PATH = "/var/lib/homeassistant"

class ConfigError(Exception):
    """Exception raised for configuration errors."""
    pass

def get_info_from_zha_conf():
    zha_conf_path = os.path.join(BASE_PATH, "zha.conf")
    
    if not os.path.exists(zha_conf_path):
        raise ConfigError(f"Error: {zha_conf_path} does not exist")
    
    ieee = None
    radio_type = "zigate"  # Default to zigate if not specified
    
    try:
        with open(zha_conf_path, 'r') as f:
            for line in f:
                if "Device IEEE:" in line:
                    ieee = line.split("Device IEEE:")[1].strip()
                elif "Radio Type:" in line:
                    radio_type = line.split("Radio Type:")[1].strip()
    except Exception as e:
        raise ConfigError(f"Error reading {zha_conf_path}: {e}")
    
    if not ieee:
        raise ConfigError("Error: Could not find Device IEEE in zha.conf")
    
    print(f"Found IEEE: {ieee}, Radio Type: {radio_type}")
    return ieee, radio_type

def check_and_stop_ha_service():
    need_restart = False
    try:
        result = subprocess.run(['systemctl', 'is-active', 'home-assistant.service'], 
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        
        if result.stdout.strip() == 'active':
            print("Stopping home-assistant.service...")
            subprocess.run(['systemctl', 'stop', 'home-assistant.service'], 
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            need_restart = True
    except Exception as e:
        print(f"Error checking or stopping home-assistant.service: {e}")
    
    return need_restart

def find_zigbee_coordinator(devices):
    """查找 Zigbee Coordinator 设备"""
    coordinators = []
    
    for device in devices:
        # 检查是否有 zigbee 连接
        has_zigbee_connection = any(
            conn[0] == "zigbee" 
            for conn in device.get("connections", [])
        )
        
        # Coordinator 的 via_device_id 为 null
        is_root_device = device.get("via_device_id") is None
        
        # 检查是否为 ZHA 标识符
        has_zha_identifier = any(
            identifier[0] == "zha" 
            for identifier in device.get("identifiers", [])
        )
        
        if has_zigbee_connection and is_root_device and has_zha_identifier:
            coordinators.append(device)
    
    return coordinators

def update_config_entries(radio_type="zigate"):
    config_entries_path = os.path.join(BASE_PATH, "homeassistant/.storage/core.config_entries")
    mqtt_entry_id = None
    
    if not os.path.exists(config_entries_path):
        raise ConfigError(f"Error: {config_entries_path} does not exist")
    
    try:
        with open(config_entries_path, 'r') as f:
            config_data = json.load(f)
    except Exception as e:
        raise ConfigError(f"Error reading {config_entries_path}: {e}")
    
    # Check if entries exist
    if 'data' not in config_data or 'entries' not in config_data['data']:
        raise ConfigError("Error: Invalid format in config_entries file")
    
    entries = config_data['data']['entries']
    new_entries = []
    
    # Iterate through entries, remove mqtt related configs, keep others
    for entry in entries:
        if entry.get('domain') == 'mqtt':
            mqtt_entry_id = entry.get('entry_id')
            print(f"Removing MQTT configuration with entry_id: {mqtt_entry_id}")
            continue  # Skip this entry, equivalent to deletion
        new_entries.append(entry)
    
    # Check if ZHA configuration exists
    has_zha = False
    zha_entry_id = None
    for entry in new_entries:
        if entry.get('domain') == 'zha':
            has_zha = True
            zha_entry_id = entry.get('entry_id')
            print(f"ZHA configuration already exists with entry_id: {zha_entry_id}")
            break
    
    # If no ZHA configuration exists, add one
    if not has_zha:
        # Generate a truly new entry_id
        # Format similar to: 01JWJ0ZAEC9C8YN1BVYW4SFW3G
        zha_entry_id = f"01{uuid.uuid4().hex.upper()[:24]}"
        now = datetime.now(timezone.utc).isoformat()
        
        if radio_type == "zigate":
            zha_entry = {
                "created_at": now,
                "data": {
                    "device": {
                        "baudrate": 115200,
                        "flow_control": None,
                        "path": "/dev/ttyAML3"
                    },
                    "radio_type": radio_type
                },
                "disabled_by": None,
                "discovery_keys": {},
                "domain": "zha",
                "entry_id": zha_entry_id,
                "minor_version": 1,
                "modified_at": now,
                "options": {},
                "pref_disable_new_entities": False,
                "pref_disable_polling": False,
                "source": "user",
                "subentries": [],
                "title": "/dev/ttyAML3",
                "unique_id": None,
                "version": 4
            }
        elif radio_type == "blz":
            zha_entry = {
                "created_at": now,
                "data": {
                    "device": {
                        "baudrate": 2000000,
                        "flow_control": None,
                        "path": "/dev/ttyAML3"
                    },
                    "radio_type": radio_type
                },
                "disabled_by": None,
                "discovery_keys": {},
                "domain": "zha",
                "entry_id": zha_entry_id,
                "minor_version": 1,
                "modified_at": now,
                "options": {},
                "pref_disable_new_entities": False,
                "pref_disable_polling": False,
                "source": "user",
                "subentries": [],
                "title": "/dev/ttyAML3",
                "unique_id": None,
                "version": 4
            }
        else:
            raise ConfigError(f"Unsupported radio_type: {radio_type}")
            
        new_entries.append(zha_entry)
        print(f"Added ZHA configuration with entry_id: {zha_entry_id} for radio_type: {radio_type}")
    
    # Update entries
    config_data['data']['entries'] = new_entries
    
    # Write back to file
    try:
        with open(config_entries_path, 'w') as f:
            json.dump(config_data, f, indent=2)
        print(f"Updated {config_entries_path}")
    except Exception as e:
        raise ConfigError(f"Error writing to {config_entries_path}: {e}")
    
    return mqtt_entry_id, zha_entry_id

def update_device_registry(mqtt_entry_id, zha_entry_id, ieee, radio_type):
    device_registry_path = os.path.join(BASE_PATH, "homeassistant/.storage/core.device_registry")
    
    if not os.path.exists(device_registry_path):
        raise ConfigError(f"Error: {device_registry_path} does not exist")
    
    try:
        with open(device_registry_path, 'r') as f:
            device_data = json.load(f)
    except Exception as e:
        raise ConfigError(f"Error reading {device_registry_path}: {e}")
    
    # Check if devices exist
    if 'data' not in device_data or 'devices' not in device_data['data']:
        raise ConfigError("Error: Invalid format in device_registry file")
    
    devices = device_data['data']['devices']
    new_devices = []
    
    # Iterate through devices, remove those related to mqtt_entry_id
    for device in devices:
        if mqtt_entry_id and 'config_entries' in device:
            # If the device's config_entries contains mqtt_entry_id, remove the device
            if mqtt_entry_id in device['config_entries']:
                print(f"Removing device linked to MQTT: [{device.get('name', 'Unknown device')}]")
                continue
        new_devices.append(device)
    
    # Check if ZHA coordinator device already exists
    coordinators = find_zigbee_coordinator(new_devices)
    has_zha_coordinator = len(coordinators) > 0
    
    if has_zha_coordinator:
        print("ZHA coordinator device already exists in registry")
    else:
        now = datetime.now(timezone.utc).isoformat()
        # Use the zha_entry_id obtained from update_config_entries
        if radio_type == "zigate":
            coordinator_device = {
                "area_id": None,
                "config_entries": [zha_entry_id],
                "config_entries_subentries": {zha_entry_id: [None]},
                "configuration_url": None,
                "connections": [["zigbee", ieee]],
                "created_at": now,
                "disabled_by": None,
                "entry_type": None,
                "hw_version": None,
                "id": "af41f395068280b4b3c76734dd1444f3",
                "identifiers": [["zha", ieee]],
                "labels": [],
                "manufacturer": "ZiGate",
                "model": "ZiGate USB-TTL",
                "model_id": None,
                "modified_at": now,
                "name_by_user": None,
                "name": "ZiGate ZiGate USB-TTL",
                "primary_config_entry": zha_entry_id,
                "serial_number": None,
                "sw_version": "3.21",
                "via_device_id": None
            }
        elif radio_type == "blz":
            coordinator_device = {
                "area_id": None,
                "config_entries": [zha_entry_id],
                "config_entries_subentries": {zha_entry_id: [None]},
                "configuration_url": None,
                "connections": [["zigbee", ieee]],
                "created_at": now,
                "disabled_by": None,
                "entry_type": None,
                "hw_version": None,
                "id": "af41f395068280b4b3c76734dd1444f3",
                "identifiers": [["zha", ieee]],
                "labels": [],
                "manufacturer": "Bouffalo Lab",
                "model": "BL706",
                "model_id": None,
                "modified_at": now,
                "name_by_user": None,
                "name": "Bouffalo Lab BL706",
                "primary_config_entry": zha_entry_id,
                "serial_number": None,
                "sw_version": "0x00000000",
                "via_device_id": None
            }
        else:
            raise ConfigError(f"Unsupported radio_type: {radio_type}")
            
        new_devices.append(coordinator_device)
        print(f"Added {radio_type} coordinator device with ZHA entry_id: {zha_entry_id}")
    
    # 更新devices
    device_data['data']['devices'] = new_devices
    
    # Write back to file
    try:
        with open(device_registry_path, 'w') as f:
            json.dump(device_data, f, indent=2)
        print(f"Updated {device_registry_path}")
    except Exception as e:
        raise ConfigError(f"Error writing to {device_registry_path}: {e}")


def update_entity_registry():
    """Update the entity registry to remove all MQTT platform entities"""
    entity_registry_path = os.path.join(BASE_PATH, "homeassistant/.storage/core.entity_registry")
    
    if not os.path.exists(entity_registry_path):
        print(f"Warning: {entity_registry_path} does not exist, skipping entity registry update")
        return
    
    try:
        with open(entity_registry_path, 'r') as f:
            entity_data = json.load(f)
    except Exception as e:
        print(f"Warning: Error reading {entity_registry_path}: {e}, skipping entity registry update")
        return
    
    # Check if entities exist
    if 'data' not in entity_data or 'entities' not in entity_data['data']:
        print("Warning: Invalid format in entity_registry file, skipping entity registry update")
        return
    
    entities = entity_data['data']['entities']
    new_entities = []
    removed_count = 0
    
    # Filter out all entities with platform="mqtt"
    for entity in entities:
        if entity.get('platform') == 'mqtt':
            removed_count += 1
            continue  # Skip this entity (remove it)
        new_entities.append(entity)
    
    if removed_count > 0:
        # Update entities
        entity_data['data']['entities'] = new_entities
        
        # Write back to file
        try:
            with open(entity_registry_path, 'w') as f:
                json.dump(entity_data, f, indent=2)
            print(f"Updated {entity_registry_path}: removed {removed_count} MQTT entities")
        except Exception as e:
            print(f"Warning: Error writing to {entity_registry_path}: {e}")
    else:
        print("No MQTT entities found in entity registry, no changes made")

def restart_ha_service_if_needed(need_restart):
    if need_restart:
        print("Restarting home-assistant.service...")
        try:
            subprocess.run(['systemctl', 'start', 'home-assistant.service'], 
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            print("home-assistant.service restarted successfully")
        except Exception as e:
            print(f"Error restarting home-assistant.service: {e}")

def stop_and_disable_service(service_name):
    """Stop and disable a systemd service if it exists"""
    try:
        # Check if service exists
        result = subprocess.run(['systemctl', 'list-unit-files', service_name], 
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if service_name in result.stdout:
            # Check if service is active
            status = subprocess.run(['systemctl', 'is-active', service_name], 
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            if status.stdout.strip() == 'active':
                print(f"Stopping {service_name}...")
                subprocess.run(['systemctl', 'stop', service_name], 
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            
            # Check if service is enabled
            enabled = subprocess.run(['systemctl', 'is-enabled', service_name], 
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            if enabled.stdout.strip() == 'enabled':
                print(f"Disabling {service_name}...")
                subprocess.run(['systemctl', 'disable', service_name], 
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                
            print(f"{service_name} has been stopped and disabled")
            return True
        return False
    except Exception as e:
        print(f"Error managing {service_name}: {e}")
        return False

def main():
    need_restart = False
    success = False
    
    try:
        # Step 1: Get IEEE address and radio type
        ieee, radio_type = get_info_from_zha_conf()
        
        # Step 2: Check and stop home-assistant.service
        need_restart = check_and_stop_ha_service()
                
        # Step 3: Update config_entries
        mqtt_entry_id, zha_entry_id = update_config_entries(radio_type)
        
        # Step 4: Update device_registry
        update_device_registry(mqtt_entry_id, zha_entry_id, ieee, radio_type)
        
        # Step 5: Update entity registry
        update_entity_registry()
        
        # Sync filesystem to ensure all changes are written to disk
        print("Syncing filesystem...")
        for _ in range(3):
            os.system('sync')
        
        success = True
        print("ZHA configuration completed successfully")

        # Stop and disable zigbee2mqtt and mosquitto services (if they exist)
        stop_and_disable_service('zigbee2mqtt.service')
        stop_and_disable_service('mosquitto.service')

        print("Note: zigbee2mqtt.service and mosquitto.service have been stopped and disabled if they existed")
        
    except ConfigError as e:
        print(f"Configuration error: {e}")
    except Exception as e:
        print(f"Unexpected error: {e}")
    finally:
        # Regardless of success, ensure home-assistant.service is restarted (if needed)
        if need_restart:
            restart_ha_service_if_needed(need_restart)
            
        # If failed, return error code
        if not success:
            sys.exit(1)

if __name__ == "__main__":
    main()
