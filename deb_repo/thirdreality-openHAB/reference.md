# OpenHAB 安装

[English](./reference_en.md)

## 后台命令行安装

整体流程参考：<https://www.openhab.org/docs/installation/linux.html>

1. 使用串口连接 linuxbox (波特率 115200，无奇偶校验，1 bit 停止位)，并使用 nmtui 配置 wiki 网络。2. 连接网络后使用 ip address 获取当前 ip 地址，推荐使用 ssh 重新登陆 linuxbox 以获取更高的终端速度。
   1. 参考 <https://github.com/thirdreality/LinuxBox/wiki/FAQ#q1-what-are-the-default-username-and-password>
2. 更新系统安装包列表
   1. apt-get update
      1. 如果遇见 NO_PUBKEY 问题，该问题一般为系统集成问题。和 OpenHAB 安装无关，可以通过 gpg --export 解决，具体操作可以询问 AI。
3. 安装 jdk (version: 21, architecture arm64)
   1. jdk 版本必须是 21 版本，且必须是 64 位的。
      1. 参考 <https://docs.azul.com/core/install/debian>
   2. 设定源之后, apt install zulu21-jdk 会自动安装合适的架构的 21 版本的 jdk。
   3. 如果是手动安装，则需要下载正确的版本（<https://cdn.azul.com/zulu/bin/zulu21.44.17-ca-jdk21.0.8-linux_arm64.deb>）。
   4. 安装完成后使用 jdk --version 确保 jdk 版本是正确的。有时候系统本身可能已经存在其它版本的 jdk，此时需要使用 update-alternatives 命令将版本切换到 21 版本。
4. 按照官方指南安装 openHAB
   1. 参考 <https://www.openhab.org/docs/installation/linux.html#installation>
   2. openHAB 支持 arm64 架构，我们按照 linux 安装流程，正常安装即可。无需在意官方文档提供的 Armbian 安装流程。
      1. <https://www.openhab.org/docs/installation/armbian.html>
   3. apt-get update 之后如果出现 doesn't support architecture 'armhf' 警告，则无需担心。openHAB 官方源中同时支持 arm64 和 armhf 架构，这里只是自动跳过不支持的架构。
5. 启动 openHAB
   1. 参考 <https://www.openhab.org/docs/installation/linux.html#systems-based-on-systemd-e-g-debian-8-ubuntu-15-x-raspbian-jessie-and-newer>
   2. 网页打开 your-ip:8080  链接后，如果发现 'Service not found' 之类的提示，可以过个几分钟在刷新一下试试。
      1. 官方提示第一次启动可能最多需要 15 分钟的时间去初始化。
            > The first start may take up to 15 minutes, this is a good time to reward yourself with hot coffee or a freshly brewed tea!

## Z2M 安装

Git repo:

1. <https://github.com/fangzheli/zigbee-herdsman.git>
   1. branch: feat/blz
2. <https://github.com/fangzheli/zigbee2mqtt.git>
   1. branch: feat/blz-local-dev

这两个仓库需要 clone 在同一个目录下。安装方式参考 zigbee2mqtt 官方文档：<https://www.zigbee2mqtt.io/guide/installation/01_linux.html>
