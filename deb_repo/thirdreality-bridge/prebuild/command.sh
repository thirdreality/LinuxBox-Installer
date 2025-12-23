#!/bin/bash
# HubV3 Service Command Handler Script
# This script is executed when a matching MQTT command topic is received
# Arguments: $1 = payload (JSON string or other data)
#
# Expected JSON formats:
#   - {"command": "restart"}
#     Execute: systemctl restart hubv3.service > /dev/null 2>&1 &
#     Note: "> /dev/null 2>&1 &" means:
#       - Redirect stdout to /dev/null (discard standard output)
#       - Redirect stderr to stdout (discard error output)
#       - Run in background (&)
#
#   - {"command": "led", "param": "<value>"}
#     Execute: /usr/local/bin/supervisor led <value>
#     Supported param values:
#       Module Control:
#         - "on", "enable", "enabled"     : Enable LED module
#         - "off", "disable", "disabled", "module_off" : Disable LED module (persistent)
#       User Event:
#         - "clear"                       : Clear user event state (USER_EVENT_OFF)
#         - "toggle"                      : Toggle critical red LED (red-yellow alternating flash)
#       Colors (mapped to USER_EVENT):
#         - "red"                         : Red LED (USER_EVENT_RED)
#         - "blue"                        : Blue LED (USER_EVENT_BLUE)
#         - "yellow"                      : Yellow LED (USER_EVENT_YELLOW)
#         - "green"                       : Green LED (USER_EVENT_GREEN)
#         - "white"                       : White LED (USER_EVENT_WHITE)
#         - "cyan"                        : Cyan LED (USER_EVENT_CYAN)
#         - "magenta"                     : Magenta LED (USER_EVENT_MAGENTA)
#         - "purple"                      : Purple LED (mapped to magenta)
#     Examples:
#       - {"command": "led", "param": "red"}      : Set red LED
#       - {"command": "led", "param": "clear"}     : Clear user event
#       - {"command": "led", "param": "on"}        : Enable LED module
#       - {"command": "led", "param": "off"}       : Disable LED module
#
#   - {"command": "reboot"}
#     Execute: sync (3 times), supervisor led startup, then reboot
#
#   - {"command": "detach"}
#     Execute: systemctl stop linuxbox-hubv3-bridge.service
#
#   - {"command": "permit_join", "param": "start"}
#     Execute: /usr/local/bin/supervisor zigbee scan
#
#   - {"command": "permit_join", "param": "stop"}
#     Execute: /usr/local/bin/supervisor zigbee stop_scan
#
#   - {"command": "switch_host", "param": "https://hm.3reality.co/api/hub/v1"}
#     Modify configuration file: /var/lib/hubv3-bridge/configuration.yaml
#     Update sinks.hm_mqtt.http field

LOG_FILE="/tmp/hubv3_service_command.log"
CONFIG_FILE="/var/lib/hubv3-bridge/configuration.yaml"

# Get payload (first argument)
PAYLOAD="$1"

# Log received payload
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
echo "[$TIMESTAMP] Command received: $PAYLOAD" >> "$LOG_FILE"

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "[$TIMESTAMP] Error: jq is not installed" >> "$LOG_FILE"
    exit 1
fi

# Parse JSON using jq to extract command and param fields
COMMAND=$(echo "$PAYLOAD" | jq -r '.command // empty' 2>/dev/null)
PARAM=$(echo "$PAYLOAD" | jq -r '.param // empty' 2>/dev/null)

# Handle restart command
if [ "$COMMAND" = "restart" ]; then
    echo "[$TIMESTAMP] Restart command detected" >> "$LOG_FILE"
    
    # Execute restart command in background with output redirection
    # > /dev/null 2>&1 & means:
    #   - > /dev/null: redirect stdout to /dev/null (discard)
    #   - 2>&1: redirect stderr (file descriptor 2) to stdout (file descriptor 1)
    #   - &: run command in background
    systemctl restart linuxbox-hubv3-bridge.service > /dev/null 2>&1 &
    
    echo "[$TIMESTAMP] Restart command executed in background" >> "$LOG_FILE"
    exit 0
fi

# Handle led command
if [ "$COMMAND" = "led" ]; then
    if [ -z "$PARAM" ]; then
        echo "[$TIMESTAMP] Error: LED command requires 'param' field" >> "$LOG_FILE"
        exit 1
    fi
    
    echo "[$TIMESTAMP] LED command detected with param: $PARAM" >> "$LOG_FILE"
    
    # Execute supervisor led command with param
    /usr/local/bin/supervisor led "$PARAM"
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        echo "[$TIMESTAMP] LED command executed successfully: param=$PARAM" >> "$LOG_FILE"
    else
        echo "[$TIMESTAMP] LED command failed with exit code $EXIT_CODE: param=$PARAM" >> "$LOG_FILE"
    fi
    
    exit $EXIT_CODE
fi

# Handle reboot command
if [ "$COMMAND" = "reboot" ]; then
    echo "[$TIMESTAMP] Reboot command detected" >> "$LOG_FILE"
    
    # Execute sync three times
    sync
    sync
    sync
    
    # Execute supervisor led startup
    /usr/local/bin/supervisor led startup
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        echo "[$TIMESTAMP] LED startup command executed successfully" >> "$LOG_FILE"
    else
        echo "[$TIMESTAMP] LED startup command failed with exit code $EXIT_CODE" >> "$LOG_FILE"
    fi
    
    # Execute reboot
    echo "[$TIMESTAMP] Executing reboot..." >> "$LOG_FILE"
    /usr/sbin/reboot
    exit $EXIT_CODE
