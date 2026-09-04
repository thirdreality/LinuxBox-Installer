# thirdreality-matter2mqtt 技术方案与最终技术方向

> 状态:定稿(供团队评审)
> 适用对象:matter2mqtt 网关（基于 matter.js matter-server，脱离 Home Assistant 独立运行）

---

## 1. 背景与目标

产品需求发生了变化：需要一个**与 Home Assistant 兼容、可独立发布（面向 buildroot）、且可脱离 Home Assistant 运行**的 Matter 网关。为此立项 `thirdreality-matter2mqtt`：以 matter.js 的 matter-server 作为 Matter 控制器基座，把设备的**配对、状态上报、控制**统一通过 MQTT 暴露。

贯穿始终的三条硬约束：

1. **安全信息不外发**——配对码、证书、凭证、ACL 等不得进入 MQTT。
2. **不 fork 上游引擎**——改动以最小 patch 或"自维护子模块"方式固化，便于跟随上游升级。
3. **尊重 2GiB 小内存**——重构建不并发，必要时借用临时 swap。

---

## 2. matter.js server 架构（理解基础）

- **引擎层（`@matter/*`）**：Matter 协议栈。配网流程 `ControllerCommissioningFlow`（`@matter/protocol`）、交互模型 Interaction Model、数据模型与行为 behavior（`@matter/node`）。
- **服务壳层（`matter-server` + `@matter-server/*`）**：WebSocket API、命令处理 `ControllerCommandHandler`、以及 MQTT 数据面 `MqttServer`/`MqttInterface`。
- **两套对外接口**：
  - **WebSocket（默认端口 5580）**：主接口，Home Assistant 走它。
  - **MQTT**：把数据模型镜像出去，并可反向接收写/命令。
  - 注：5010 只是 dashboard 网页端口，核心服务始终 5580。
- **BLE 代理机制**：matter-server 本身不持有蓝牙，通过 `--ble-proxy` 开出 `/ble` WebSocket，由外部 BLE client 连上来替它操作蓝牙；或用 `--bluetooth-adapter` 走内置 noble 直连 HCI（二者互斥）。

**MQTT 相关代码分布（关键）**：
- `@matter/mqtt`（packages/mqtt）= **纯传输层**（`MqttJsEndpoint`，mqtt.js 封装）。薄、稳，可直接复用。
- `@matter/node` 的 `MqttServer`（system behavior）+ `MqttInterface` = **映射逻辑层**：从引擎内 `StateStream` 拿属性变化 → 生成 topic → 发布 retained；并处理反向的写/命令。**数据源是引擎内 StateStream，不经过 WebSocket。** 这一层是我们所有定制的落点。

---

## 3. 最终技术方向（总览）

```
          ┌───────────────────────────────────────────────┐
          │              matter-server 1.3.3               │
          │            (matter.js 引擎 0.17.7)             │
          │                                                │
   BLE ───┤  --ble-proxy  ── /ble WS ── [python ble-proxy] │──→ 蓝牙硬件(与 bluetoothd 共存)
          │                              (bleak + MTU 修复) │
          │                                                │
          │  StateStream ──→ [自维护 MQTT 映射层] ──────────┼──→ MQTT broker (mosquitto)
          │                   (替代官方 MqttServer)          │     ├ 数据面(白名单过滤)
          │                                                │     ├ 命令面(含无参 on/off)
          │  ControllerCommandHandler.handleInvoke ◄───────┤     └ 控制/清理
          └───────────────────────────────────────────────┘
```

三个组成部分的最终决策：

| 组成 | 最终方向 | 理由 |
|---|---|---|
| **基座** | matter-server **1.3.3 / matter.js 0.17.7** | 配网流程正常；升级到新版前需评估回归 |
| **BLE 代理** | **python `matter-ble-proxy`（bleak）+ MTU 修复补丁** | 走 BlueZ、与 bluetoothd 共存；noble 方案独占 hci0、与 bluetoothd 冲突 |
| **MQTT 层** | **自维护一套 MQTT 映射层**（引擎内、StateStream 数据源，替代官方 `MqttServer`） | 定制需求多，散点打补丁不可持续；自维护可集中管理、跟随升级更可控 |

---

## 4. BLE 代理：维持 python bleak + MTU 修复

### 4.1 选型对比

