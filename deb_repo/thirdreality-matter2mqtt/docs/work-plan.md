# matter2mqtt 工作计划 —— 跟随上游、最小可撤改动

> 版本：v1（权威工作文档；取代并修正此前 `self-developed-mqtt.md` 的"自研"方向）
> 基座：matter-server 1.3.3 / matter.js 0.17.7；运行于 hubv3（armbian arm64，~2GiB）

---

## 0. 指导思想（先立规矩）

**尽量跟随 matter.js 官方，我们自己的改动越少越好、越浅越好、越容易撤越好。**

- **不自研整层**（不写自己的 MqttServer/MqttInterface）。自研会与官方分叉，将来官方 MQTT 增强时我们反而维护一套重复且可能冲突的代码。
- 每一处必须的改动，都做成**最小、可撤的"垫片"**，并挂一条**"上游取代路线图"**：官方一旦提供对应能力，就删掉垫片、切回官方。
- 目标是"打最小垫片、紧跟上游、随时把垫片还给官方"，**主动防止被上游演进挤占**。

---

## 1. 我们想要什么（目标与验收标准）

| 能力 | 验收标准 |
|---|---|
| Matter 配对 | BLE + WiFi 设备可稳定配对（含慢速 BLE 设备如小夜灯） |
| 状态上报 | 业务属性上报到 MQTT（on/off、亮度、颜色、光照、人体、型号名） |
| 控制 | 经 MQTT 可开关/调亮度/调色，**含无参命令 on/off/toggle** |
| 安全 | **敏感信息不外发**：配对码、证书、凭证、ACL 不出现在 MQTT |
| 数据量 | 单设备 topic 数可控（只发业务簇，去元数据） |
| 残留清理 | 配对失败/删除的僵尸设备可清 |
| 兼容/发布 | 与 HA 数据结构一致；可独立发布（buildroot） |
| **工程约束** | **对上游改动最小、可撤、紧跟 matter.js** |

---

## 2. 现状（已完成，实证）

改动面：**3 处上游 patch + 1 个自有文件**。

| # | 上游文件 | 改动 | 固化 | 实测 |
|---|---|---|---|---|
| 1 | `matter_ble_proxy/client.py` | `_handle_connect` 后 `_acquire_mtu()` | `matter_ble_proxy_mtu.patch` + `build.sh [2c]` | MTU 23→247，关键读 5.6s→0.24s，配对稳定 |
| 2 | `@matter-server/ws-controller/.../ControllerCommandHandler.js` | 启动后 `behaviors.require(MqttServer,{address})` + `import()` 加载桥 | `matterjs_mqtt.patch` | MQTT 数据面 + 命令桥就绪 |
| 3 | `@matter/node/.../MqttInterface.js` | `#feed` 的 `StateStream` 加 `clusters` 白名单（1 行） | `matter_mqtt_publish_filter.patch`（**未接入 build.sh**） | topic 738→197，敏感簇命中 0 |
| — | `tr-commission-bridge.mjs`（自有） | 命令翻译 `invoke`（复用 `handleInvoke`，无参命令正确）+ 启动清孤儿 | prebuild + build.sh | on/off/toggle/亮度/颜色成功；清孤儿验证通过 |

已验证的关键事实（作为决策依据）：

- 官方 matter-server **CLI 无任何 mqtt 选项**；引擎有 `MqttServer` 能力但壳默认不启用。
- 原生 `MqttInterface` 把整个数据模型**无差别镜像**、含敏感明文（`commissioning/passcode`、`operational-credentials`、`access-control`、`group-key-management`）。
- `StateStream(node,{clusters:[...]})` **原生支持 cluster 白名单**，`MqttInterface` 只是没用它。
- 原生 `CommandResource` 对**无参命令**强制 `{}` → `on/off/toggle` 报 `Expected void`；带参命令（move-to-level）正常。WebSocket 的 `handleInvoke` 把空 `{}` 归一为 `undefined`，无参命令正常 → 桥复用它。
- onOff 属性只读，写属性被拒（`Unsupported write`）→ 开关必须走命令。
- 端口：5580=WebSocket API，5010=dashboard。

