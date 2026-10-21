#!/bin/bash
# This script installs and configures the otbr-agent service. Running it from the
# Supervisor turned out to happen too early -- the filesystem may not be ready yet,
# which made it unreliable -- so it was moved to run once the network is up.

# Enhanced wpan0 interface fix function
fix_wpan_interface() {
    echo "$(date): Starting wpan0 interface fix"
    
    # Check Thread state before fix
    if curl -s --connect-timeout 3 http://localhost:8081/node >/dev/null 2>&1; then
        state=$(curl -s http://localhost:8081/node | jq -r '.State')
        echo "$(date): Thread state before fix: $state"
    fi
    
    # Reset interface
    if ip link show wpan0 >/dev/null 2>&1; then
        ip link set wpan0 down
        ip -6 addr flush dev wpan0
        ip link set wpan0 up
        echo "$(date): wpan0 interface reset completed"
        
        # Wait and check state after fix
        sleep 5
        if curl -s --connect-timeout 3 http://localhost:8081/node >/dev/null 2>&1; then
            new_state=$(curl -s http://localhost:8081/node | jq -r '.State')
            echo "$(date): Thread state after fix: $new_state"
        fi
    else
        echo "$(date): wpan0 interface not found"
    fi
}

# This script used to check the state of GPIO pins 0 and 27: start otbr-agent when
# high, stop it when low.

# if gpioget 0 27; then
#     /usr/bin/systemctl start otbr-agent || true
#     if [ -e "/usr/local/bin/supervisor" ]; then
#         /usr/local/bin/supervisor thread enabled || true
#     fi    
# else
#     /usr/bin/systemctl disable otbr-agent || true
#     /usr/bin/systemctl stop otbr-agent || true
#     if [ -e "/usr/local/bin/supervisor" ]; then
#         /usr/local/bin/supervisor thread disabled || true
#     fi    
# fi

gpioset 0 29=0  
sleep 0.2
gpioset 0 27=1
sleep 0.2
gpioset 0 27=0
sleep 0.2
gpioset 0 27=1
sleep 0.5

/usr/bin/systemctl start otbr-agent || true
if [ -e "/usr/local/bin/supervisor" ]; then
    /usr/local/bin/supervisor thread enabled || true
fi    

# Wait for otbr-agent to fully start and check for deprecated addresses
echo "$(date): Waiting for otbr-agent to start and checking for deprecated addresses"
sleep 5
#for i in {1..12}; do
#    if systemctl is-active --quiet otbr-agent && ip link show wpan0 &>/dev/null; then
#        if ip -6 addr show wpan0 | grep -q "deprecated"; then
#            echo "$(date): Deprecated addresses detected on wpan0"
#            fix_wpan_interface
#        else
#            echo "$(date): No deprecated addresses found on wpan0"
#        fi
#        break
#    fi
#    sleep 5
#done

