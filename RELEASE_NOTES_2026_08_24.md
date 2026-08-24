# LinuxBox Release Notes — 2026-08-24

ThirdReality LinuxBox (hubv3) 智能家居网关发布说明。

> **本次为增量发布，仅更新 `thirdreality-hacore`（2026.8.0 → 2026.8.3）。**
> 其余 deb 包沿用 2026-08-06 发布版本，未变更。背景与历史变更请参见
> `RELEASE_NOTES_2026_08_06.md`。

---

## ⚠️ 重要提示

- **Home Assistant Core 2026.8.0 → 2026.8.3**（上游补丁版），
  frontend 随集成要求升级到 **20260729.7**。
- **matter.js server（npm `matter-server`）1.3.3 → 1.4.0**，底层
  `@matter/main` 升至 **0.17.9**。
- **ZHA 栈保持不变**：zha 2.1.0 / zha-quirks 2.2.0 / matter-python-client 1.3.0
  （2026.8.3 各集成 manifest 未 bump 这些库），`zha.patch` 等三个补丁经复查
  仍在位（首启补装依赖后再次确认）。
- 本增量做了启动冒烟测试（0 ERROR、无 `KeyError: 'blz'`），并按惯例执行了
  **两阶段打包**（首启让 HAcore 自动补装运行期依赖后再重新打包）。
  生产部署前请自行验证关键功能。

---

## 📦 Deb 包清单

| 包名 | 版本 | 说明 |
| --- | --- | --- |
| thirdreality-python3 | 3.14.6 | 未变更 |
| **thirdreality-hacore** | **2026.8.3** | **升级**：HA Core 2026.8.3 + matter.js server 1.4.0 |
| thirdreality-music-assistant | 2.9.9 | 未变更 |
| thirdreality-otbr-agent | 2026.07.0 | 未变更 |
| thirdreality-zigbee-mqtt | 2.11.0-rc | 未变更 |
| thirdreality-hacore-config | 2025.10.0 | 未变更 |
| thirdreality-bridge | 0.9.2 | 未变更 |
| thirdreality-board-firmware | 1.14.01 | 未变更 |

> 版本以各包 `DEBIAN/control` 的 `Version` 字段为准。

---

## 本次周期主要变更

### thirdreality-hacore → 2026.8.3

- **HA Core 2026.8.3** / frontend 20260729.7。
- **matter.js server 1.3.3 → 1.4.0**（`@matter/main` 0.17.9）；
  `matter-server.service` 保持 `--ble-proxy`。
- 依赖 pin 按 2026.8.3 各集成 manifest 核对：仅 frontend 需升
  （20260729.5 → 20260729.7）；zha 2.1.0 / zha-quirks 2.2.0 /
  matter-python-client 1.3.0 均未变。
- **补丁核对**：zha 未被重装，`zha.patch`（blz 电台）、`zigpy_cli.patch`、
  `zigpy_cli_asyncio.patch` 三者首启后复查全部在位；deb 内已验证 `zigpy_blz`。
- **构建说明**：2026.8.3 上游发布当时清华镜像尚未同步，HA 本体此次改用官方
  PyPI 安装；其余包沿用镜像。两阶段打包（首启预热 → 重打）已完成。

---

## 📥 升级 / 验证建议

- 仅需替换 `thirdreality-hacore`（2026.8.3）；其余包沿用现版。
- 依赖前置包 `thirdreality-python3`（≥ 3.14）与系统自带 **Node.js ≥ 22.13**。
- 部署后确认：
  - `systemctl status matter-server` 正常、HA matter 集成连接
    `ws://localhost:5580/ws` 正常；
  - ZHA（blz 电台 `/dev/ttyAML3`）加载正常、无 `KeyError: 'blz'`；
  - Matter over WiFi（BLE 配对）与音频等关键链路可用。
- **建议先在测试设备上验证再批量升级。**
