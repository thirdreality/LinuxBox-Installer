# README

[English](./README_en.md)

该目录下的 cmake 脚本用于打包 openHAB 以及 zigbee2mqtt 相关依赖。在最终的安装过程中我们会尽可能的减少对网络的依赖，来加快安装速度。

如果你想通过 debian arm64 官方源的方式安装 openHAB 可以参考该文档：[reference](./reference.md)

## 构建前置条件

1. cmake
2. git
3. make (Ninja 也可以)
4. linux (不一定非得是 debian)

## 如何构建

```bash
cd thirdreality-openHAB && mkdir build && cd build
cmake ..
make package
```

构建结束后，所有的 deb 包都在 openHAB-0.1.1-Linux.tar.xz 中

## 如何安装

为了安装之后能够正常启动，你可能需要先烧录内置的 zigbee dongle 固件。
参考: <https://github.com/thirdreality/LinuxBox/wiki/How-to-burn-the-image-to-LinuxBox#3-flash-the-zigbee--thread-board>

### 通过 Usb installer 安装

1. 你可以将 `openHAB-<version>-Linux.tar.xz` 压缩包解压到 U盘中，确保 U盘根目录有 R3Archives 目录，并且其中包含 deb 包。
2. 将 U盘插入 linuxbox 顶部的 U 盘口，等待蓝灯亮起。

### 手动安装

1. 将压缩包中的 deb 通过 sftp 或者其他的方式拷贝到 linuxbox 中。
2. 进入 linuxbox 后台使用 dpkg -i 安装所有的 deb 包，最后使用 apt-get install -f -y 解决依赖问题。

## 启动

LinuxBox 重新上电后，zigbee2mqtt.service 和 openhab.service 会自动启动。或者手动在后台输入:

```bash
systemctl start zigbee2mqtt.service
systemctl start openhab.service
```

openhab 和 zigbee2mqtt 一般需要等待一会儿才能完全启动。

## OpenHAB 使用方法

先安装 mqtt binding，必要的配置项：

 1. ip: localhost
 2. port: 1883
 3. username: thirdreality
 4. password: thirdreality

mqtt binding 会自动扫描新的 things，并出现在 Settings/Things/INBOX 中。
出现 Zigbee2MQTT Bridge 后，可以通过该 thing 添加新的 zigbee 设备

1. 在 Zigbee2MQTT Bridge 的 Channels 页面，需要为 Permit Join 创建一个新的 Item，然后才可以控制 zigbee dongle 添加设备。
2. Permit Join 打开后，新加入的设备作为 things 同样会出现在 Settings/Things/INBOX 中。
3. 所有的 Things 都需要先配置 Channel 添加 Item，然后才能使用。