| 方案 | 蓝牙访问 | 需 python | MTU | 与 bluetoothd |
|---|---|---|---|---|
| **python `matter-ble-proxy`（bleak）** | BlueZ D-Bus | 需要(3.12+，用 3.14 venv) | 默认 23，需补丁 | **共存** ✅ |
| Node `noble-ble-proxy` | noble raw HCI | 不需要 | 自协商 ~247 | 独占 hci0，冲突 ❌ |
| `--bluetooth-adapter`（内置 noble） | noble raw HCI | 不需要 | ~247 | 独占 hci0，冲突 ❌ |

**决策**：维持 python bleak。关键因素不是语言，而是"独占 hci0 vs 与 bluetoothd 共存"——noble 两条路都会与系统 `bluetoothd` 抢 hci0，真机复现过"配对中途被断连"。

### 4.2 MTU 修复（已固化，必须保留）

- **根因（实证）**：bleak 的 BlueZ 后端不主动获取协商后的 ATT MTU，链路被钉死在最小值 23，导致配网过程一次较大的读被拆成大量 20 字节小分片、拖垮设备 BTP 而断连。
- **修复**：连接后补一次 `_acquire_mtu()`。**实测 MTU 23→247、关键读耗时 5.6s→0.24s，小夜灯配对稳定成功。**
- **固化**：`prebuild/matter_ble_proxy_mtu.patch` + `build.sh [2c]`（幂等）。
- **认知修正**：官方 `matter-ble-proxy` CLI 是"参考/测试实现"，Home Assistant 走自有蓝牙后端；MTU=23 问题主要影响"把 CLI 当生产件"的独立部署（如我们），**不是坑所有 HA 用户的上游通病**。
- **固件侧**：小夜灯在极端小 MTU 下会主动断 BLE，已作为固件健壮性问题反馈固件团队（设备侧加固）。

---

## 5. MQTT 层：自维护映射层（核心决策）

### 5.1 为什么不再"打补丁"

围绕 MQTT 我们要的定制越来越多：**安全过滤、瘦身、无参命令修正、命令翻译、启动清孤儿、未来的 HA discovery**。若继续在官方 `MqttInterface` 上散点打补丁：每个 patch 独立、脆弱；升级 matter-server 要逐个重对（行号/sentinel/路径）；且核心行为（无差别镜像、topic 结构、命令映射）不受我们主导。**改动已经够多，应从"打补丁"转为"拥有这一层"。**

### 5.2 形态

- **复用**官方 `@matter/mqtt` 传输层（`MqttJsEndpoint`）。
- **自维护**一份 `MqttServer`/`MqttInterface` 映射逻辑（参考官方那份编写），仍跑在 matter-server 进程内、**直接消费引擎 `StateStream` 数据源**（不连 ws、不外挂进程）。
- **明确排除**的方向：外挂进程去连 5580 WebSocket——数据要在本机再拉一遍、多一套连接/重连/鉴权复杂度，已否决。
- 本质：fork 引擎里 **mqtt 这一个子模块（`MqttServer.js` + `MqttInterface.js` 两三个文件）**，不是 fork 整个引擎，范围可控。

### 5.3 这一层集中解决的四件事

**(1) 安全 + 瘦身过滤（白名单为主）**

问题实证：官方 `MqttInterface.#publishUpdate` 把整个数据模型**无差别镜像**到 MQTT，单设备数百个 topic，其中包含 `commissioning/passcode` 明文、`operational-credentials`（NOC/根证书/fabric 凭证）、`access-control/acl`、`group-key-management` 等敏感信息——直接违背"安全信息不外发"。引擎无任何过滤开关（仅 `allowOfflineUse`）。

方案：在发布出口做过滤。
- **白名单簇（默认不发、显式放行）**：`onOff`、`levelControl`、`colorControl`、`occupancySensing`、`illuminanceMeasurement`、`temperature/humidity`、`booleanState`、`powerSource`、`basicInformation`、`identify` 等业务簇。白名单天然安全——敏感簇不在其中就永远不外泄。
- **属性黑名单（去元数据/敏感）**：`attributeList`/`acceptedCommandList`/`generatedCommandList`/`clusterRevision`/`featureMap`，以及任何 `nocs`/`trustedRootCertificates`/`fabrics`/`acl`/`passcode` 等。
- 白名单**可配置**（环境变量/配置文件），降低维护成本。
- 效果：单设备从数百 topic 降到十几个业务 topic，敏感凭证一律不上 broker。
- （进阶可选）按簇聚合成单条 JSON，进一步压缩 topic 数。

**(2) 无参命令修正（on/off/toggle 原生可用）**

问题实证（同一原生路径对照）：
- 带参命令 `.../level-control/move-to-level` → **成功**（`status: Success (0)`）。
- 无参命令 `.../on-off/on` → **失败**：`Expected void, got object`。

