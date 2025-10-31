#!/bin/bash
# 本脚本主要用于安装和配置 otbr-agent 服务，由于Supervisor中运行的太早，而文件系统可能没有准备好，导致不够稳定，
# 所以后移到网络满足后再执行。

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

# 该脚本会检查 GPIO pin 0 和 27 的状态，如果为高电平，则启动 otbr-agent 服务；如果为低电平，则停止 otbr-agent 服务。

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

