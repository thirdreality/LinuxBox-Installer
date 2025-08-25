#!/bin/bash

gpioset 0 29=0  
sleep 0.2
gpioset 0 27=1
sleep 0.2
gpioset 0 27=0
sleep 0.2
gpioset 0 27=1
sleep 0.2

/usr/bin/systemctl start otbr-agent || true
if [ -e "/usr/local/bin/supervisor" ]; then
    /usr/local/bin/supervisor thread enabled || true
fi    

echo "$(date): Waiting for otbr-agent to start and checking for deprecated addresses"
sleep 0.5


