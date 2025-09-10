#!/srv/homeassistant/bin/python3
# -*- coding: utf-8 -*-

# home_assistant_z2m_enable.py

# deprecated, Do not use this script

import os
import re
import json
import sys
import subprocess
import uuid
from datetime import datetime, timezone

# Base path
BASE_PATH = "/var/lib/homeassistant"

def main():
    need_restart = False
    
    try:
        print("Hint: Use supervisor zigbee z2m to enable zigbee2mqtt services")
    except Exception as e:
        print(f"Unexpected error: {e}")
        return 1
    finally:
        need_restart = True
    return 0


if __name__ == "__main__":
    sys.exit(main())
