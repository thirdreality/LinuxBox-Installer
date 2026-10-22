# LinuxBox Release Notes — 2026-10-22

ThirdReality LinuxBox (hubv3) 智能家居网关发布说明。

> **本次为较大的一次发布**：5 个 deb 包有变更，其中 **`thirdreality-matter2mqtt`
> 为首次发布**（此前 7 次提交均未进入任何 release）。
> 历史变更请参见 `RELEASE_NOTES_2026_08_24.md` 及更早文档。

---

## ⚠️ 重要提示

- **Home Assistant Core 2026.8.3 → 2026.10.2**，frontend 随集成要求升级到
  **20260930.4**。2026.10 新增 `map_tiles` 系统集成（地图瓦片服务变更），它只依赖
  `http`/`websocket_api`，**不引入新的 Python 依赖**，打包不受影响。
- **OpenThread Border Router v2026.07.0 → v2026.10.0**（commit `cb4bdae2`），
  跟随 HA add-on 的 `OTBR_BETA_VERSION`，与我们一直跟的 beta 阶段保持一致。
- **修复一个会导致 Thread 首启不可用的 bug**：`otbr_database` 此前写死了 HA 的
  Python 解释器，在未安装 hacore 的机器上脚本根本不会执行，导致**首次启动
  Thread 状态为 `disabled` 且没有 active dataset**。详见下文。
- **`thirdreality-matter2mqtt` 首发**：不依赖 Home Assistant 的
  Matter→MQTT 网关。与 hacore 自带的 matter-server **运行期互斥**（同占 5580
  端口与 BLE 适配器），安装器不会替你做选择，详见下文。
- **安全相关行为变更**：mosquitto 的明文 1883 监听器已收紧到仅本机
  （`127.0.0.1`/`::1`）。**原先把远端 Home Assistant 指向本机 broker 的部署会
  连不上**，需改用专用 TLS 监听器。
- 构建源变更：pip 镜像由清华改为阿里（清华源对 pip 返回 403，详见下文）。

---

## 一、本次发布的包版本

本次 release tag：**`2026.10.2`**

