#!/bin/bash

# Define source and destination paths
SRC="/usr/lib/thirdreality/images"
DST="/lib/firmware/bl706"
VERSION="1.00.00"
WORK_DIR="/mnt/R3Install"

# Function to get current system version components
get_system_version_components() {
    if [ ! -f "/etc/t3r-release" ]; then
        echo "Error: /etc/t3r-release file not found"
        return 1
    fi
    
    # Read current version info from /etc/t3r-release
    local t3r_version_raw
    t3r_version_raw=$(grep '^VERSION=' /etc/t3r-release | cut -d '"' -f2 | sed 's/^v//')
    
    if [ -z "$t3r_version_raw" ]; then
        echo "Error: Could not read VERSION from /etc/t3r-release"
        return 1
    fi
    
    # Parse system version segments
    local sys_major sys_zigbee sys_thread sys_armbian
    sys_major=$(echo "$t3r_version_raw" | awk -F. '{print $1}')
    sys_zigbee=$(echo "$t3r_version_raw" | awk -F. '{print $2}')
    sys_thread=$(echo "$t3r_version_raw" | awk -F. '{print $3}')
    sys_armbian=$(echo "$t3r_version_raw" | awk -F. '{print $4}')
    
    # Keep version numbers as strings, just ensure they're not empty
    [ -z "$sys_zigbee" ] && sys_zigbee=0
    [ -z "$sys_thread" ] && sys_thread=0
    
    echo "$sys_zigbee $sys_thread $sys_armbian"
}

# Function to get script version components
get_script_version_components() {
    local script_zigbee script_thread
    script_zigbee=$(echo "$VERSION" | cut -d'.' -f2)
    script_thread=$(echo "$VERSION" | cut -d'.' -f3)
    
    # Set defaults if empty
    [ -z "$script_zigbee" ] && script_zigbee=0
    [ -z "$script_thread" ] && script_thread=0
    
    echo "$script_zigbee $script_thread"
}

# Function to update version in /etc/t3r-release
update_version_info() {
    local component=$1
    local new_version=$2

    if [ ! -f "/etc/t3r-release" ]; then
        echo "Warning: /etc/t3r-release file not found"
        return 1
    fi

    echo "Updating $component version to $new_version in /etc/t3r-release"

    # Read current version info from /etc/t3r-release
    local t3r_version_raw
    t3r_version_raw=$(grep '^VERSION=' /etc/t3r-release | cut -d '"' -f2 | sed 's/^v//')
    local t3r_version_id
    t3r_version_id=$(grep '^VERSION_ID=' /etc/t3r-release | cut -d '"' -f2)

    # Fallback to script VERSION if missing
    if [ -z "$t3r_version_raw" ]; then
        t3r_version_raw="$VERSION"
    fi

    # Parse segments
    local major zigbee_version thread_version armbian_version
    major=$(echo "$t3r_version_raw" | awk -F. '{print $1}')
    zigbee_version=$(echo "$t3r_version_raw" | awk -F. '{print $2}')
    thread_version=$(echo "$t3r_version_raw" | awk -F. '{print $3}')
    armbian_version=$(echo "$t3r_version_raw" | awk -F. '{print $4}')

    # Derive armbian from VERSION_ID if not present in VERSION
    if [ -z "$armbian_version" ] && [ -n "$t3r_version_id" ]; then
        armbian_version=$(echo "$t3r_version_id" | sed -E 's/^1[0-9]{4}([0-9]{2})$/\1/')
    fi
    # Final fallback
    if [ -z "$armbian_version" ]; then
        armbian_version="05"
    fi

    # Update the requested component
    if [ "$component" = "zigbee" ]; then
        #zigbee_version=$(printf "%02d" "$new_version")
        zigbee_version=$(printf "%02d" "$((10#$new_version))")
    elif [ "$component" = "thread" ]; then
        #thread_version=$(printf "%02d" "$new_version")
        thread_version=$(printf "%02d" "$((10#$new_version))")
    fi

    # Ensure major exists
    if [ -z "$major" ]; then
        major="1"
    fi

    # Build new 4-part version string and ID
    local new_version_string="${major}.${zigbee_version}.${thread_version}.${armbian_version}"
    sed -i "s/^VERSION=.*/VERSION=\"v${new_version_string}\"/" /etc/t3r-release

    local new_version_id="1${zigbee_version}${thread_version}${armbian_version}"
    sed -i "s/^VERSION_ID=.*/VERSION_ID=\"${new_version_id}\"/" /etc/t3r-release

    echo "Updated VERSION to v${new_version_string}"
    echo "Updated VERSION_ID to ${new_version_id}"
    
    # 在/var/log目录下创建更新记录文件
    local update_record_file="/var/log/thirdreality-update-${component}-$(date +%Y%m%d-%H%M%S).log"
    {
        echo "=== ThirdReality Firmware Update Record ==="
        echo "Update Time: $(date)"
        echo "Component: $component"
        echo "New Version: $new_version"
        echo "Full Version String: v${new_version_string}"
        echo "Version ID: ${new_version_id}"
        echo "Updated File: /etc/t3r-release"
        echo "=========================================="
    } > "$update_record_file"
    
    echo "Update record saved to: $update_record_file"
}

