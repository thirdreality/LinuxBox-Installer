# README

The CMake scripts in this directory are used to package openHAB and its zigbee2mqtt dependencies. During the final installation, we will minimize network dependencies as much as possible to accelerate the installation speed.

If you prefer to install openHAB through the official Debian ARM64 repositories, please refer to this documentation: [reference](./reference_en.md)

## Prerequisites for Building

1. CMake
2. Git
3. Make
4. Linux (Debian is not necessary)

## How to Build

```bash
cmake --workflow --preset openhab
```

After the build is complete, all deb packages will be located in the build/R3Archives directory.

### About openHAB Versions

The current stable version of openHAB is 4.3.6, which supports mqtt but does not support matter. Version 5.0.0 has not yet been released as a stable version; its overall usage is not as smooth as 4.3.6, and there are some issues with mqtt support,
but it does support matter.

If you want to try it, you can modify the value of the `CONFIG_OPENHAB_VERSION` field in CMakePresets.json.

## How to Install

To ensure proper startup after installation, you may need to first flash the built-in Zigbee dongle firmware.
Refer to: <https://github.com/thirdreality/LinuxBox/wiki/How-to-burn-the-image-to-LinuxBox#3-flash-the-zigbee--thread-board>

### Using USB Installer

1. Extract the `openHAB-<version>-Linux.tar.xz` archive to a USB drive, ensuring the USB root directory contains an `R3Archives` folder with all `.deb` packages.
2. Insert the USB drive into the top USB port of the LinuxBox and wait for the blue light to illuminate.

### Manual Installation

1. Copy the `.deb` packages from the archive to the LinuxBox via SFTP or other methods.
2. Access the LinuxBox background terminal and install all packages using:

   ```bash
   dpkg -i *.deb
   apt-get install -f -y  # Resolve dependencies
   ```

## Startup

After rebooting the LinuxBox, the `zigbee2mqtt.service` and `openhab.service` will start automatically. Alternatively, manually start them with:

```bash
systemctl start zigbee2mqtt.service
systemctl start openhab.service
```

Note: openHAB and zigbee2mqtt may take some time to fully initialize.

## Using OpenHAB

1. First install the **MQTT Binding**. Configure with these essential parameters:
   - IP: `localhost`
2. The MQTT binding will automatically scan for new devices, which will appear under **Settings > Things > INBOX**.
3. After the **Zigbee2MQTT Bridge** appears, use it to add Zigbee devices:
   - On the Bridge's **Channels** page, create a new **Item** for `Permit Join` to enable device pairing.
   - When `Permit Join` is active, new devices will appear in **Settings > Things > INBOX**.
   - All Things require **Channel configuration** (adding Items) before they can be used.
