# LinuxBox-Installer

Quick installer for HomeAssistant, zigbee2mqtt, Homekit bridge etc

## install-home-assistant-core

Official Document: [Jump to home-assistant.io](https://www.home-assistant.io/installation/linux#install-home-assistant-core)


Lastest version:

- python3_3.14.6.deb(3.14.6) [Download python3](https://github.com/thirdreality/LinuxBox-Installer/releases/download/2026.7.4/python3_3.14.6.deb)
- hacore-config_2025.10.0.deb [Download hacore-config](https://github.com/thirdreality/LinuxBox-Installer/releases/download/2025.12.0/hacore-config_2025.10.0.deb)
- hacore_2026.10.2.deb [Download hacore](https://github.com/thirdreality/LinuxBox-Installer/releases/download/2026.10.2/hacore_2026.10.2.deb)
- otbr-agent_2026.10.0.deb [Download otbr-agent](https://github.com/thirdreality/LinuxBox-Installer/releases/download/2026.10.2/otbr-agent_2026.10.0.deb)
- zigbee-mqtt_2.11.0-rc.deb [Download zigbee-mqtt](https://github.com/thirdreality/LinuxBox-Installer/releases/download/2026.2.3/zigbee-mqtt_2.11.0-rc.deb)  

- board_firmware_1.14.01.deb [Download board-firmware](https://github.com/thirdreality/LinuxBox-Installer/releases/download/2025.11.0/board_firmware_1.14.01.deb)

## install-OpenHab

To to continue ...



## USB-AUTOMATION-INSTALLATION

### 1、Software Only

On An empty USB storage:
```
.
└── R3Install
    ├── hacore_2026.10.2.deb
    ├── hacore-config_2025.10.0.deb
    ├── otbr-agent_2026.10.0.deb
    ├── python3_3.14.6.deb
    └── zigbee-mqtt_2.11.0-rc.deb
```


### 2、Software With zigbee/thread Board Flash
On An empty USB storage:
```
.
└── R3Install
    ├── board_firmware_1.14.01.deb
    ├── .force_board_flash  <----------------
    ├── hacore_2026.10.2.deb
    ├── hacore-config_2025.10.0.deb
    ├── otbr-agent_2026.10.0.deb
    ├── python3_3.14.6.deb
    └── zigbee-mqtt_2.11.0-rc.deb
```