# Function to check if upgrade is needed
check_upgrade_needed() {
    local script_zigbee script_thread sys_zigbee sys_thread
    local version_info
    
    # Get script version components
    version_info=$(get_script_version_components)
    script_zigbee=$(echo "$version_info" | cut -d' ' -f1)
    script_thread=$(echo "$version_info" | cut -d' ' -f2)
    
    echo "DEBUG: Raw script version info: '$version_info'" >&2
    echo "DEBUG: Parsed script_zigbee: '$script_zigbee', script_thread: '$script_thread'" >&2
    
    # Get system version components
    version_info=$(get_system_version_components)
    if [ $? -ne 0 ]; then
        echo "Error: Failed to get system version components"
        return 1
    fi
    
    sys_zigbee=$(echo "$version_info" | cut -d' ' -f1)
    sys_thread=$(echo "$version_info" | cut -d' ' -f2)
    
    echo "DEBUG: Raw system version info: '$version_info'" >&2
    echo "DEBUG: Parsed sys_zigbee: '$sys_zigbee', sys_thread: '$sys_thread'" >&2
    
    echo "Script version: Zigbee=$script_zigbee, Thread=$script_thread" >&2
    echo "System version: Zigbee=$sys_zigbee, Thread=$sys_thread" >&2
    
    local need_zigbee_upgrade=false
    local need_thread_upgrade=false
    
    # Check if script version is higher than system version
    echo "DEBUG: Comparing zigbee versions: script='$script_zigbee' vs system='$sys_zigbee'" >&2
    echo "DEBUG: Zigbee comparison result: $script_zigbee -gt $sys_zigbee" >&2
    if [ "$script_zigbee" -gt "$sys_zigbee" ]; then
        echo "Zigbee upgrade needed: script version ($script_zigbee) > system version ($sys_zigbee)" >&2
        need_zigbee_upgrade=true
    else
        echo "Zigbee upgrade not needed: script version ($script_zigbee) <= system version ($sys_zigbee)" >&2
    fi
    
    echo "DEBUG: Comparing thread versions: script='$script_thread' vs system='$sys_thread'" >&2
    echo "DEBUG: Thread comparison result: $script_thread -gt $sys_thread" >&2
    if [ "$script_thread" -gt "$sys_thread" ]; then
        echo "Thread upgrade needed: script version ($script_thread) > system version ($sys_thread)" >&2
        need_thread_upgrade=true
    else
        echo "Thread upgrade not needed: script version ($script_thread) <= system version ($sys_thread)" >&2
    fi
    
    # Only return the upgrade flags, no debug output here
    echo "$need_zigbee_upgrade $need_thread_upgrade"
}