---

## 3. 要做的工作（任务清单）

### A. 固化与收敛现有改动（近期，必做）

- **A1. 白名单 patch 接入 build.sh**：`matter_mqtt_publish_filter.patch` 目前只在运行版、未固化。做成幂等步骤（sentinel = `clusters:`），与前两个 patch 同套路。
  - 完成标准：`--rebuild` 后 deb 内 `MqttInterface.js` 带白名单；重装/升级不丢。
- **A2. 白名单可配置**：cluster 白名单不要写死在 patch 里，改为从**环境变量/配置文件**读取（如 `MATTER_MQTT_CLUSTERS`）。
  - 目的：白名单是"业务清单",会随支持的品类增加；可配置避免每次改代码。
  - 完成标准：不改文件、改配置即可增减上报的簇。
- **A3.（可选）属性去元数据**：在发布出口跳过 `attributeList/acceptedCommandList/generatedCommandList/clusterRevision/featureMap`，进一步瘦身。
  - 注意：这是 attribute 级，`StateStream` 到不了，需在发布处过滤 → 会略微增加对 `MqttInterface` 的改动面。**权衡：若瘦身收益不值得增加改动面，可暂缓**（符合"最小改动"原则）。
- **A4. 3 个 patch 体检**：确认都幂等、有 sentinel、路径正确（`matterjs_mqtt.patch` 的 import 路径已修为 `/srv/matter2mqtt`）。

### B. 安全审计（近期，必做 —— 硬底线）

- **B1. 黑名单核对**：逐一确认白名单**没有**放进任何敏感簇（`operationalCredentials`/`accessControl`/`groupKeyManagement`/`generalCommissioning`/`administratorCommissioning`/`diagnosticLogs` 等）。
- **B2. 本机节点(node 0)敏感核对**：确认 `commissioning/passcode`、server 自身 `operational-credentials` 等也不外发（白名单对 node 0 同样生效）。
- 完成标准：`mosquitto_sub -t 'matter2mqtt/#'` 全量抓取，grep 敏感字段命中数 = 0。

### C. 命令面（视需求）

- **C1. nodeId↔peerId 映射文档化**：控制用 `nodeId`，来自 `<prefix>/peers/<peer>/0/commissioning/peerAddress`。写进使用说明。
- **C2.（可选）便捷开关 topic**：`<ctl>/onoff/set {"nodeId":7,"state":"on"}`，桥内部补 endpoint/cluster。**待同事试用反馈后再决定**。

### D. 上游跟随机制（关键 —— 防挤占）

- **D1. 维护"上游取代路线图"**（见第 4 节），并在每次升级 matter-server / matter-ble-proxy 时执行检查：
  - 官方是否新增 `--mqtt-address` 类 CLI/配置 → 若有，撤 patch #2 的"启用"半，改用官方入口。
  - 官方 `MqttServer` 是否新增发布过滤配置 → 若有，撤 patch #3，改用官方配置。
  - 官方是否修复无参命令（`CommandResource`）→ 若修，桥的 `invoke` 可瘦身/下线。
  - 官方 `matter-ble-proxy` 是否修 MTU → 若修，撤 patch #1。
- **D2. 记录撤除条件**：每个 patch 头部注明"当官方提供 X 时删除本 patch"。
- 完成标准：任何一次上游升级，都能据路线图快速判断"哪些垫片可以还给官方"。

### E. 升级回归测试（每次升级必跑）

固定回归清单（见第 6 节），保证跟随上游升级时功能不回退。

### F. 打包发布

- **F1. 重打 deb**：固化本轮全部（白名单接入后）。
- **F2. 验证清单**：deb 内 MTU patch、桥、白名单、路径修正齐全；`dpkg-deb -c` 抽查。

### G. 待决策（需拍板）

- **G1. HA discovery 路线**：纯 MQTT discovery vs ws+MQTT 并存。
- **G2. 是否向上游反馈**：MQTT 发布过滤配置、无参命令修复——这两项若上游做了，我们的垫片就能撤。是否推动（提 issue/PR）由你定；按 OHF 政策，任何提交需人工审核、且需附完整原始日志。
- **G3. BLE 后端**：维持 python bleak；若将来 hub 不再需要 bluetoothd，可重估 noble（免 python/MTU 垫片）。