| 包 | 版本 | 状态 | 下载 |
|---|---|---|---|
| **thirdreality-hacore** | **2026.10.2** | 升级（← 2026.8.3） | [hacore_2026.10.2.deb](https://github.com/thirdreality/LinuxBox-Installer/releases/download/2026.10.2/hacore_2026.10.2.deb) |
| **thirdreality-otbr-agent** | **2026.10.0** | 升级（← 2026.07.0） | [otbr-agent_2026.10.0.deb](https://github.com/thirdreality/LinuxBox-Installer/releases/download/2026.10.2/otbr-agent_2026.10.0.deb) |
| **thirdreality-matter2mqtt** | **1.4.0-tr.3** | 🆕 **首次发布** | [matter2mqtt_1.4.0-tr.3.deb](https://github.com/thirdreality/LinuxBox-Installer/releases/download/2026.10.2/matter2mqtt_1.4.0-tr.3.deb) |
| thirdreality-zigbee-mqtt | 2.11.0-rc | 内容变更，版本号未变 ⚠️ | [zigbee-mqtt_2.11.0-rc.deb](https://github.com/thirdreality/LinuxBox-Installer/releases/download/2026.2.3/zigbee-mqtt_2.11.0-rc.deb) |
| thirdreality-hacore-config | 2025.10.0 | 未变更 | [hacore-config_2025.10.0.deb](https://github.com/thirdreality/LinuxBox-Installer/releases/download/2025.12.0/hacore-config_2025.10.0.deb) |
| thirdreality-python3 | 3.14.6 | 未变更 | [python3_3.14.6.deb](https://github.com/thirdreality/LinuxBox-Installer/releases/download/2026.7.4/python3_3.14.6.deb) |
| thirdreality-music-assistant | 2.9.9 | 未变更 | [music-assistant_2.9.9.deb](https://github.com/thirdreality/LinuxBox-Installer/releases/download/2026.7.4/music-assistant_2.9.9.deb) |
| thirdreality-flash-firmware | 1.14.01 | 未变更 | [board_firmware_1.14.01.deb](https://github.com/thirdreality/LinuxBox-Installer/releases/download/2025.11.0/board_firmware_1.14.01.deb) |

### 备注

1. **按需获取**：上表并非都要装。只有 `hacore` / `otbr-agent` /
   `matter2mqtt` 是本次更新的内容；其余包未变更，沿用其发布时的 release tag，
   已装过的无需重新下载。按你的实际功能需求取用即可，例如：
   - 不需要音乐播放 → 不必装 `music-assistant`
   - `zigbee-mqtt`（zigbee2mqtt）**可选**：Zigbee 既可以用它，也可以用
     Home Assistant 自带的 **ZHA** 集成（本仓库为 ZHA 打了博流专用的
     `zha.patch`）。两者都要独占同一个 Zigbee 协处理器串口
     （`/dev/ttyAML3`），因此**只能启用其中一个**。
   - 固件版本已是最新 → `board_firmware` 会被安装器自动跳过
   - `matter2mqtt` 与 hacore 自带的 matter-server **运行期互斥**，按使用的栈
     二选一（详见第四节）

2. **`hacore` 需要 `hacore-config` 配合**：`hacore` 只提供程序本体，初始配置
   （`configuration.yaml`、`.storage/` 下的 http/otbr/thread 等条目）由
   `hacore-config` 提供，两者需成对安装，且 `hacore-config` **必须先装**。
   另注意 `hacore-config` **不支持升级，仅支持全新安装** —— 它的 `postinst`
   在 `hacore` 尚未安装时会打印
   `Warn: Script /srv/homeassistant/bin/home_assistant_init.sh not found.`，
   这是安装顺序导致的正常提示，`hacore` 装完即可，不影响结果。
   `hacore` 还依赖 `thirdreality-python3`（Python 3.14.2+）。

> 未变更的包沿用其发布时的 release tag，无需重新下载。

> ⚠️ **zigbee2mqtt 版本号未 bump**：内容有 4 处改动但 `Version:` 仍为
> `2.11.0-rc`。USB 安装器按版本号比较，会把它判为「已最新」而**跳过安装**。
> 若需要这些改动随镜像下发，发布前请先 bump 版本号 —— 届时上表的下载链接也需
> 改为指向本次 tag `2026.10.2`。

### 一键下载

```bash
TAG=2026.10.2
BASE=https://github.com/thirdreality/LinuxBox-Installer/releases/download

# 本次更新的包
wget $BASE/$TAG/hacore_2026.10.2.deb
wget $BASE/$TAG/otbr-agent_2026.10.0.deb
wget $BASE/$TAG/matter2mqtt_1.4.0-tr.3.deb

# 未变更的包（沿用旧 tag，按需获取）
wget $BASE/2025.12.0/hacore-config_2025.10.0.deb    # hacore 的配套配置，需与 hacore 成对
wget $BASE/2026.7.4/python3_3.14.6.deb              # hacore 的运行时依赖
wget $BASE/2026.2.3/zigbee-mqtt_2.11.0-rc.deb       # 可选：Zigbee 也可用 HA 的 ZHA，二者只能启用一个
wget $BASE/2026.7.4/music-assistant_2.9.9.deb       # 音乐播放（可选）
wget $BASE/2025.11.0/board_firmware_1.14.01.deb     # Zigbee/Thread 协处理器固件
```

> U 盘安装时把 deb 放到 `/mnt/R3Install`（U 盘根目录的 `R3Install/`），
> `hubv3-usb-sync` 按文件名模式 `<短名>_*.deb` 自动识别并按版本比较决定是否安装。

---

## 二、thirdreality-hacore → 2026.10.2

### 依赖版本

全部取自 HA 2026.10.2 自带的 `package_constraints.txt` 与各集成的
`manifest.json`，非估计值：

| 依赖 | 旧 | 新 |
|---|---|---|
| homeassistant | 2026.8.3 | **2026.10.2** |
| home-assistant-frontend | 20260729.7 | **20260930.4** |
| matter-python-client | 1.3.0 | **1.4.0** |
| python-otbr-api | 2.10.0 | **3.0.0** |
| zha / zha-quirks | 2.1.0 / 2.2.0 | **2.3.1 / 2.3.0** |
| serialx | 1.8.2 | **1.11.0** |
| hassil | 3.8.0 | **3.12.1** |
| home-assistant-intents | 2026.6.24 | **2026.10.6** |
| mutagen | 1.47.0 | **1.48.1** |
| async-upnp-client | 0.46.2 | **0.48.2** |
| music-assistant-client | 1.3.6 | **1.5.1** |

Python 要求仍为 `>=3.14.2`，`thirdreality-python3` 3.14.6 满足，未变更。

### 补丁状态

- `zha.patch`（博流专用，向 `RadioType` 注册 blz）— **已应用**
- `zigpy_cli.patch`（博流专用，向 zigpy-cli radio 表注册 blz）— **已应用**
- `zigpy_cli_asyncio.patch` — **已被上游取代**。zigpy-cli 2.0.0 自己实现了
  Python 3.14 的 event-loop 修复（且更完整：用共享 loop）。幂等守卫检测到
  sentinel `asyncio.new_event_loop` 后跳过，**不会导致构建失败**。该补丁现为
  无害的 no-op，后续可考虑删除。

### 构建源：清华 → 阿里

构建一度失败，原因与版本升级无关：**清华 pip 镜像对 pip 返回 403**，连 `wheel`、
`setuptools` 都解析不到，`zigpy-blz` 的构建依赖步骤因此失败。

排查要点（供后续复用）：

- **curl 对同一 URL 返回 200，只有 pip 吃 403** — 必须用 pip 自身探测，
  curl/浏览器测不出来。
- **科大、交大反代清华的包存储**：索引层返回 200，但下载实际文件时仍跳回
  `mirrors.tuna.tsinghua.edu.cn` 吃 403。**只测索引会误判为可用。**
- 阿里、腾讯、华为、pypi.org 均正常。

改动：默认源改为阿里，可用 `PIP_INDEX_URL=... ./build.sh` 覆盖。同时
**不再使用 `pip3 config set`** —— 它写的是全局 `~/.config/pip/pip.conf`，会污染
整机配置、影响本次构建之外的一切；改用构建环境内的
`PIP_INDEX_URL`/`PIP_TRUSTED_HOST`。

### 其他

- `matter_server_lock_cleanup.sh`：matter-server 启动前清理陈旧的 matter.js
  storage 锁（断电后残留会导致起不来）。

### 验证

venv 实测：`hass --version` 返回 2026.10.2；上表 12 个 pin 全部命中；
`pip check` 报告 no broken requirements（含注释中特别警告过的
zigpy 2.3.0 + serialx 1.11.0 组合）。

---

## 三、thirdreality-otbr-agent → 2026.10.0

### 修复：Thread 首启 `disabled`、无 dataset

**这是本次最重要的修复。** 症状：

```
postinst: line 39: /usr/lib/thirdreality/otbr_database: cannot execute: required file not found
```

根因：`otbr_database` 的 shebang 写死为 `#!/srv/homeassistant/bin/python3`。
在**未安装 hacore** 的机器上该解释器不存在，内核 exec 失败 —— 报错里的
"required file not found" 指的是**解释器**，不是脚本本身。于是脚本从未执行，
`dataset init new` / `dataset commit active` / `thread start` 一次都没跑，
Thread 首次启动即为 `disabled` 且无 active dataset。

修复：

- shebang 改为 `#!/usr/bin/env python3`。该脚本只用标准库
  （`asyncio`/`json`/`os`/`subprocess`/`datetime`/`uuid`），与 Home Assistant
  无关，没有理由绑定 HA 的解释器。系统 python3 (3.11) 与 HA 的 (3.14) 均实测可跑。
- postinst 此前用 `|| true` 吞掉失败，仍打印 "Install OTBR-Agent success"。
  现在改为打印 `[WARN]`——这一步失败就意味着没有 active dataset，正是上述症状。
  仍不致命：装包不该因此中止。
- `DEBIAN/control` 补充声明 `python3` 依赖。

**真机验证已通过**：安装日志显示
`No active dataset found. Creating new dataset...` → Step1~6 全部 `Done` →
`New active dataset: 0e0800...`，HA 的 core config 与 thread database 均写入成功。

### 上游升级（137 个 commit）

两处影响打包：

1. **新增可选的进程内防火墙后端**：`-DOTBR_NFTABLES`（Linux）与 `-DOTBR_PF`
   （macOS）。**两者均保持 OFF**，防火墙规则仍由我们自己的 `otbr-firewall.sh`
   （ipset/ip6tables）负责；现在在 cmake 显式传这两个 flag，不依赖上游默认值。
2. **即使两者都关，构建仍会无条件安装两个标记文件**
   `/usr/share/otbr/{nftables-backend,pf-backend}`，供旧的防火墙脚本判断规则
   归属。对我们而言内容为 `0`。已加入 `STAGED_FILES` 清单（保持双向校验有效）
   与 `--clean` 的手工删除分支。

### 顺带修复一个潜伏问题（非本次升级引入）

清单校验拦住了一次打包，暴露出 staging 布局的隐患：
`pkg-config --variable=systemdsystemunitdir systemd` 返回 `/lib/systemd/system`，
因此 `DESTDIR` 把 unit 装到了 `staging/lib/...`。真实系统上 `/lib` 是指向
`usr/lib` 的符号链接（usrmerge），两种写法是同一个文件；但**在 staging 里它们是
两个独立目录**，清单期望的 `staging/usr/lib/...` 并不存在，于是构建中止。

这个问题**早于本次版本升级** —— 旧的「从 /usr 复制」流程因为那个符号链接而碰巧
能工作。现在收集前先把 staging 归一化为 usrmerge 布局。

> 这其实是清单校验的一次成功拦截：它挡住了一个会缺少两个 systemd unit 的残缺 deb。

### 文档与注释

本包内所有中文注释与输出已转为英文（`build.sh`、维护者脚本、prebuild 脚本、
README）。翻译时顺带修正了 README 两处过时事实：

- 原文提到的两个 stable 专用 patch（`0001-rest-SO_REUSEADDR`、
  `0002-nat64-handle-ipv4-options`）**已不存在** —— add-on 删掉了整个
  `patches/` 目录，两个阶段都不打 patch。
- add-on 的 stable commit 是 `fd872ab9`，不是原文写的 `624a7d98`。

### 验证

二进制报告 `0.3.0-cb4bdae2`；所有动态库可解析；`libsystemd`/`libdbus`
链接数为 **0**（`DBUS=OFF` 的预期）；两个标记文件内容为 `0`；清单校验零警告。

---

## 四、thirdreality-matter2mqtt 1.4.0-tr.3 🆕 首次发布

不依赖 Home Assistant 的 **Matter → MQTT 网关**。以 zigbee2mqtt 风格的 topic
布局，把 Matter 设备的状态、控制、配网与固件升级暴露到 MQTT，并支持
Home Assistant MQTT discovery。

### 构成

- 基于 ThirdReality 的 **matterjs-server fork**（matter-server 1.4.0 /
  matter.js 0.17.9），启用其 `packages/mqtt-bridge`（`--mqtt-url`）。
  此前「官方 npm 包 + `@matter/mqtt` 补丁」的做法已废弃。
- **BLE 配网**走独立的 `matter-ble-proxy` venv（bleak/BlueZ，Python 3.14 来自
  `thirdreality-python3`），与 `bluetoothd` 共存。
- Node.js 取系统运行时（>= 22.13）。
- 连接系统的 mosquitto（由 zigbee2mqtt / OS 提供），**本包不安装也不配置它**。

### 服务

| 服务 | 说明 |
|---|---|
| `matter2mqtt.service` | matter.js server + MQTT bridge，监听 5580 |
| `matter-ble-proxy.service` | BLE provider，连 `ws://127.0.0.1:5580/ble` |

### ⚠️ 与 hacore 自带 matter-server 运行期互斥

两者**同占 5580 端口、同抢 BLE 适配器**，但允许并存安装。仲裁逻辑在包内：

- **preinst** 不碰原生栈：不停、不 disable，尤其**不删**
  `/srv/homeassistant` 或 `/srv/matter_server`。
- **postinst** 在检测到 `home-assistant.service` 或 `matter-server.service`
  存在时，保持 `matter2mqtt.service` / `matter-ble-proxy.service`
  **不启动、不 enable**。

也就是说，**切换栈始终是显式的运维动作**，安装器不替你决定。装机日志会明确说明：

```
matter2mqtt: matter-server.service is enabled or running; leaving matter2mqtt.service untouched (conflicting resource)
matter2mqtt: home-assistant.service is enabled or running; leaving matter-ble-proxy.service untouched (conflicting resource)
```

### 1.4.0-tr.1 → tr.3 的累积改进

- storage 锁可在断电后存活（不再因残留锁起不来）
- OTA 固件升级
- zigbee2mqtt 风格的 color / move-step 支持
- 打包与启动修复；USB 安装器改为选取最新的 deb

---

## 五、thirdreality-zigbee-mqtt（版本号未变）

### ⚠️ 安全行为变更：mosquitto 1883 收紧到仅本机

matter2mqtt 会把整个 Matter 数据模型发布到 broker，**包括配网码、NOC 证书，
以及 MQTT 凭据本身**。此前随包下发的配置监听所有接口（仅有密码保护），现改为
绑定 `127.0.0.1`/`::1`。

**影响**：原先把**远端** Home Assistant 指向本机 broker 的部署**会连不上**。
确需远程访问时，应使用专用的 TLS 监听器并配置 per-client ACL。

本机的 z2m、matter2mqtt、bridge 均通过 `localhost:1883` 连接，不受影响。

### external_converters 修复

Z2M 2.x 仅在设置了 `advanced.enable_external_js` 时才加载
`data/external_converters/*.js`，因此 `6ed8510` 起随包下发的 converter
**一直被静默忽略**。现在：

- 两份默认配置均启用该开关；
- 已有安装通过 post-fix 迁移，改动保持幂等（手工改过的
  `configuration.yaml` 不会被覆盖）；
- `build.sh` 每次重打包都从 `prebuild/converters` 重新播种
  `external_converters`。

此外修复了因库版本更新而失效的 converter js 文件。

---

## 六、安装与升级

### 升级路径

- **`/var/lib/thread`（Thread 网络凭据）在升级时保留**：dpkg 升级走的是
  `prerm upgrade`，不匹配 remove/purge 分支。
- 防火墙清理由 preinst 停止服务触发 `ExecStopPost` 自然完成，prerm 无需为升级
  单独处理。
- **`thirdreality-hacore-config` 不支持升级**（仅全新安装）。

### 用 dpkg 手工安装

`dpkg -i` **不会自动解析 Depends**。如提示缺 `libjsoncpp25`、`python3` 等，
安装后补一句 `apt-get -f install`。

---

## 七、已知事项与后续

1. **zigbee2mqtt 版本号未 bump**（见第一节的警告）—— 发布前需确认。
2. **OTBR 防火墙的真机验证尚未执行**。规则累积是 `feb106c` 那次重构要解决的
   核心问题，至今没有在带 `wpan0` 的设备上验证过。建议在设备上执行：
   ```bash
   systemctl restart otbr-agent
   ip6tables -L OTBR_FORWARD_INGRESS -n | wc -l   # 多次重启后行数应稳定，不累积
   ipset list -n | grep otbr
   systemctl disable --now hubv3-otbr-agent        # 链与 ipset 应被清空
   ```
3. **`zigpy_cli_asyncio.patch` 已被上游取代**，当前为无害 no-op，可考虑删除。
4. **出厂态的监听面收紧尚未实施**。开发期需要开放这些端口做调试，出厂应仅保留
   本机访问。涉及 z2m frontend (8099)、otbr REST (8081)、otbr Web GUI (8080)、
   matter-server/matter2mqtt WS (5580)。注意 `otbr-web` 不是 `WantedBy` 启动，
   而是被 `otbr-agent` 的 `Wants=` 拉起，**单纯 `disable` 无效，需 `mask`**。
5. **z2m frontend 目前无认证**。schema 支持 `auth_token`（启用认证）与
   `disable_ui_serving`（只保留 WebSocket、不提供 Web UI），出厂前建议启用。
6. **构建机残留**：OTBR 的 `script/bootstrap` 会安装 `bind9` 并自动 enable
   `named`。纯构建机通常不需要，可按需 disable。