# Function to flash zigbee firmware with service management
flash_zigbee() {
    echo "upgrade bl702/706 zigbee firmware ..."

    echo "Checking for zigbee firmware at: $SRC/blz_whole_img.bin"
    if [ -f "$SRC/partition_images/blz_whole_img.bin" ]; then
        echo "Found zigbee firmware source file"
        # Check if old firmware exists and calculate MD5
        if [ -f "$DST/partition_1m_images/blz_whole_img.bin" ]; then
            old_md5=$(md5sum "$DST/partition_1m_images/blz_whole_img.bin" | cut -d' ' -f1)
            echo "Old zigbee firmware MD5: $old_md5"
        else
            echo "No existing zigbee firmware found"
        fi
        
        # Copy new firmware
        cp $SRC/partition_images/blz_whole_img.bin $DST/partition_1m_images/blz_whole_img.bin
        
        # Calculate new firmware MD5
        new_md5=$(md5sum "$DST/partition_1m_images/blz_whole_img.bin" | cut -d' ' -f1)
        echo "New zigbee firmware MD5: $new_md5"
        
        # Compare MD5s if old firmware existed
        if [ ! -z "$old_md5" ]; then
            if [ "$old_md5" = "$new_md5" ]; then
                echo "Zigbee firmware unchanged (same MD5)"
            else
                echo "Zigbee firmware updated (MD5 changed)"
            fi
        fi

        # Check and stop services if they are running
        local services_to_manage=("home-assistant.service" "zigbee2mqtt.service")
        local stopped_services=()
        
        for service in "${services_to_manage[@]}"; do
            if systemctl is-active --quiet "$service"; then
                echo "Stopping $service before flashing..."
                systemctl stop "$service"
                stopped_services+=("$service")
            fi
        done

        # Execute flash command with system PATH to ensure python3 resolves to system interpreter
        chmod +x $DST/bl706_func.sh
        local bl706_env_path="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
        PATH="$bl706_env_path" $DST/bl706_func.sh flash zigbee || true

        # Get BL702 info after flashing zigbee firmware
        echo "Getting BL702 info after zigbee firmware flash..."
        if [ -f "$SRC/check_zigbee_firmware.py" ]; then
            python3 "$SRC/check_zigbee_firmware.py"
        else
            echo "Warning: check_zigbee_firmware.py not found at $SRC/check_zigbee_firmware.py"
        fi
        
        # Restart previously stopped services
        for service in "${stopped_services[@]}"; do
            echo "Restarting $service after flashing..."
            systemctl start "$service"
        done
        
        # Update version information after successful zigbee flash
        local zigbee_version=$(echo "$VERSION" | cut -d'.' -f2)
        update_version_info "zigbee" "$zigbee_version"

    else
        echo "Zigbee firmware source file not found: $SRC/partition_images/blz_whole_img.bin"
    fi
}

