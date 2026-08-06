# LinuxBox Release Notes — 2026-08-06

ThirdReality LinuxBox (hubv3) 智能家居网关发布说明。

> **本次为增量发布，仅更新 `thirdreality-hacore`（2026.7.4 → 2026.8.0）。**
> 其余 deb 包沿用 2026-07-28 发布版本，未变更。背景与历史变更请参见
> `RELEASE_NOTES_2026_07_28.md` / `RELEASE_NOTES_2026_07_23.md`。

---

## ⚠️ 重要提示

- **Home Assistant Core 2026.7.4 → 2026.8.0**（上游月度大版本），
  frontend 随集成要求升级到 **20260729.5**。
- **matter.js server（npm `matter-server`）1.3.1 → 1.3.3**，底层
  `@matter/main` 升至 **0.17.7 正式版**——此前 issue #918 的 BLE 配对修复
  （PR #4139）已随正式版收编，不再依赖 alpha 快照。该修复此前已在真机
  验证通过（Bouffalo 设备 BLE 配对全流程成功，见 07-29 脱敏日志）。
- **ZHA 栈随 HA 2026.8 升级**：zha 2.0.1 → **2.1.0**、zha-quirks → **2.2.0**、
  zigpy → 2.1.0（radio 后端 bellows 1.0.0、zigpy-deconz 1.0.0 等随动）。
  `zha.patch`（注册 blz/Bouffalo 电台）已确认对 zha 2.1.0 干净适用并重新
  应用，真机冒烟测试通过（HA 启动 0 ERROR、无 `KeyError: 'blz'`）。
- **matter 集成客户端库** matter-python-client 0.7.1 → **1.3.0**
  （matter-ble-proxy 保持 0.7.1）。
- 本增量做了启动冒烟测试，未做全流程回归，生产部署前请自行验证关键功能。

---

## 📦 Deb 包清单

| 包名 | 版本 | 说明 |
| --- | --- | --- |
| thirdreality-python3 | 3.14.6 | 未变更 |
| **thirdreality-hacore** | **2026.8.0** | **升级**：HA Core 2026.8.0 + matter.js server 1.3.3 |
| thirdreality-music-assistant | 2.9.9 | 未变更 |
| thirdreality-otbr-agent | 2026.07.0 | 未变更 |
| thirdreality-zigbee-mqtt | 2.11.0-rc | 未变更 |
| thirdreality-hacore-config | 2025.10.0 | 未变更 |
| thirdreality-bridge | 0.9.2 | 未变更 |
| thirdreality-board-firmware | 1.14.01 | 未变更 |

> 版本以各包 `DEBIAN/control` 的 `Version` 字段为准。

---

## 本次周期主要变更

### thirdreality-hacore → 2026.8.0

- **HA Core 2026.8.0** / frontend 20260729.5。
- **依赖 pin 按 2026.8.0 各集成 manifest 对齐**（集成库不在 HA 核心依赖中，
  就地升级不会自动带上，需手动同步）：
  - zha==2.1.0、zha-quirks==2.2.0（zigpy 2.1.0 随动）；
  - matter-python-client==1.3.0（matter-ble-proxy==0.7.1 不变）；
  - home-assistant-frontend==20260729.5。
- **matter.js server 1.2.8→1.3.1→**（本次）**1.3.3**：`@matter/main` 0.17.7
  正式版，含 BLE 配对断链容错（matterjs-server#918 / matter.js#4139，
  已真机验证）。`matter-server.service` 保持 `--ble-proxy`。
- **补丁核对（重点）**：zha 2.1.0 重装会冲掉 blz 补丁，构建时由
  `tr_build_guard_start` 后的幂等补丁流程自动重打；`zigpy_cli.patch`、
  `zigpy_cli_asyncio.patch` 不受影响。deb 内已验证 `zigpy_blz` 在位。
- 维护性修复延续 07-31 系列（随本 deb 首次成套发布）：
  - ZHA 模式 `home_assistant_zha_enable.py` 只禁用 zigbee2mqtt，
    **不再停用 mosquitto**（消除与 z2m post-fix 的安装期互相打架）；
  - build.sh 补丁应用幂等化（防原地升级丢补丁）、纯重打包路径 OOM 防护。

---

## 📥 升级 / 验证建议

- 仅需替换 `thirdreality-hacore`（2026.8.0）；其余包沿用现版。
- 依赖前置包 `thirdreality-python3`（≥ 3.14）与系统自带 **Node.js ≥ 22.13**。
- 部署后确认：
  - `systemctl status matter-server` 正常、HA matter 集成连接
    `ws://localhost:5580/ws` 正常；
  - ZHA（blz 电台 `/dev/ttyAML3`）加载正常、无 `KeyError: 'blz'`；
  - Matter over WiFi（BLE 配对）可用（0.17.7 正式版首次收编，建议抽测一台
    Bouffalo 设备复核）；
  - 音频等关键链路可用。
- ZHA 栈本轮多个组件大版本跳变（zha 2.1 / zigpy 2.1 / bellows 1.0），
  建议重点回归 Zigbee 配对与既有设备控制。
- **建议先在测试设备上验证再批量升级。**
