#!/bin/bash
# Reset the Thread RCP before otbr-agent opens /dev/ttyAML6. Runs as the first
# ExecStartPre of otbr-agent.service, so every start/restart of the agent sees a
# freshly reset radio (if the radio were reset after the agent attached, the agent
# would abort on the unexpected RCP reset).

gpioset 0 29=0
sleep 0.2
gpioset 0 27=1
sleep 0.2
gpioset 0 27=0
sleep 0.2
gpioset 0 27=1
sleep 0.5

exit 0
