# LinuxBox Release Notes — 2026-07-20

ThirdReality LinuxBox (hubv3) 智能家居网关发布说明。

---

## ⚠️ 重要提示

- **本次 deb 为 Python 3.13 系列的最后一个版本。** 上游 Home Assistant / Music
  Assistant 等组件正在向 Python 3.14 迁移，后续版本将不再基于 3.13 构建。
- **matter-server 已从 Python 迁移到 Node.js**，Python 版 matter-server 的最后一个版本
  为 **8.1.2**（本次发布仍随 hacore 打包 8.1.2）；后续将不再提供 Python 版 matter-server。
- **本次发布是工程师抽空制作，肯定是试过几次的，但未能按照流程完成全部测试**，请在生产环境部署前自行验证关键功能（Zigbee / Thread /
  Matter / 音频播放等），谨慎升级。

---

## 📦 Deb 包清单

| 包名 | 版本 | 说明 |
| --- | --- | --- |
| thirdreality-python3 | 3.13.11 | Python 3.13 运行时（`/usr/local/python3`），本系列最后一版 |
| thirdreality-hacore | 2026.2.3 | Home Assistant Core + 前端 + matter-server 8.1.2 |
| thirdreality-music-assistant | 2.8.9 | ⚠️Music Assistant，最新支持 Python 3.13 的稳定版 |
| thirdreality-otbr-agent | 2026.07.0 | OpenThread Border Router (Thread 1.4, Web GUI) |
| thirdreality-zigbee-mqtt | 2.11.0-rc | Zigbee2MQTT + herdsman |
| thirdreality-hacore-config | 2025.10.0 | HA 默认配置 |
| thirdreality-bridge | 0.9.2 | hubv3 桥接服务 |
| thirdreality-board-firmware | 1.14.01 | Zigbee/Thread 芯片固件刷写 |

> 版本以各包 `DEBIAN/control` 的 `Version` 字段为准。

### ⬇️ 下载

- [python3_3.13.11.deb](https://github.com/thirdreality/LinuxBox-Installer/releases/download/2026.2.3/python3_3.13.11.deb)
- [hacore_2026.2.3.deb](https://github.com/thirdreality/LinuxBox-Installer/releases/download/2026.2.3/hacore_2026.2.3.deb)
- [music-assistant_2.8.9.deb](https://github.com/thirdreality/LinuxBox-Installer/releases/download/2026.2.3/music-assistant_2.8.9.deb)
- [otbr-agent_2026.07.0.deb](https://github.com/thirdreality/LinuxBox-Installer/releases/download/2026.2.3/otbr-agent_2026.07.0.deb)
- [zigbee-mqtt_2.11.0-rc.deb](https://github.com/thirdreality/LinuxBox-Installer/releases/download/2026.2.3/zigbee-mqtt_2.11.0-rc.deb)

> 📌 另外建议一并下载此前发布、本次未变更的配置包（HA 默认配置，安装 hacore 前需要）：
> [hacore-config_2025.10.0.deb](https://github.com/thirdreality/LinuxBox-Installer/releases/download/2025.12.0/hacore-config_2025.10.0.deb)（来自 2025.12.0 release，版本未变）。

### 本次周期主要变更

- **music-assistant → 2.8.9**：从 2.6.3 升级到最新支持 Python 3.13 的稳定版
  （2.9.0 起上游要求 Python 3.14）。构建接入统一的 OOM 守护（临时 swap + 编译期停无关
  服务），并修正了 Python 版本比较的字典序 bug。
- **otbr-agent**：修复了 `DEBIAN/control` 中多余的 `bind9` 依赖。该依赖并非运行时必需
  （NAT64/DNS64 由 OpenThread 内建 translator + `OTBR_DNS_UPSTREAM_QUERY` 处理），
  在未安装 bind9 的设备上会导致 `dpkg -i` 因依赖不满足而安装失败。
- **otbr-agent**：恢复了 OpenThread Web GUI，监听端口 **8080**（`http://<设备IP>:8080`）。

---

## 💿 Armbian 镜像

本次额外提供两个 Armbian 系统镜像：

- **Armbian 6.6.120**（新内核）
- **Armbian 5.10.247**（旧内核，兼容用途）

> ⚠️ **Armbian 6.6.120 尚未针对 `music-assistant_2.8.9.deb` 做定制**，不建议在 Armbian
> 6.6.120 平台上直接安装 Music Assistant。

### 镜像变更

1. **调整 `/boot` 分区** —— 避免 ext4 分区写坏时导致设备完全无法启动，提升系统的可恢复性。
2. **内置 nodejs 与 mosquitto** —— 预装常用运行依赖，减少首次部署时的联网安装步骤
   （otbr-agent web GUI 构建、Zigbee2MQTT MQTT broker 等直接可用）。
3. **调整 MMC 参数** —— 降低 eMMC/MMC 写入错误的发生概率，提升存储稳定性。
4. **修正并更新 USB 安装脚本，以及 factory reset（恢复出厂）脚本**。

### 未包含 / 待验证

- **无线信号复杂环境下， WIFI有概率丢失AP，强制重启 wifi / bluetooth 硬件** 的相关改动**未测试、本次未应用**（未纳入本次发布），
  留待后续验证后再启用。

---

## 📥 升级建议

- 由于本版为 Python 3.13 系列收尾版本且未全量测试，建议先在测试设备上验证后再批量升级。
- 若从旧版本升级 otbr-agent，注意新版依赖列表已移除 bind9；无 Thread 芯片或不使用 Thread
  的设备，可直接 `systemctl disable --now hubv3-otbr-agent` 关闭整套 OTBR 服务。