# Function to flash thread firmware with service management
flash_thread() {
    echo "upgrade bl702/706 thread firmware ..."
    
    echo "Checking for thread firmware at: $SRC/thread_whole_img.bin"
    if [ -f "$SRC/partition_images/thread_whole_img.bin" ]; then
        echo "Found thread firmware source file"
        # Check if old firmware exists and calculate MD5
        if [ -f "$DST/partition_1m_images/thread_whole_img.bin" ]; then
            old_md5=$(md5sum "$DST/partition_1m_images/thread_whole_img.bin" | cut -d' ' -f1)
            echo "Old thread firmware MD5: $old_md5"
        else
            echo "No existing thread firmware found"
        fi
        
        # Copy new firmware
        cp $SRC/partition_images/thread_whole_img.bin $DST/partition_1m_images/thread_whole_img.bin
        # Calculate new firmware MD5
        new_md5=$(md5sum "$DST/partition_1m_images/thread_whole_img.bin" | cut -d' ' -f1)
        echo "New thread firmware MD5: $new_md5"
        
        # Compare MD5s if old firmware existed
        if [ ! -z "$old_md5" ]; then
            if [ "$old_md5" = "$new_md5" ]; then
                echo "Thread firmware unchanged (same MD5)"
            else
                echo "Thread firmware updated (MD5 changed)"
            fi
        fi

        # Check and stop otbr-agent.service if it is running
        local service_to_manage="otbr-agent.service"
        local was_running=false
       
        if systemctl is-active --quiet "$service_to_manage"; then
            echo "Stopping $service_to_manage before flashing..."
            systemctl stop "$service_to_manage"
            was_running=true
        fi

        # Execute flash command with system PATH to ensure python3 resolves to system interpreter
        chmod +x $DST/bl706_func.sh
        local bl706_env_path="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
        PATH="$bl706_env_path" $DST/bl706_func.sh flash thread || true

        # Get RCP version after flashing thread firmware
        echo "Getting RCP version after thread firmware flash..."
        if [ -f "$SRC/check_thread_firmware.py" ]; then
            python3 "$SRC/check_thread_firmware.py"
        else
            echo "Warning: check_thread_firmware.py not found at $SRC/check_thread_firmware.py"
        fi
        
        # Restart otbr-agent.service if it was running before
        if [ "$was_running" = true ]; then
            echo "Restarting $service_to_manage after flashing..."
            systemctl start "$service_to_manage"
        fi
        
        # Update version information after successful thread flash
        local thread_version=$(echo "$VERSION" | cut -d'.' -f3)
        update_version_info "thread" "$thread_version"

    else
        echo "Thread firmware source file not found: $SRC/partition_images/thread_whole_img.bin"
    fi
}

echo "Firmware upgrade script starting..."

# Copy necessary files first
if [ -f "$SRC/bl706_func.sh" ]; then
    echo "copy bl706_func.sh to $DST/bl706_func.sh"
    cp $SRC/bl706_func.sh $DST/bl706_func.sh
    chmod +x $DST/bl706_func.sh
fi

if [ -f "$SRC/bflb_iot.tar.gz" ]; then
    echo "copy bflb_iot.tar.gz to $DST/bflb_iot.tar.gz"
    cp $SRC/bflb_iot.tar.gz $DST/bflb_iot.tar.gz
    rm -rf $DST/bflb_iot > /dev/null 2>&1
fi

# Check for force upgrade mode
if [ -f "$WORK_DIR/.force_board_flash" ]; then
    echo "Force upgrade mode detected: $WORK_DIR/.force_board_flash"
    echo "Executing both zigbee and thread flash operations..."
    
    # Execute both flash operations
    flash_zigbee
    flash_thread
else
    echo "Normal upgrade mode: checking version compatibility..."
    
    # Check if upgrade is needed
    upgrade_info=
    upgrade_info=$(check_upgrade_needed)
    if [ $? -ne 0 ]; then
        echo "Error: Failed to check upgrade requirements"
        exit 1
    fi
    
    echo "DEBUG: Raw upgrade_info from check_upgrade_needed: '$upgrade_info'" >&2
    
    need_zigbee=
    need_thread=
    need_zigbee=$(echo "$upgrade_info" | cut -d' ' -f1)
    need_thread=$(echo "$upgrade_info" | cut -d' ' -f2)
    
    echo "DEBUG: Parsed upgrade flags - need_zigbee: '$need_zigbee', need_thread: '$need_thread'" >&2
    
    # Execute flash operations based on version comparison
    if [ "$need_zigbee" = "true" ]; then
        echo "Executing zigbee firmware upgrade..."
        flash_zigbee
    else
        echo "Skipping zigbee firmware upgrade (version not higher)"
    fi
    
    if [ "$need_thread" = "true" ]; then
        echo "Executing thread firmware upgrade..."
        flash_thread
    else
        echo "Skipping thread firmware upgrade (version not higher)"
    fi
fi

if [ -e "/usr/local/bin/supervisor" ]; then
    /usr/local/bin/supervisor led clear
fi

# Sync filesystem to ensure all changes are written to disk
echo "Syncing filesystem to ensure version updates are saved..."
sync
