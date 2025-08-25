#!/srv/homeassistant/bin/python3
# -*- coding: utf-8 -*-

import argparse
import json
import os
import time
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--home', default="/var/lib/homeassistant/homeassistant", help='Default: /var/lib/homeassistant/homeassistant')
args = parser.parse_args()

def check_device_file(file_path):
    my_file = Path(file_path)
    if not my_file.exists():
        print(file_path + " is not exist")
        return
    dev_file = open(file_path, "r+", encoding='utf-8')
    json_string = dev_file.read()
    dev_file.close()

    body = json.loads(json_string)
    if 'deleted_devices' in body['data']:
        body['data']['deleted_devices'] = []

    dev_file = open(file_path, "w+", encoding='utf-8')
    dev_file.write(json.dumps(body, indent=2))
    dev_file.close()

    for _ in range(3):
        os.system('sync')

    print(file_path + " validate success")
    return


def check_entity_file(file_path):
    my_file = Path(file_path)
    if not my_file.exists():
        print(file_path + " is not exist")
        return
    entity_file = open(file_path, "r+", encoding='utf-8')
    json_string = entity_file.read()
    entity_file.close()

    body = json.loads(json_string)
    if 'deleted_entities' in body['data']:
        body['data']['deleted_entities'] = []

    entity_file = open(file_path, "w+", encoding='utf-8')
    entity_file.write(json.dumps(body, indent=2))
    entity_file.close()

    for _ in range(3):
        os.system('sync')

    print(file_path + " validate success")
    return

def initialize_pin():
    # Initialize GPIO pins for Zigbee and Thread modules
    print("Reset Zigbee module GPIOZ_1/GPIOZ_3...")
    # Zigbee reset: DB_RSTN1/GPIOZ_1
    # Zigbee boot: DB_BOOT1/GPIOZ_3
    try:
        subprocess.run(["gpioset", "0", "3=0"], check=True)
        time.sleep(0.2)
        subprocess.run(["gpioset", "0", "1=1"], check=True)
        time.sleep(0.2)
        subprocess.run(["gpioset", "0", "1=0"], check=True)
        time.sleep(0.2)
        subprocess.run(["gpioset", "0", "1=1"], check=True)
            
    except subprocess.CalledProcessError as e:
        print(f"Error executing Zigbee gpioset command: {e}")
    except Exception as e:
        print(f"Error initializing Zigbee GPIO pins: {e}")    
    
    return

def main_run(dir):
    initialize_pin()

    if not dir.endswith(os.sep):
        dir += os.sep
    dir += '.storage' + os.sep

    device_file = dir + 'core.device_registry'
    entity_file = dir + 'core.entity_registry'

    check_device_file(device_file)
    check_entity_file(entity_file)

    return

if __name__ == "__main__":
    main_run(args.home)