### H. 固件侧（并行，交固件团队）

- 小夜灯在极端小 MTU 下主动断 BLE → 设备 BTP/BLE 健壮性加固。

---

## 4. 上游取代路线图（防挤占核心表）

| 我们的垫片 | 现在为何必须 | 官方取代信号 | 取代后动作（撤垫片） |
|---|---|---|---|
| #2 启用 MQTT | matter-server 壳无 mqtt 开关 | 出现 `--mqtt-address` / `mqtt` 配置 | 删"启用"半，改用官方 CLI/配置 |
| #3 上报过滤 | 引擎无发布过滤、且敏感外泄 | `MqttServer.State` / 配置出现 include/exclude/filter | 删 patch，改用官方过滤配置 |
| 桥·invoke（无参命令） | `CommandResource` 无参命令缺陷 | 官方修复无参命令 | 无参命令走原生 topic，桥对应逻辑下线 |
| #1 BLE MTU | bleak/proxy 不取协商 MTU | 官方 ble-proxy 取 MTU / 修复 | 删 patch |
| 桥·commission | 官方未把配对接入 MQTT | 官方提供 MQTT 配对入口 | 相应下线 |
| 桥·清孤儿 | 官方失败 peer 残留不回收 | 官方发布删除/回收机制 | 相应下线 |

**原则**：这张表就是"跟随上游"的操作手册——垫片能撤就撤，长期让改动面趋近于 0。

---

## 5. 分期

- **阶段一（固化止血，近期）**：A1/A2（白名单接 build.sh + 可配置）、B（安全审计）、F（重打 deb）。达成"安全底线 + 现有能力固化"。
- **阶段二（按需增强）**：A3（属性瘦身，权衡后定）、C2（便捷命令，视反馈）。
- **阶段三（持续跟随）**：D（每次升级执行取代路线图，逐步撤垫片）、E（回归）。
- **阶段四（可选）**：G1（HA discovery）、G2（上游反馈）。

---

## 6. 升级回归清单（每次升级 matter-server / ble-proxy 后执行）

1. 配对：BLE 设备可配上（看日志 `Commissioned`）。
2. MTU：ble-proxy 日志 `negotiated ATT MTU=247`（非 23）。
3. 上报过滤：`mosquitto_sub -t 'matter2mqtt/#'`，只剩白名单业务簇，敏感字段命中 0。
4. 控制：`<ctl>/invoke/set` 发 on/off/toggle/moveToLevel，`onOff` 状态随之变化。
5. 清孤儿：埋一个假 peer retained → 重启 → 被清、真实设备保留。
6. 三个 patch 是否仍成功应用（幂等 sentinel 命中或重新打上）。
7. 对照第 4 节路线图：本次升级官方是否已提供某能力 → 可撤对应垫片。

---

## 7. 风险与维护

- **改动集中、可撤**：3 patch + 1 桥，每处有 sentinel + 撤除条件。
- **依赖上游私有点需盯**：bleak 私有 `_acquire_mtu`（#1）、引擎 private `#feed`（#3）。升级后重点验证这两处。
- **不扩大改动面**：抵制"顺手自研 MqttInterface"的冲动——那是被挤占风险最大、维护最重的方向。安全过滤保持"1 行白名单 + 可配置"的最小形态。
- **与 HA 数据一致性**：topic 结构不改，过滤只做减法。

---

## 8. 结论

我们要做的工作，本质是**三类**：
1. **固化 + 守住安全底线**（白名单接 build.sh + 可配置 + 安全审计 + 重打 deb）——近期必做。
2. **建立"跟随上游"机制**（取代路线图 + 升级回归）——保证紧跟 matter.js、垫片能撤、不被挤占。
3. **按需增强 + 待决策**（属性瘦身、便捷命令、HA discovery、上游反馈）。

始终守住一条：**最小、可撤、跟随上游**——不自研、不扩面，让我们的改动随官方演进持续收敛。
