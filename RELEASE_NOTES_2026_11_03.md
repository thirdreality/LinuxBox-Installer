# LinuxBox Release Notes — 2026-11-03

ThirdReality LinuxBox (hubv3) 智能家居网关发布说明。

> 本次 2 个 deb 包有变更：`thirdreality-hacore`（含 matter-server）与
> `thirdreality-otbr-agent`。其余包沿用原 release，未变更。
> 历史变更请参见 `RELEASE_NOTES_2026_10_22.md` 及更早文档。

---

## ⚠️ 重要提示

- **Home Assistant Core 2026.10.2 → 2026.10.4**，frontend 随之升级到
  **20260930.5**。matter / thread / otbr / zha 集成的依赖在两个版本间**没有变化**。
- **matter-server（matter.js）1.4.0 → 1.5.5**，与 HA 官方 app
  [`app-matter-server`](https://github.com/home-assistant/app-matter-server) 当前使用的版本一致。
- **OpenThread Border Router v2026.10.0 → v2026.11.0**（commit `76fb21d6`）。
  **本次领先于 HA 官方 app**：截至发布日，
  [`app-openthread-border-router`](https://github.com/home-assistant/app-openthread-border-router)
  的 beta 仍是 v2026.10.0，stable 是 v2026.09.0。
- **修复 Thread 射频复位时序**：此前每次开机，射频都会在 otbr-agent 已经连上之后
  被复位一次，agent 要靠 RCP 恢复机制才能救回来，详见第三节。
- hacore 补装了 8 个此前每次首启都要现场下载的依赖，**离线设备上 matter / otbr /
  zha / bluetooth 不再因此加载失败**，详见第二节。
- hacore 的依赖版本改为遵守 HA 的 `package_constraints.txt`。此前首启时 HA 会把
  `cffi` 等 11 个包降级，导致 `xiaomi_ble` 等集成在**首次启动时加载失败、重启一次才
  恢复**，详见第二节。
- hacore 中 11 个预装依赖此前落后于 HA 的要求（其中 3 个甚至低于 HA 自己的
  `package_constraints.txt`），本次一并对齐，详见第二节。

---

## 一、本次发布的包版本

本次 release tag：**`2026.10.4`**

| 包 | 版本 | 状态 | 下载 |
|---|---|---|---|
| **thirdreality-hacore** | **2026.10.4** | 升级（← 2026.10.2） | [hacore_2026.10.4.deb](https://github.com/thirdreality/LinuxBox-Installer/releases/download/2026.10.4/hacore_2026.10.4.deb) |
| **thirdreality-otbr-agent** | **2026.11.0** | 升级（← 2026.10.0） | [otbr-agent_2026.11.0.deb](https://github.com/thirdreality/LinuxBox-Installer/releases/download/2026.10.4/otbr-agent_2026.11.0.deb) |
| thirdreality-matter2mqtt | 1.4.0-tr.3 | 未变更 | [matter2mqtt_1.4.0-tr.3.deb](https://github.com/thirdreality/LinuxBox-Installer/releases/download/2026.10.2/matter2mqtt_1.4.0-tr.3.deb) |
| thirdreality-zigbee-mqtt | 2.11.0-rc | 未变更 | [zigbee-mqtt_2.11.0-rc.deb](https://github.com/thirdreality/LinuxBox-Installer/releases/download/2026.2.3/zigbee-mqtt_2.11.0-rc.deb) |
| thirdreality-hacore-config | 2025.10.0 | 未变更 | [hacore-config_2025.10.0.deb](https://github.com/thirdreality/LinuxBox-Installer/releases/download/2025.12.0/hacore-config_2025.10.0.deb) |
| thirdreality-python3 | 3.14.6 | 未变更 | [python3_3.14.6.deb](https://github.com/thirdreality/LinuxBox-Installer/releases/download/2026.7.4/python3_3.14.6.deb) |
| thirdreality-music-assistant | 2.9.9 | 未变更 | [music-assistant_2.9.9.deb](https://github.com/thirdreality/LinuxBox-Installer/releases/download/2026.7.4/music-assistant_2.9.9.deb) |
| thirdreality-flash-firmware | 1.14.01 | 未变更 | [board_firmware_1.14.01.deb](https://github.com/thirdreality/LinuxBox-Installer/releases/download/2025.11.0/board_firmware_1.14.01.deb) |

### 备注

1. **按需获取**：只有 `hacore` 与 `otbr-agent` 是本次更新的内容，其余包沿用其
   发布时的 release tag，已装过的无需重新下载。
2. **`hacore` 需要 `hacore-config` 配合**，且 `hacore-config` 必须先装、
   仅支持全新安装（与上一版相同）。`hacore` 依赖 `thirdreality-python3` 3.14。
3. **Python 3.13 系列已停止更新**，最后一版见 `RELEASE_NOTES_2026_07_20.md`
   （tag `2026.2.3`）。两个系列的 deb 清单见仓库根目录 `README.md`。

### 一键下载

```bash
TAG=2026.10.4
BASE=https://github.com/thirdreality/LinuxBox-Installer/releases/download

# 本次更新的包
wget $BASE/$TAG/hacore_2026.10.4.deb
wget $BASE/$TAG/otbr-agent_2026.11.0.deb

# 未变更的包（沿用旧 tag，按需获取）
wget $BASE/2025.12.0/hacore-config_2025.10.0.deb    # hacore 的配套配置，需与 hacore 成对
wget $BASE/2026.7.4/python3_3.14.6.deb              # hacore 的运行时依赖
wget $BASE/2026.2.3/zigbee-mqtt_2.11.0-rc.deb       # 可选：Zigbee 也可用 HA 的 ZHA，二者只能启用一个
wget $BASE/2026.7.4/music-assistant_2.9.9.deb       # 音乐播放（可选）
wget $BASE/2026.10.2/matter2mqtt_1.4.0-tr.3.deb     # 可选：与 hacore 自带 matter-server 运行期互斥
wget $BASE/2025.11.0/board_firmware_1.14.01.deb     # Zigbee/Thread 协处理器固件
```

> U 盘安装时把 deb 放到 `/mnt/R3Install`（U 盘根目录的 `R3Install/`），
> `hubv3-usb-sync` 按文件名模式 `<短名>_*.deb` 自动识别并按版本比较决定是否安装。

---

## 二、thirdreality-hacore → 2026.10.4

### 依赖版本

全部取自 HA 2026.10.4 的 `package_constraints.txt`、`requirements_all.txt`
与各集成的 `manifest.json`，非估计值。

HA 2026.10.2 → 2026.10.4 本身只影响一个我们打包的依赖：

| 依赖 | 旧 | 新 |
|---|---|---|
| homeassistant | 2026.10.2 | **2026.10.4** |
| home-assistant-frontend | 20260930.4 | **20260930.5** |

matter（`matter-python-client` 1.4.0 / `matter-ble-proxy` 0.7.1）、otbr / thread
（`python-otbr-api` 3.0.0）、zha（2.3.1）的要求均未变化。

### 对齐落后的预装依赖（非本次升级引入）

`build.sh` 里按「首次启动日志」预装的一批集成依赖一直没有随 HA 升级更新，在
2026.10.2 时就已落后。其中 `av`、`habluetooth`、`bluetooth-data-tools` 低于 HA
自己 `package_constraints.txt` 的固定版本，等于**装完 HA 又把它们降级**；HA 首次
加载这些集成时会再联网重装，离线设备上则会失败。本次全部对齐 2026.10.4：

| 依赖 | 旧 | 新 |
|---|---|---|
| av | 17.0.1 | **19.0.0** |
| habluetooth | 6.26.5 | **7.1.2** |
| bluetooth-data-tools | 1.29.18 | **1.29.24** |
| aioesphomeapi | 45.3.1 | **46.6.0** |
| esphome-dashboard-api | 1.3.0 | **1.4.0** |
| bleak-esphome | 3.9.7 | **4.0.0** |
| aioshelly | 13.26.2 | **13.34.1** |
| xiaomi-ble | 1.11.0 | **1.16.1** |
| pyotp | 2.9.0 | **2.10.0** |
| PySwitchbot | 2.2.0 | **2.9.0** |
| radios | 0.3.2 | **1.0.0** |

### 补装首启必需的依赖（非本次升级引入）

HA 加载集成时，不只安装它自己的 `requirements`，也会安装 `dependencies` 与
`after_dependencies` 的。按这条规则把设备默认加载的集成（`default_config`、
`hacore-config` 中配置的 matter 等，以及 otbr / thread / zha / bluetooth / mqtt /
music_assistant）递归展开，共 75 个集成，其中 3 个依赖 build.sh 从未预装：

| 依赖 | 需要它的集成 | 来源 |
|---|---|---|
| `aiohasupervisor==0.6.0` | hassio | matter、otbr、zha、bluetooth 等的 `after_dependencies` |
| `gazetteer-matcher==1.1.0` | conversation | `default_config` → assist_pipeline |
| `openai==3.10.0` | cloud | `default_config` |

此前它们都在首次启动时现场下载。尤其是 `aiohasupervisor`：hassio 在模块级导入它，
缺失时 matter、otbr、zha、bluetooth、esphome、shelly、switchbot、xiaomi_ble 等
**连导入都会失败**，离线设备上这些集成无法加载。本次全部预装。

随后按 hacore README 的两阶段流程，用 `hacore-config` 的默认配置实际启动 HA 做首启
预热，又发现 5 个首启会下载的包，一并写入 build.sh：

| 依赖 | 需要它的集成 |
|---|---|
| `infrared-protocols==10.1.0` | infrared（实体集成，总会加载） |
| `rf-protocols==4.3.0` | radio_frequency（实体集成，总会加载） |
| `getmac==0.9.5` | upnp / dlna_dmr（发现局域网路由器时加载） |
| `pysmlight==0.5.3`、`bleak-smlight==1.1.0` | smlight（局域网中有 SMLIGHT 设备时加载） |

### 依赖版本改为遵守 HA 的约束文件（非本次升级引入）

预热时 `xiaomi_ble`（附近有小米蓝牙设备被发现）加载失败：

```
Exception: Version mismatch: this is the 'cffi' package version 2.0.0 ...
When we import the top-level '_cffi_backend' extension module, we get version 2.1.1
```

原因：build.sh 中未固定版本的安装拉进了 `cffi` 2.1.1，而 HA 的
`package_constraints.txt` 固定为 2.0.0（上游 issue #175832 正是为此）。HA 首启装包时
带 `--constraint`，把 cffi 降回 2.0.0，但进程中已加载的仍是 2.1.1 的 `_cffi_backend`，
依赖 `pycryptodomex` 的集成因此失败，**要重启一次才恢复**。

同样偏离约束的还有 10 个包，其中 `pycares`、`grpcio`、`protobuf`、`pydantic` 也带
C 扩展，存在同类风险：

| 依赖 | 偏离的版本 | 约束版本 |
|---|---|---|
| cffi | 2.1.1 | 2.0.0 |
| pycares | 5.2.1 | 5.0.1 |
| grpcio | 1.85.1 | 1.83.1 |
| protobuf | 7.36.2 | 7.36.0 |
| pydantic | 2.14.2 | 2.13.5 |
| anyio | 4.16.0 | 4.14.2 |
| async-timeout | 5.0.1 | 4.0.3 |
| charset-normalizer | 3.5.2 | 3.4.3 |
| boto3 / botocore | 1.43.123 | 1.42.97 |
| setuptools | 84.2.1 | 84.0.0 |

改动：

- 装完 `homeassistant` 后导出 `PIP_CONSTRAINT`/`UV_CONSTRAINT`，此后所有安装都遵守
  HA 自带的约束文件。
- 每次构建（包括 venv 已存在的纯重打包）在打补丁前把偏离约束的已装包装回约束版本；
  已对齐时不联网、不改动。

### matter-server 1.4.0 → 1.5.5

对齐 HA 官方 app `app-matter-server`（其 base image 为
`ghcr.io/matter-js/matterjs-server:1.5.5`）。

- 底层 matter.js 升到 **0.18.0**（支持 Matter 1.6.1）。Node.js 要求仍为
  `>= 22.13`，系统自带的 24.x 满足。
- WebSocket API 升到 schema 14，**向后兼容**；HA 2026.10.4 的
  `matter-python-client` 1.4.0 不需要改动，官方 app 也是同样的组合。
- 我们 `matter-server.service` 用到的命令行参数（`--storage-path`、`--port`、
  `--vendorid`、`--fabricid`、`--ble-proxy`、`--log-level`、`--log-file`）
  均未变化，**service 文件无需修改**。
- 与我们相关的修复：
  - 1.5.5：旧版本写坏了 discovery TTL 的节点可以重新加载，不再让其后保存的节点
    在启动时全部不可用。
  - 1.5.0：启动失败（如 5580 端口被占用）时以退出码 1 退出，配合
    `Restart=on-failure` 可自动重试；此前会无监听地继续运行。
  - 1.5.0：节点可用性直接跟随连接状态，去掉了原先断连后 3 分钟的宽限期，
    离线设备会更快显示为不可用。

> `thirdreality-matter2mqtt` 基于 ThirdReality 自己的 matterjs-server fork
> （1.4.0-tr.3），**本次未升级**。

### 补丁状态

`zha.patch`、`zigpy_cli.patch` 的处理方式不变（幂等应用）；
`zigpy_cli_asyncio.patch` 仍被上游取代，为无害的 no-op。

### 验证

在构建出的 venv 上实测：

- `hass --version` 返回 **2026.10.4**，Python 3.14.6。
- build.sh 中 **61 个固定版本全部命中**，venv 与 HA `package_constraints.txt`
  **零偏离**，`pip check` 报告 no broken requirements。
- **首启预热复测**：对齐后用全新的默认配置再次启动 HA，**没有下载任何新包**，
  `xiaomi_ble` 的 cffi 错误不再出现。剩余报错只有 `ffmpeg`、`libpcap` 未安装
  （系统层面，与本次无关，见第五节）。
- `zha.patch`、`zigpy_cli.patch` 已应用（blz 已注册）。
- matter、otbr、thread、zha、bluetooth、esphome、stream、shelly、switchbot、
  xiaomi_ble、mqtt、music_assistant、hassio、conversation、cloud、
  assist_pipeline、default_config 等 **19 个集成全部可以导入**（补装依赖前有 9 个
  因缺 `aiohasupervisor` 失败）。
- matter-server：用临时存储目录在备用端口实际启动，首次启动约 33 秒就绪；
  仪表盘 HTTP 200；WebSocket `server_info` 报告
  `matter-server/1.5.5 (matter.js/0.18.0)`、`schema_version` 14、
  `min_supported_schema_version` 11；日志无 ERROR。
- npm 11 默认不执行原生模块的 install 脚本（构建日志中的
  `npm warn install-scripts`）。逐个确认：`bluetooth-hci-socket`、`usb`、
  `@serialport/bindings-cpp` 自带 linux-arm64 预编译文件，可正常加载；`noble` /
  `bleno` 在 Linux 上走 `hci-socket` 绑定，用不到其原生 `.node`；五个包均可正常
  `require`。我们的 service 使用 `--ble-proxy`，本来也不直接使用这些模块。

上述 HA 启动是在构建机（hubv3）上直接运行 venv 完成的；**尚未通过安装 deb 走完整的
安装与 systemd 启动流程，也未做 Matter 配网测试**，详见第五节。

---

## 三、thirdreality-otbr-agent → 2026.11.0

### 修复：开机时 Thread 射频复位晚于 otbr-agent 启动

`hubv3-otbr-agent.service`（总开关）声明了 `After=otbr-agent.service`，因此开机
顺序是 **otbr-agent 先连上 RCP，hubv3 的脚本后跑**，脚本里的 GPIO 0/29、0/27
复位就发生在 agent 已经运行之后。本机（2026.10.0）开机日志：

```
04:01:09.823 systemd: Started otbr-agent.service
04:01:09.852 systemd: Starting hubv3-otbr-agent.service
04:01:10.559 otbr-agent: [W] P-HdlcIntface-: Error decoding hdlc frame: Parse
04:01:10.564 otbr-agent: [C] P-RadioSpinel-: Unexpected RCP reset: RESET_EXTERNAL
04:01:10.564 otbr-agent: [W] P-RadioSpinel-: RCP failure detected
04:01:10.613 otbr-agent: [W] P-RadioSpinel-: Trying to recover (1/2)
04:01:10.656 otbr-agent: [N] P-RadioSpinel-: RCP recovery is done
```

agent 没有退出，是靠 `OT_RCP_RESTORATION_MAX_COUNT=2` 在进程内恢复了 RCP，
但**每次开机都白白消耗一次恢复机会**，并伴随一次 HDLC 解析错误。

修复：

- 复位逻辑移到 `otbr-agent-init.sh`，作为 `otbr-agent.service` 的**第一个
  `ExecStartPre`**（在防火墙 setup 之前）。agent 的每次启动、重启都会先复位射频。
- `hubv3-otbr-agent.sh` 不再操作 GPIO，只负责 `supervisor thread enabled`。

### 上游升级（34 个 commit）

**对打包没有影响**：上游没有修改 CMake 选项、`script/bootstrap` 或 service 模板，
`build.sh` 只改了 `COMMIT=`。

- `--rest-listen-address` 新增支持 unix socket 路径（以 `/` 开头）。我们在
  `/etc/default/otbr-agent` 中的 `0.0.0.0` 照常可用。
- 运行期修复：mDNS 重试地址解析时保留已解析的服务；DNS-SD 在请求所在的接口上
  订阅 mDNS；REST 网络诊断支持 Enhanced Route TLV (37)。
- openthread 子模块 `cb18e0f` → `ecd308b`（96 个 commit），我们配置头文件中用到的
  宏均未变化。

### 配置头文件不跟随 HA app

HA app 的 `openthread-core-ha-config-posix.h` 新增了
`OPENTHREAD_CONFIG_MULTICAST_DNS_AUTO_ENABLE_ON_INFRA_IF 0`，因为它的启动脚本会先
设置 mDNS 主机名、再手动打开 mDNS。我们没有这一步，**照搬会导致 mDNS 不启动**，
所以保留原头文件。

同理，`build.sh` 在头文件缺失时**不再自动下载**，改为直接报错（原下载地址在 HA
把 add-on 迁到独立仓库后已经 404）。

### 验证

- 二进制报告 `0.3.0-76fb21d6`；所有动态库可解析；`libsystemd`/`libdbus` 链接数
  为 0；两个防火墙后端标记文件内容为 `0`；清单校验零警告。
- deb 内 `otbr-agent.service.d/firewall.conf` 的第一个 `ExecStartPre` 为
  `otbr-agent-init.sh`，`hubv3-otbr-agent.sh` 中已无 `gpioset`。

**复位时序修复与 v2026.11.0 均尚未装到真机上验证**，详见第五节。

---

## 四、其他

- `thirdreality-zwave` 的 `postinst` 与 `thirdreality-openHAB` 的 `postrm` 修复了
  语法错误（此前 `bash -n` 不通过，dpkg 会停在半配置状态）。这两个包本次不发布。
- `README.md` 改为按 Python 3.14 / 3.13 两个系列分别列出 deb，`latest.md` 同步
  到本次版本。

---

## 五、已知事项与后续

1. **真机验证待做**。建议在带 Thread 芯片的 hubv3 上安装本次两个包后执行：
   ```bash
   # 复位时序：本次开机不应再出现 RESET_EXTERNAL / RCP failure
   reboot
   journalctl -b -u otbr-agent | grep -E "RCP reset|RCP failure|recover"
   systemctl show otbr-agent -p NRestarts          # 应为 0
   # Thread 网络在升级后保留
   ot-ctl state; ot-ctl dataset active
   # Matter
   journalctl -b -u matter-server | grep -E "Controller started|ERROR"
   ```
2. **HA app 的 OTBR 仍停在 v2026.10.0**，本次的 v2026.11.0 未经 HA 官方验证。
   若真机发现问题，可回退到 `otbr-agent_2026.10.0.deb`（tag `2026.10.2`）。
3. **`thirdreality-matter2mqtt` 仍基于 matter-server 1.4.0 fork**，与 hacore 自带的
   1.5.5 版本不一致，后续需要单独升级。
4. **系统缺少 `ffmpeg` 与 `libpcap`**（与本次升级无关）。前者影响 HA 的
   ffmpeg/stream 相关功能，后者使 dhcp 发现失效
   （`aiodhcpwatcher: libpcap is not available`），依赖 DHCP 发现的集成不会被自动发现。
5. **`version.json` 未更新**，内容仍停留在 2025 年。若设备端程序读取它来判断升级，
   需单独确认后再改。
6. 上一版遗留的事项（出厂态监听面收紧、z2m frontend 认证、构建机 `named` 残留）
   仍未处理，见 `RELEASE_NOTES_2026_10_22.md` 第七节。
