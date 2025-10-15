#!/bin/bash

# Empty delete_devices, delete_entitis when startup
PRE_CHECK_PY="/srv/homeassistant/bin/home_assistant_boot_check.py"
if [ -f "$PRE_CHECK_PY" ]; then
    /srv/homeassistant/bin/python3 $PRE_CHECK_PY
fi