fi

# Handle detach command
if [ "$COMMAND" = "detach" ]; then
    echo "[$TIMESTAMP] Detach command detected" >> "$LOG_FILE"
    
    # Stop service in background
    systemctl stop linuxbox-hubv3-bridge.service > /dev/null 2>&1 &
    
    echo "[$TIMESTAMP] Service stop command executed in background" >> "$LOG_FILE"
    exit 0
fi

# Handle permit_join command
if [ "$COMMAND" = "permit_join" ]; then
    if [ -z "$PARAM" ]; then
        echo "[$TIMESTAMP] Error: permit_join command requires 'param' field (start/stop)" >> "$LOG_FILE"
        exit 1
    fi
    
    echo "[$TIMESTAMP] Permit join command detected with param: $PARAM" >> "$LOG_FILE"
    
    if [ "$PARAM" = "start" ]; then
        /usr/local/bin/supervisor zigbee scan
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 0 ]; then
            echo "[$TIMESTAMP] Zigbee scan started successfully" >> "$LOG_FILE"
        else
            echo "[$TIMESTAMP] Zigbee scan failed with exit code $EXIT_CODE" >> "$LOG_FILE"
        fi
    elif [ "$PARAM" = "stop" ]; then
        /usr/local/bin/supervisor zigbee stop_scan
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 0 ]; then
            echo "[$TIMESTAMP] Zigbee scan stopped successfully" >> "$LOG_FILE"
        else
            echo "[$TIMESTAMP] Zigbee stop_scan failed with exit code $EXIT_CODE" >> "$LOG_FILE"
        fi
    else
        echo "[$TIMESTAMP] Error: permit_join param must be 'start' or 'stop', got: $PARAM" >> "$LOG_FILE"
        exit 1
    fi
    
    exit $EXIT_CODE
fi

# Handle switch_host command
if [ "$COMMAND" = "switch_host" ]; then
    if [ -z "$PARAM" ]; then
        echo "[$TIMESTAMP] Error: switch_host command requires 'param' field (URL)" >> "$LOG_FILE"
        exit 1
    fi
    
    echo "[$TIMESTAMP] Switch host command detected with param: $PARAM" >> "$LOG_FILE"
    
    # Check if config file exists
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "[$TIMESTAMP] Error: Configuration file not found: $CONFIG_FILE" >> "$LOG_FILE"
        exit 1
    fi
    
    # Use Python to safely modify YAML file
    # Preserves comments and formatting using regex-based replacement
    # Use /usr/bin/python3 to ensure specific Python version
    /usr/bin/python3 << PYTHON_EOF
import sys
import shutil
import re

config_file = "$CONFIG_FILE"
new_url = "$PARAM"

try:
    # Create backup
    backup_file = config_file + '.bak'
    shutil.copy2(config_file, backup_file)
    
    # Read file content
    with open(config_file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Check if sinks.hm_mqtt.http exists
    if 'sinks:' not in content or 'hm_mqtt:' not in content:
        print("Error: 'sinks.hm_mqtt' section not found in configuration", file=sys.stderr)
        sys.exit(1)
    
    # Use sed-like replacement to preserve format and comments
    # Pattern: http: <url> (with optional whitespace and comments)
    pattern = r'(http:\s*)([^\s#\n]+)(.*)'
    
    # Find and replace http field in hm_mqtt section
    lines = content.split('\n')
    in_hm_mqtt = False
    found = False
    new_lines = []
    
    for i, line in enumerate(lines):
        # Check if we're entering hm_mqtt section
        if re.match(r'^\s*hm_mqtt:\s*$', line):
            in_hm_mqtt = True
            new_lines.append(line)
            continue
        
        # Check if we're leaving hm_mqtt section (next top-level key)
        if in_hm_mqtt and re.match(r'^[a-zA-Z]', line) and not line.startswith(' ') and not line.startswith('\t'):
            in_hm_mqtt = False
        
        # If we're in hm_mqtt section and this is the http line
        if in_hm_mqtt and re.match(r'^\s+http:\s*', line):
            # Extract existing value and comments
            match = re.match(r'^(\s+http:\s*)([^\s#\n]+)(.*)$', line)
            if match:
                indent = match.group(1)
                old_value = match.group(2)
                rest = match.group(3)  # comments, etc.
                new_lines.append(f"{indent}{new_url}{rest}")
                found = True
                print(f"Successfully updated http from '{old_value}' to '{new_url}'")
            else:
                new_lines.append(line)
        else:
            new_lines.append(line)
    
    if not found:
        print("Error: 'http' field not found in sinks.hm_mqtt section", file=sys.stderr)
        sys.exit(1)
    
    # Write updated content
    with open(config_file, 'w', encoding='utf-8') as f:
        f.write('\n'.join(new_lines))
    
    sys.exit(0)
    
except Exception as e:
    print(f"Error updating configuration: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF
    
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        echo "[$TIMESTAMP] Configuration updated successfully: http=$PARAM" >> "$LOG_FILE"
    else
        echo "[$TIMESTAMP] Configuration update failed with exit code $EXIT_CODE" >> "$LOG_FILE"
    fi
    
    exit $EXIT_CODE
fi

# Handle unknown commands
if [ -n "$COMMAND" ]; then
    echo "[$TIMESTAMP] Unknown command: $COMMAND" >> "$LOG_FILE"
    exit 1
fi

# No command found in payload
if [ -n "$PAYLOAD" ]; then
    echo "[$TIMESTAMP] No valid command found in payload: $PAYLOAD" >> "$LOG_FILE"
fi

exit 0


