# LinuxBox Release Notes — 2026-07-28

ThirdReality LinuxBox (hubv3) 智能家居网关发布说明。

> **本次为增量发布，仅更新 `thirdreality-hacore`（2026.7.3 → 2026.7.4）。**
> 其余 deb 包均沿用 2026-07-23 发布版本，未变更。基础平台（Python 3.14、matter.js
> 服务端架构、BLE proxy 配对链路等）延续上一个 release，背景请参见
> `RELEASE_NOTES_2026_07_23.md`。

---

## ⚠️ 重要提示

- **Home Assistant Core 2026.7.3 → 2026.7.4**（frontend 保持 20260624.6）。
- **matter.js server（npm `matter-server`）1.2.8 → 1.3.1**，随之底层
  `@matter/*` 提升到 `0.17.7-alpha.0-20260723-8a6b27aed`。此 alpha 快照**包含了
  matter.js PR #4139**（详见下文"Matter BLE 配对修复")。
- **matter.js 上游号称已修复此前记录的 Matter over WiFi（BLE）配对 bug**
  （matterjs-server issue #918 / matter.js PR #4139），但**尚未在真机上验证**，
  升级后请务必用 Bouffalo 设备实测确认。
- 本增量未做全流程回归测试，生产部署前请自行验证关键功能。

---

## 📦 Deb 包清单

| 包名 | 版本 | 说明 |
| --- | --- | --- |
| thirdreality-python3 | 3.14.6 | 未变更 |
| **thirdreality-hacore** | **2026.7.4** | **升级**：HA Core 2026.7.4 + matter.js server 1.3.1 |
| thirdreality-music-assistant | 2.9.9 | 未变更 |
| thirdreality-otbr-agent | 2026.07.0 | 未变更 |
| thirdreality-zigbee-mqtt | 2.11.0-rc | 未变更 |
| thirdreality-hacore-config | 2025.10.0 | 未变更 |
| thirdreality-bridge | 0.9.2 | 未变更 |
| thirdreality-board-firmware | 1.14.01 | 未变更 |

> 版本以各包 `DEBIAN/control` 的 `Version` 字段为准。

---

## 本次周期主要变更

### thirdreality-hacore → 2026.7.4

- **Home Assistant Core 2026.7.3 → 2026.7.4**（上游维护版；frontend、matter 客户端库
  `matter-python-client` / `matter-ble-proxy` 0.7.1 等其余 pin 不变）。
- **matter.js server 1.2.8 → 1.3.1**（`build.sh` 的 `MATTER_SERVER_NPM_VERSION`
  同步更新）。底层依赖随之提升：`@matter/main` =
  `0.17.7-alpha.0-20260723-8a6b27aed`（含 PR #4139 的 BLE 配对修复提交 `8a6b27aed`）。
- `matter-server.service` 保持 `--ble-proxy`（经 HA BLE proxy 配对），
  `postinst` 保持 matter.js 架构（无 `fix_matter_vendor_id`、
  `/var/lib/homeassistant/matter_server` 收紧为 `chmod 700`），与 2026.7.3 一致。

---

## Matter BLE 配对修复（上游 PR #4139，待真机验证）

上一 release（2026-07-23）在"问题分析"中记录了 **问题 2**：Bouffalo 单射频设备
声明 `supportsConcurrentConnection = true`，却在 `addOrUpdateWiFiNetwork` 成功后、
commissioner 发出 `connectNetwork` **之前**约 5~6 秒单方面断开 BLE，导致 matter.js
将其判为致命错误、配对失败（而旧的 python-matter-server 因时序侥幸能配上）。

- 我们据此向 matter.js 上游提交了 **matterjs-server issue #918**。
- 维护者 Apollon77 以 **matter.js PR #4139** 修复，已于 **2026-07-23 合入 main**，
  标注 "fixed — awaits validation feedback"。
- **修复思路正是我们建议的方案二**：`AddNOC` 成功后，若设备在并发流程中提前断开
  BLE，不再判定为致命错误，转为非并发流程（转 mDNS 操作发现完成 CASE）；
  上游还将容错范围扩展到 `addOrUpdateWiFiNetwork` 与 networks 属性读取环节。
- 本 release 通过升级 matter-server 到 1.3.1 纳入了该修复（`@matter/main` 快照含提交
  `8a6b27aed`）。

> **注意**：上游仅"声称修复、等待验证反馈"，**我们尚未在真机复测**。
> 升级后请用 Smart Color Night Light（VID `0x1407` / PID `0x1088`，BouffaloLab
> 单芯片 BLE/WiFi）等 Bouffalo 设备实测 BLE 配对是否恢复正常，并将结果反馈上游 issue。

---

## 📥 升级 / 验证建议

- 仅需替换 `thirdreality-hacore`（2026.7.4）；其余包沿用 2026-07-23 版本。
- 依赖前置包 `thirdreality-python3`（≥ 3.14）与系统自带 **Node.js ≥ 22.13**。
- 部署后确认：
  - `systemctl status matter-server` 正常、HA matter 集成连接
    `ws://localhost:5580/ws` 正常；
  - **重点验证 Matter over WiFi（BLE）配对**：用 Bouffalo 设备实测 PR #4139 是否
    真正解决问题 2；Matter over LAN 与已配对设备控制不受影响。
  - Zigbee 与音频等关键链路可用。
- **强烈建议先在测试设备上验证再批量升级。**
