# LinuxBox Release Notes — 2026-07-23

ThirdReality LinuxBox (hubv3) 智能家居网关发布说明。

> **本版本是运行时切换到 Python 3.14 之后的第一个 release**，除 Python 运行时外，
> Home Assistant Core、Matter 服务端、Music Assistant 均随之完成大版本升级/迁移。

---

## ⚠️ 重要提示

- **Python 运行时 3.13 → 3.14.6**（`thirdreality-python3`），本系列首版。
- **Home Assistant Core 升级到 2026.7.3**（frontend 20260624.6），venv 迁移到
  Python 3.14。
- **Matter 服务端从 Python 迁移到 Node.js 的 matter.js server。** 停更的
  `python-matter-server[server]`（最后版本 8.1.2）不再使用，改为官方同款
  **matter.js server（npm `matter-server`，pin `1.2.8`）**，与旧实现 WebSocket
  协议兼容，首次启动会**自动迁移**旧的 `chip.json` / `<fabricid>.json` 数据。
  - 依赖系统自带 **Node.js ≥ 22.13**（armbian / buildroot 默认 24.x），Node 不打进 deb。
  - HA 侧 matter 集成客户端库随 HA 2026.7 改名拆分为 `matter-python-client` +
    `matter-ble-proxy`（pin `0.7.1`）。
  - **BLE 配对经 HA BLE proxy 执行**（`--ble-proxy`），不使用本地适配器直连
    （`--bluetooth-adapter`），原因见"问题分析"一节。
- **Music Assistant 升级到 2.9.9**（2.8.9 → 2.9.9）。2.9.0 起 MA 要求 Python ≥ 3.14，
  运行时升级后锁定解除。
- **本次发布未完成全流程测试**，请在生产环境部署前自行验证关键功能（Zigbee / Thread /
  Matter / 音频播放等），谨慎升级。尤其注意本轮 HA 依赖存在多个大版本跳变
  （zha 0.0.90→2.0.0、bleak→3.0.2、aioesphomeapi→45、universal-silabs-flasher→1.1.0 等）。

---

## 📦 Deb 包清单

| 包名 | 版本 | 说明 |
| --- | --- | --- |
| thirdreality-python3 | 3.14.6 | **升级**：Python 3.14 运行时（`/usr/local/python3`） |
| thirdreality-hacore | 2026.7.3 | **升级**：HA Core 2026.7.3 + 前端 20260624.6 + matter.js server 1.2.8 |
| thirdreality-music-assistant | 2.9.9 | **升级**：MA server 2.9.9（要求 Python ≥ 3.14） |
| thirdreality-otbr-agent | 2026.07.0 | 未变更，OpenThread Border Router (Thread 1.4, Web GUI :8080) |
| thirdreality-zigbee-mqtt | 2.11.0-rc | 未变更，Zigbee2MQTT + herdsman |
| thirdreality-hacore-config | 2025.10.0 | 未变更，HA 默认配置 |
| thirdreality-bridge | 0.9.2 | 未变更，hubv3 桥接服务 |
| thirdreality-board-firmware | 1.14.01 | 未变更，Zigbee/Thread 芯片固件刷写 |

> 版本以各包 `DEBIAN/control` 的 `Version` 字段为准。

---

## 本次周期主要变更

### thirdreality-python3 → 3.14.6
- 目标 Python 从 3.13.11 切换到 **3.14.6**（3.14 系列最新维护版），
  ssl / ctypes / sqlite3 / venv 真机验证正常。

### thirdreality-hacore → 2026.7.3
- **HA Core 2026.7.3 / frontend 20260624.6**；venv 从 Python 3.13 迁移到 3.14
  （构建脚本内所有 `lib64/python3.13` 路径、`preinst` 的 Python 校验同步更新到 3.14）。
- **Matter 服务端迁移到 matter.js server**：
  - 删除原 `/srv/matter_server` 的 Python venv 构建，改为 `npm install matter-server@1.2.8`
    到 `/srv/matter_server`（含 Node ≥ 22.13 校验、native 模块编译依赖 best-effort 安装、
    产物瘦身）。
  - `matter-server.service` 重写为 `node … MatterServer.js`，沿用旧存储目录
    `/var/lib/homeassistant/matter_server`（首启自动迁移）、`--vendorid 4939 --port 5580`，
    **BLE 采用 `--ble-proxy`**（经 HA 蓝牙栈代理，见下文问题分析）。
  - 移除外部 `chip-ota-provider-app` 的下载与打包（matter.js 内置 OTA）。
  - HA venv 客户端库 `python-matter-server==8.1.2` → `matter-python-client==0.7.1` +
    `matter-ble-proxy==0.7.1`。
  - `postinst` 增加 Node.js 存在性校验（缺失时告警，不中断安装）。
