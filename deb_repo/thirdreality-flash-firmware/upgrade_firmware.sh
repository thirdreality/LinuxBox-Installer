#!/bin/bash

# Define source and destination paths
SRC="/usr/lib/thirdreality/images"
DST="/lib/firmware/bl706"
VERSION="1.00.00"

# Function to update version in /etc/t3r-release
update_version_info() {
    local component=$1
    local new_version=$2
    
    if [ ! -f "/etc/t3r-release" ]; then
        echo "Warning: /etc/t3r-release file not found"
        return 1
    fi
    
    echo "Updating $component version to $new_version in /etc/t3r-release"
    
    # Parse current VERSION from script
    local current_version=$(echo "$VERSION" | cut -d'.' -f1-3)
    local zigbee_version=$(echo "$VERSION" | cut -d'.' -f2)
    local thread_version=$(echo "$VERSION" | cut -d'.' -f3)
    
    # Update component version
    if [ "$component" = "zigbee" ]; then
        zigbee_version=$(printf "%02d" $new_version)
    elif [ "$component" = "thread" ]; then
        thread_version=$(printf "%02d" $new_version)
    fi
    
    # Construct new version string
    local new_version_string="1.${zigbee_version}.${thread_version}"
    
    # Update VERSION in /etc/t3r-release
    sed -i "s/^VERSION=.*/VERSION=\"v${new_version_string}\"/" /etc/t3r-release
    
    # Update VERSION_ID (format: 1XXYYZZ where XX=zigbee, YY=thread, ZZ=armbian)
    local armbian_version=$(echo "$VERSION" | cut -d'.' -f4)
    if [ -z "$armbian_version" ]; then
        armbian_version="03"  # Default armbian version
    fi
    local new_version_id="1${zigbee_version}${thread_version}${armbian_version}"
    sed -i "s/^VERSION_ID=.*/VERSION_ID=\"${new_version_id}\"/" /etc/t3r-release
    
    echo "Updated VERSION to v${new_version_string}"
    echo "Updated VERSION_ID to ${new_version_id}"
}

echo "Firmware upgrade script starting..."

# Function to flash zigbee firmware with service management
flash_zigbee() {
    echo "upgrade bl702/706 zigbee firmware ..."
    
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
    else
        echo "Zigbee firmware source file not found: $SRC/partition_images/blz_whole_img.bin"
    fi
    
    # Execute flash command
    chmod +x $DST/bl706_func.sh
    $DST/bl706_func.sh flash zigbee
    
    # Restart previously stopped services
    for service in "${stopped_services[@]}"; do
        echo "Restarting $service after flashing..."
        systemctl start "$service"
    done
    
    # Update version information after successful zigbee flash
    local zigbee_version=$(echo "$VERSION" | cut -d'.' -f2)
    update_version_info "zigbee" "$zigbee_version"
}

# Function to flash thread firmware with service management
flash_thread() {
    echo "upgrade bl702/706 thread firmware ..."
    
    # Check and stop otbr-agent.service if it is running
    local service_to_manage="otbr-agent.service"
    local was_running=false
    
    if systemctl is-active --quiet "$service_to_manage"; then
        echo "Stopping $service_to_manage before flashing..."
        systemctl stop "$service_to_manage"
        was_running=true
    fi
    
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
    else
        echo "Thread firmware source file not found: $SRC/partition_images/thread_whole_img.bin"
    fi
    
    # Execute flash command
    chmod +x $DST/bl706_func.sh
    $DST/bl706_func.sh flash thread
    
    # Restart otbr-agent.service if it was running before
    if [ "$was_running" = true ]; then
        echo "Restarting $service_to_manage after flashing..."
        systemctl start "$service_to_manage"
    fi
    
    # Update version information after successful thread flash
    local thread_version=$(echo "$VERSION" | cut -d'.' -f3)
    update_version_info "thread" "$thread_version"
}

if [ -e "/usr/local/bin/supervisor" ]; then
    /usr/local/bin/supervisor led magenta
fi

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

# Call zigbee flash function
flash_zigbee

# Call thread flash function
flash_thread

if [ -e "/usr/local/bin/supervisor" ]; then
    /usr/local/bin/supervisor led off
fi

# Sync filesystem to ensure all changes are written to disk
echo "Syncing filesystem to ensure version updates are saved..."
sync
