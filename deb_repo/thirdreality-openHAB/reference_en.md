# OpenHAB Installation

[中文](./reference.md)

## Command-line Installation in the Background

For the overall process, refer to: <https://www.openhab.org/docs/installation/linux.html>

1. Connect to the linuxbox via serial port (baud rate 115200, no parity, 1 stop bit), and configure the wiki network using nmtui.
   1. After connecting to the network, use `ip address` to get the current IP address. It is recommended to log in to the linuxbox again using ssh to get a higher terminal speed.
      1. Refer to <https://github.com/thirdreality/LinuxBox/wiki/FAQ#q1-what-are-the-default-username-and-password>
2. Update the system package list
   1. `apt-get update`
      1. If you encounter the NO_PUBKEY issue, this is generally a system integration problem and unrelated to OpenHAB installation. It can be resolved using `gpg --export`; for specific operations, you can ask AI.
3. Install JDK (version: 21, architecture arm64)
   1. The JDK version must be 21 and 64-bit.
      1. Refer to <https://docs.azul.com/core/install/debian>
   2. After setting up the source, `apt install zulu21-jdk` will automatically install the appropriate 21 version of JDK for the architecture.
   3. If installing manually, you need to download the correct version (<https://cdn.azul.com/zulu/bin/zulu21.44.17-ca-jdk21.0.8-linux_arm64.deb>).
   4. After installation, use `jdk --version` to ensure the JDK version is correct. Sometimes the system may already have other versions of JDK installed; in this case, you need to use the `update-alternatives` command to switch to version 21.
4. Install openHAB according to the official guide
   1. Refer to <https://www.openhab.org/docs/installation/linux.html#installation>
   2. openHAB supports the arm64 architecture. We can follow the linux installation process for normal installation. There is no need to pay attention to the Armbian installation process provided in the official documentation.
      1. <https://www.openhab.org/docs/installation/armbian.html>
   3. If a warning like "doesn't support architecture 'armhf'" appears after `apt-get update`, there is no need to worry. The official openHAB source supports both arm64 and armhf architectures; this is just automatically skipping the unsupported architecture.
5. Start openHAB
   1. Refer to <https://www.openhab.org/docs/installation/linux.html#systems-based-on-systemd-e-g-debian-8-ubuntu-15-x-raspbian-jessie-and-newer>
   2. After opening the link `your-ip:8080` in a web browser, if you see a prompt like 'Service not found', you can try refreshing after a few minutes.
      1. The official prompt says that the first start may take up to 15 minutes for initialization.
            > The first start may take up to 15 minutes, this is a good time to reward yourself with hot coffee or a freshly brewed tea!

## Z2M Installation

Git repositories:

1. <https://github.com/fangzheli/zigbee-herdsman.git>
   1. branch: feat/blz
2. <https://github.com/fangzheli/zigbee2mqtt.git>
   1. branch: feat/blz-local-dev

These two repositories need to be cloned in the same directory. For installation methods, refer to the official zigbee2mqtt documentation: <https://www.zigbee2mqtt.io/guide/installation/01_linux.html>