- **维护脚本按 matter.js 架构清理（移除 CHIP/python-matter-server 遗留）**：
  - `postinst`：删除针对旧 CHIP KV 存储的 `fix_matter_vendor_id()` 及其调用、
    删除 `/tmp/chip_kvs` 目录创建（matter.js 用 `--storage-path` 下的
    driver/wal/snapshot KV 分区，vendorId 仅由启动参数 `--vendorid` 提供、不落盘），
    脚本权限数组移除已删除的 `home_assistant_matter_fix.sh`；
  - `postrm`：删除 `/tmp/chip_kvs` 清理；
  - `preinst`：升级备份从只备旧 `chip.json` 扩展为备份整个
    `matter_server/config/` 与 `server-*/`（matter.js 实际数据目录；仍兼容备份
    旧 `chip.json`）；
  - `build.sh`：移除 `home_assistant_matter_fix.sh` 拷贝，并删除该脚本文件。
- **敏感数据目录加固**：`postinst` 对 `/var/lib/homeassistant/matter_server`
  设 `chmod 700`。matter.js 会把 WiFi 凭据等明文写入 `config/…/wal`，收紧目录
  权限避免非 root 用户读取（旧 python-matter-server 无此需求）。
- **依赖版本同步**：随 HA 2026.7 更新约 50 个依赖 pin。
- **Python 3.14 兼容性修复（真机发现）**：
  - zha 缺失问题：zigpy-cli 拖入的 `zigpy-zboss(<2)` 与 zha 2.0.0（需 zigpy 2.0）冲突
    → 改为 `--no-deps` 安装 zigpy-cli 跳过 zboss；
  - `serialx` 陈旧 pin 0.6.2 → 1.8.2（zigpy 2.0 需 ≥1.4.0），显式固定 `zha-quirks==2.1.1`；
  - 新增 `zigpy_cli_asyncio.patch`：Python 3.14 移除 `asyncio.get_event_loop()`
    无 loop 时自动创建的旧行为，导致 zigpy-cli 全部命令崩溃，补丁改为无 loop 时新建。
- **补丁适配**：`zha.patch` 针对 zha 2.0.0 重做（精确匹配，零 fuzz，真机验证
  RadioType.blz 注册生效、`/dev/ttyAML3` blz 电台探测正常）；`zigpy_cli.patch`
  同步 header 路径到 3.14。
- **离线 / 内网构建友好**：`build.sh` 幂等（venv 与 matter-server 已存在则零联网重复），
  可用环境变量 `NPM_REGISTRY_URL=<url>` 指定内网 npm 源。
- **工具 / 文档**：`sync_all_versions.py` 的 matter 版本源改为 npm registry、
  客户端库改名、移除 ota-provider 逻辑；README 更新架构说明。

### thirdreality-music-assistant → 2.9.9
- MA server 2.8.9 → **2.9.9**（2026-07-17 上游最新稳定版）。
- 2.9.0 起要求 Python ≥ 3.14；`build.sh` 的 Python 版本门槛同步从 3.13 提到 3.14。
- **上游坏 pin 规避**：2.9.9 的 `requirements_all.txt` 里 `audible==0.10.0` 元数据
  要求 Python <3.13，与 MA 自身 requires-python>=3.14 矛盾，导致依赖批量安装被 pip
  中止（0.11.0 又与 pillow==12.2.0 冲突，无法简单换版本）。`build.sh` 下载后直接
  移除该行预装。副作用：**Audible provider 在 Python 3.14 上暂不可用**（其 manifest
  pin ==0.10.0，属上游问题，其余 provider 不受影响），上游修复后移除此规避即可。
- **numkong 构建规避**：`usearch==2.25.3` 依赖 numkong（不 pin 版本），numkong
  最新 7.7.1 未发布 aarch64 wheel，pip 回退源码编译并在 gcc 12 上失败（NEON dotprod
  intrinsics 目标选项问题）。`build.sh` 显式 pin `numkong==7.7.0`（有 aarch64/cp314
  wheel），上游恢复发 wheel 后可移除。
- 2.9.x 引入 torch / transformers / librosa 音频分析栈（上游 beat-this 特性），
  venv 与 deb 体积显著增大。
- `requirements_all.txt` 安装失败改为致命错误（此前静默继续，会产出缺依赖的包）。
- HA 侧 `music-assistant-client` 保持 1.3.6。

---

## 问题分析：matter.js 迁移后 Matter BLE 配对失败

matter.js server 上线后真机 BLE 配对全部失败，而旧的 python-matter-server 在同一
环境可以配对成功。经真机 debug 日志逐层排查，确认存在**两个相互独立的问题**：

### 问题 1（主机侧，已修复）：noble raw HCI 与 bluetoothd/HA 蓝牙栈冲突