根因：`CommandResource.invoke` 对空输入**强制包成 `{}`**，而无参命令（void 请求）校验拒绝任何对象——on/off/toggle 全中招，且无任何 payload 能成功。带参命令因 payload 是真实结构而正常。

方案：自维护层里把 void 请求命令处理修对（不强制 `{}`，无参传"无值"）。修好后 `matter2mqtt/peers/<peer>/<ep>/on-off/on` 这种**原生、直观 topic 直接可开关**，不再需要中转。

**(3) 命令处理与便捷层**

- 底层复用 `ControllerCommandHandler.handleInvoke`（与 WebSocket `device_command` 同一条 Interaction Model Invoke 路径，正确处理无参命令）。
- topic 契约：`<prefix>/peers/<peer>/<endpoint>/<cluster-kebab>/<command>`，payload 为命令参数 JSON。
- 说明：endpoint/cluster 不可省（Matter 寻址本质，WebSocket 亦然）；可在自维护层加**便捷开关 topic**（如仅给 nodeId + on/off，内部补 endpoint/cluster），待同事反馈后决定是否做。

**(4) 启动清孤儿**

问题：每次配对（含失败）都会分配 peer 序号并 retained 到 MQTT，失败/删除后沉积成"僵尸设备"。

方案（已实现雏形并验证）：进程启动时收集 `<prefix>/peers/#` 的 retained 快照，清除"无 `commissionedAt`"的孤儿（`publish 空 + retain`），保留真实设备，带"识别不到真实设备就跳过"的防误删保护。**不采用定时任务**（残留是离散事件产生，启动清一次即可，且不引入额外部件）。此逻辑并入自维护层。

### 5.4 配对/删除

commission/decommission 接入 MQTT（`<prefix>-ctl/commission|remove`），复用 `handler` 的 API。现由 `tr-commission-bridge` 承担，**最终并入自维护 MQTT 层**，统一成一份。

（历史修正：桥的加载 import 路径曾误用 hacore 的 `/srv/matter_server`，已改为 `/srv/matter2mqtt`。）

---

## 6. 加载与固化

自维护层的加载方式（设计阶段二选一）：

1. **构建期覆盖文件**：用我们的 `MqttServer.js`/`MqttInterface.js` 覆盖引擎里那两个（幂等，跟现有 patch 一个套路，但覆盖整份而非打补丁）。最简单直接。
2. **旁路 + 注入**：官方 MqttServer 不激活，把我们自己的 behavior 注入 ServerNode（需确认注入点，可能像桥一样在 `ControllerCommandHandler` 处 hook）。更解耦。

无论哪种，均不改引擎业务逻辑本质，改动集中在"我们自己的一份文件"里；升级 matter-server 时只需把官方新版与我们这份做一次对比合并——比追多个散点 patch 清晰、可控。

---

## 7. 分期落地

- **阶段一（止血）**：安全优先。先挡住敏感字段外泄（可先以最小过滤补丁临时处理），保证不违背"安全信息不外发"。
- **阶段二（自维护层）**：按本方案实现自维护 `MqttInterface`，落地过滤（白名单）、无参命令修正、命令/清理并入；关闭官方 `MqttServer`。
- **阶段三（增强）**：便捷命令 topic、按簇聚合、HA discovery（路线待定）。
- **发布前**：重打 deb，固化本轮全部成果。

---

## 8. 待定与风险

- **HA discovery 路线未定**：纯 MQTT discovery（HA 走 MQTT 集成）vs ws+MQTT 并存——待拍板。
- **便捷命令层**：等同事试用反馈。
- **BLE 后端**：维持 python；若未来 hub 不再需要 bluetoothd，可重新评估 noble 以省 python/MTU 补丁。
- **升级维护**：自维护层跟随引擎升级需关注 `StateStream`/behavior API 变化，但集中在一份文件、核心稳定，维护量可控。
- **固件侧**：设备（小夜灯）BLE 健壮性由固件团队跟进。

---

## 9. 结论

最终技术方向：**matter-server 1.3.3 基座 + python bleak BLE 代理（带 MTU 修复）+ 自维护 MQTT 映射层**。其中 MQTT 层是本阶段的核心决策——从"在官方实现上散点打补丁"转向"拥有并维护自己的一份 MQTT 映射逻辑"，一处集中解决**安全过滤、无参命令、命令处理、启动清理**四件事，既守住"安全信息不外发"的底线，又与引擎解耦、便于长期维护。