- matter.js 的本地 BLE（`--bluetooth-adapter 0`）使用 noble（`@stoprocent/noble`），
  直接打开 raw HCI socket 操作 hci0，**绕过 BlueZ**。
- 本机 hci0 同时被 bluetoothd 和 HA bluetooth 集成（bleak Adv Monitor 持续扫描）占用。
  bluetoothd 会接管/断开"不是它建立的" LE 连接（journal 实锤：
  `Failed to disconnect device` 与对配对目标设备的 `store_conn_param()` 记录）。
- 表现：BLE 连接反复中断，配对最多进行到 attestation 即被掐断。
- python-matter-server 之所以正常，是因为 CHIP SDK 走 BlueZ D-Bus，与 bluetoothd
  协作而非竞争。
- **修复**：`matter-server.service` 改为 `--ble-proxy`，BLE 配对经 HA 的
  `matter-ble-proxy`（bleak/BlueZ）代理执行，noble 不再触碰 hci0。
  修复后真机验证：BLE proxy 链路稳定工作 69 秒、数百个 BTP 分片零差错，
  PASE / 设备认证（Bouffalo PAA/PAI/DAC）/ CSR / addTrustedRootCertificate /
  addNoc 全部成功。

### 问题 2（设备侧，待固件修复）：Bouffalo 设备收到 WiFi 凭据后抢跑断开 BLE

- 测试设备：Smart Color Night Light（VID 0x1407，BouffaloLab 单芯片 BLE/WiFi 方案，
  CSA 认证 CSA23158MAT40671-24）。
- 复现（两次独立尝试签名完全一致）：`addOrUpdateWiFiNetwork` 成功返回
  （networkingStatus 0）后约 **5~6 秒**，设备在 commissioner 发出
  `connectNetwork` **之前**单方面断开 BLE——固件收到凭据即刻去连 WiFi，
  单射频芯片连 WiFi 就踢掉 BLE。
- 关键矛盾：设备的 GeneralCommissioning 声明 `supportsConcurrentConnection = true`，
  但实际行为是非并发。matter.js 严格按并发流程执行（addOrUpdate 之后还有一次
  networkCommissioning 属性读取，之后才发 connectNetwork），正好输掉与固件抢跑的
  时间窗口，并将 BLE 断链判定为致命错误。
- python-matter-server（CHIP SDK）能配上是**时序上的侥幸**：AddOrUpdate 应答后
  立即发 ConnectNetwork（无中间读取），赶在 5 秒窗口内送达，之后即使 BLE 断开
  也容忍并转 mDNS 操作发现完成 CASE。
- **排除项：路由器 AP 隔离不存在。** 真机验证同一 AP 下客户端间 IPv4/IPv6
  （含 fe80 链路本地）unicast、TCP 直连全部正常；早前"发现地址但 unreachable"
  是设备半次配对后离线留下的 mDNS 过期缓存。
- **修复方向（固件团队）**，二选一：
  1. `supportsConcurrentConnection` 改为 false（改动最小，matter.js 会走
     非并发流程，与固件实际行为匹配）；
  2. 固件真正支持并发：收到凭据后保持 BLE，等 `connectNetwork` 再切射频。
- 同时建议向 matter.js 上游提 issue，请求对"声明并发但在 connectNetwork 前
  断 BLE"的设备做容错（addNoc 已成功，转 mDNS 操作发现即可完成配对）。

---

## 📥 升级 / 验证建议

- 依赖前置包 `thirdreality-python3`（≥ 3.14）与系统自带 **Node.js ≥ 22.13**。
- 建议按两阶段流程打包：`./build.sh --rebuild` → 首启预热首启依赖 → 复核 patch 日志与
  首启依赖 → 再次 `./build.sh` 重新打包。
- 部署后确认：
  - `systemctl status matter-server` 正常、`matter_server.log` 有首启迁移记录、
    HA matter 集成连接 `ws://localhost:5580/ws` 正常；
  - `server_info` 中 `ble_proxy_enabled: true`，且 HA bluetooth 集成已加载
    （BLE proxy 依赖 HA 的蓝牙栈；若未启用 bluetooth 集成，BLE 配对不可用）；
  - Zigbee(ZHA) 与音频等关键链路可用。
- **已知问题**：Matter over WiFi（BLE 配对）在 Bouffalo 设备固件修复前预期仍失败
  （见问题分析）；Matter over LAN（`network_only`）与已配对设备控制不受影响。
- Music Assistant 2.9.9 为大版本跳变后的首次收编，建议验证音源播放、
  provider 登录与 HA 集成连接。
- **强烈建议先在测试设备上验证再批量升级**（本轮含多个上游大版本跳变，未全量测试）。
