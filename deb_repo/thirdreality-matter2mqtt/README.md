# thirdreality-matter2mqtt

脱离 Home Assistant 独立运行的 **Matter → MQTT 网关**。以 matter.js 的
`matter-server` 作为 Matter 控制器基座,把设备的**配对、状态上报、控制、固件升级**
以 zigbee2mqtt 风格的 topic 布局统一通过 MQTT 暴露出去,面向 buildroot 独立发布,
同时与 Home Assistant 的数据结构保持兼容。

> 本 README 是本包的权威说明。以 `build.sh` / `prebuild/DEBIAN/control` /
> `prebuild/*.service` 为准;旧的 `docs/technical-direction.md`、`docs/work-plan.md`
> 已删除(其方案已被实现取代,见下"设计沿革")。

---

## 为什么有这个包 · 设计沿革

产品需要一个可脱离 HA 运行的 Matter 网关,并通过 MQTT 对外。围绕"MQTT 这一层怎么做"
方案演进过三次:

1. **散点打补丁**:在官方 `matter-server` 上就地 patch `MqttServer`/`MqttInterface`。
   问题:官方 MQTT 实现不满足需求(无差别镜像、含敏感明文、无参命令失败、无过滤开关),
   补丁多而脆、每次升级都要重对。
2. **自研独立 MQTT 层**:一度计划自维护一份映射层。否决——会与官方长期分叉、维护重。
3. **(当前)维护上游分叉**:我们 fork 了 matter.js 的 matterjs-server,**在它原有的
   WebSocket channel 之外新增了一个 MQTT channel**(fork 内的 `packages/mqtt-bridge`),
   通过 `--mqtt-url` 启用。官方 MQTT 不行,所以这条数据面由我们在分叉里自己维护。

因此本包**不再从官方 npm 装 matter-server**,而是从 ThirdReality 分叉的发布 tarball 安装。

---

## 架构

```
matter2mqtt.service        node MatterServer.js --ble-proxy --mqtt-url ...   (:5580 + /ble)
                           ├─ WebSocket channel (:5580)  ── HA 兼容主接口
                           └─ MQTT channel (fork 内 mqtt-bridge, --mqtt-url) ── 连系统 mosquitto
matter-ble-proxy.service   python venv 的 matter-ble-proxy (bleak/BlueZ) ── 连 :5580/ble 代理蓝牙
```

- **基座 / MQTT channel**:ThirdReality 分叉的 `matter-server`。WebSocket channel 是官方
  原有主接口(HA 走它);MQTT channel 是我们在分叉里加的,直接消费引擎数据、发布到 mosquitto。
- **BLE 代理**:独立 python venv(用 `thirdreality-python3` 3.14 建),走 bleak/BlueZ,
  **与 bluetoothd 共存**。刻意不用 noble/raw-HCI 方案——那会独占 hci0、与系统 bluetoothd 抢
  蓝牙(真机复现过"配对中途断连")。`matter-server` 用 `--ble-proxy` 开出 `:5580/ble`,
  由这个 proxy 连上来替它操作蓝牙。
- **MQTT broker**:连系统 mosquitto(由 zigbee2mqtt / OS 提供),本包**不安装也不停** broker。
- **Node.js**:用系统运行时(armbian/buildroot 自带,要求 ≥ 22.13),本包不打包 Node。

---

## 版本

- 分叉基座:`matter-server` **1.4.0-tr.3** / matter.js **0.17.9**。
- deb 版本以 `prebuild/DEBIAN/control` 的 `Version` 字段为准。
- BLE 代理:`matter-ble-proxy` **0.7.1**。

---

## 构建

低内存(~2GiB)机器上,`build.sh` 无条件调用 `../build_common.sh` 的 `tr_build_guard_start`
(停无关服务 + 按需临时 swap + 退出自动清理/恢复);重任务请后台跑。

```bash
./build.sh              # 装 matter-server 分叉 + BLE venv + 打补丁 + 打 deb
./build.sh --rebuild    # 删 /opt/matter2mqtt 重装
./build.sh --clean      # 停/禁服务、删程序目录与 unit(/var/lib 数据保留)
```

构建要点:
- **产物文件名**:`matter2mqtt_<version>.deb`。按本仓库惯例,**deb 文件名不带
  `thirdreality-` 前缀**(与 `hacore_`、`zigbee-mqtt_`、`music-assistant_` 一致),
  而 `DEBIAN/control` 的 `Package` 仍是 `thirdreality-matter2mqtt`。
  `hubv3-usb-sync` 按 `matter2mqtt_*.deb` 查找,U 盘上放多个版本时取版本号最大的那个。
- **分叉 tarball 来源**:本地 `prebuild/matter-server-<ver>.tgz` 优先(离线/开发);否则从
  GitHub Release 下载并校验 sha256。tarball 不进 git(见 `.gitignore`),由 Release 分发。
- 安装后有**守卫断言**:装到的必须是含 `-tr.` 的 ThirdReality 构建,且 `--help` 里要有
  `mqtt-url`(证明 MQTT channel 在),否则中止。
- 程序目录 `/opt/matter2mqtt`(zigbee2mqtt 风格);历史上曾在 `/srv/matter2mqtt`,构建/安装
  会清理旧位置,数据始终在 `/var/lib/matter2mqtt`。

> 分叉发布 tarball 本身如何产出,由上游 [matterjs-server](https://github.com/thirdreality/matterjs-server)
> 仓库自行处理(Release + sha256);本包只负责消费它。

---

## 与 hacore 栈共存(重要)

**文件层共存,运行层才互斥**:本包与 hacore(Home Assistant + 原生 `matter-server`)可以同时
装在一台机器上,安装过程绝不改动对方。真正抢的资源是两个不同的东西,所以本包的两个服务
**各自独立判定**:

| 本包的 unit | 抢的资源 | 冲突对端 | 启动条件 |
| --- | --- | --- | --- |
| `matter2mqtt.service` | `:5580`(+ `/ble`) | `matter-server.service` | 对端**不存在或未 enable** 时 enable + start |
| `matter-ble-proxy.service` | BLE 适配器(bleak/BlueZ) | `home-assistant.service`(HA 自带 bleak 代理) | 对端**不存在或未 enable** 时 enable + start |

- `preinst`:**对别人什么都不动**。不停、不 disable `home-assistant.service` /
  `matter-server.service`,不删它们的 unit,**更不删 `/srv/homeassistant`、
  `/srv/matter_server`**——那是 hacore 的程序目录,删掉会让 dpkg 仍以为 hacore 装着而 HA 已被
  掏空,同版本的 hacore deb 又会被 U 盘安装器判为"已最新"跳过,等于回不去。只清理本包自己的
  历史路径 `/srv/matter2mqtt`,并 `stop`(**不 disable**)本包自己的两个服务。**不动
  mosquitto**(共享 broker)。
- `postinst`:按上表逐个 unit 决策,判据是对端的 `is-enabled` 或 `is-active`(对端仅被手工
  `start` 也算在场,否则只会撞 `EADDRINUSE` / 抢 hci0)。不满足启动条件的那个 unit
  **保持原状:不启动、不 enable,也不 disable**。
- 由此有两个有用的非对称组合:HA 停用而原生 `matter-server` 仍 enabled 时,本包的 BLE 代理会
  起来,通过 `:5580/ble` 给**原生** matter-server 补上 BLE(它同样跑 `--ble-proxy`);HA
  enabled 而 `matter-server` 未 enable 时,matter2mqtt 起来但没有 BLE provider——上报与控制
  正常,BLE 配网不可用。
- 切换栈是**显式的运维动作**,包不替你做:

  ```bash
  systemctl disable --now home-assistant.service matter-server.service
  systemctl enable  --now matter2mqtt.service matter-ble-proxy.service
  ```

  彻底换栈建议先 `dpkg -r thirdreality-hacore`,让 dpkg 状态与磁盘一致。
- `hubv3-usb-sync.sh` 不再因为"U 盘上有 `hacore_*.deb`"而跳过本包;两个 deb 可以放同一张盘,
  hacore 先装、matter2mqtt 后装,后者按上表自行让位。
- `build_common.sh` 的 `tr_exclusive_peer()` 保证构建后恢复服务时不会把两栈同时拉起。

### 升级(同一个包换版本)时的时序

dpkg 的调用顺序是 `旧包 prerm upgrade` → `新包 preinst upgrade` → 解包 → `新包 postinst
configure`。解包会覆盖 `/opt/matter2mqtt` 下约 2.5 万个文件(node_modules + BLE venv),**跑
着的 node / python 被换掉文件行为不可预测**,所以解包前必须停:

- 常规升级由**旧包的 `prerm`** 完成(它从第一版起就无条件 `stop` 两个服务)。
- **新包的 `preinst` 再停一次**作为保险,覆盖 prerm 没跑到的残局(上次安装被打断留下的
  `half-installed` / `half-configured`、`dpkg -i --force-*` 等)。幂等,首装时是 no-op。
- 两处都只 `stop`、**绝不 `disable`**:`postinst` 只在对端不在场时才会 enable,若这里 disable
  了,运维手工 enable 的状态会在升级中被静默丢掉。
- 升级后由 `postinst` 按上表决定是否重新 `start`。主路径都能恢复原状(纯 matter2mqtt 机、
  或已切换过去的机器,对端都不在场)。唯一停着不自动起的是**双栈同时 enabled 的异常态**——
  此时不拉起更安全,`postinst` 会打印 WARNING 说明它仍是 enabled、重启后才会起来(届时会和
  原生栈抢资源,应先 disable 一边)。

> 反向场景仍有缺口:hacore 的 `postinst` 会无条件 enable + start `home-assistant.service` /
> `matter-server.service`,且不检查 matter2mqtt。若机器上 matter2mqtt 已 enabled,再装 hacore
> 就会两栈同时 enabled,重启后谁先起谁占住 5580,另一个反复重启。要堵住得在 hacore 侧加守卫。

---

## 补丁(幂等,每次构建校验重打)

原地 npm/pip 重装会覆盖补丁文件,故 `build.sh` 用 `tr_apply_patch_idempotent`(带 sentinel)
每次构建都按需重打:

| patch | 目标 | sentinel | 作用 |
| --- | --- | --- | --- |
| `matter_ble_proxy_mtu.patch` | `matter_ble_proxy/client.py` | `_acquire_mtu` | 连接后补取协商 ATT MTU。bleak/BlueZ 默认停在 23,导致 BTP 被拆成 20 字节小分片、大读拖垮设备断连。实测 MTU 23→247、关键读 5.6s→0.24s,配对稳定。 |
| `matterjs_commissioning_timing.patch` | `@matter/protocol` 的 `ControllerCommissioningFlow.js` | `TR-PATCH` | 跳过 `addOrUpdateWiFiNetwork` 后多余的 networks 回读(WiFi 场景 NetworkID==SSID),把时间窗留给 `connectNetwork`。根因是脆弱固件在写网络后 ~5s 停 GATT(曾误判为 0.17.9 回归,已证伪)。 |

> MQTT channel 相关逻辑已并入分叉的 `packages/mqtt-bridge`,不再以本仓库 patch 形式存在。

---

## 安全底线

硬约束:**敏感信息不外发**——配对码、证书/凭证(NOC、根证书、fabric)、ACL、group-key 等
不得进入 MQTT。该过滤现由**分叉内 mqtt-bridge** 负责(白名单式:只发业务簇),本仓库无法直接
审计。发布前建议抓包核对:

```bash
mosquitto_sub -t 'matter2mqtt/#' -v   # grep 敏感字段命中数应为 0
```

> `matter2mqtt.service` 里 MQTT 凭证为本机 localhost 明文(弱口令);仅用于本机 mosquitto,
> 若 broker 有对外暴露面需另行加固。

---

## 目录说明

```
build.sh                     构建脚本(装分叉 + BLE venv + 打补丁 + 打 deb)
prebuild/
  DEBIAN/                    control / preinst / postinst / prerm / postrm
  matter2mqtt.service        matter-server(含 MQTT channel)的 systemd unit
  matter-ble-proxy.service   BLE 代理的 systemd unit
  matter_ble_proxy_mtu.patch            MTU 修复补丁
  matterjs_commissioning_timing.patch   配网时序补丁
  matter-server-<ver>.tgz(+ .sha256)   分叉发布 tarball(gitignore,不进 git)
docs/
  build-tarball.sh           仅供参考:早期从 fork 工作树打 tarball 的原型脚本。
                             正式产出流程见上游 matterjs-server 仓库,不在本包构建路径内。
output/                      构建产物工作目录(gitignore)
```

---

## 升级 matter-server 分叉时的回归清单

1. 配对:BLE 设备可配上(日志 `Commissioned`)。
2. MTU:ble-proxy 日志 `negotiated ATT MTU=247`(非 23)。
3. MQTT channel:`--help` 含 `mqtt-url`;`mosquitto_sub -t 'matter2mqtt/#'` 有业务簇上报,
   敏感字段命中 0。
4. 控制:经 MQTT 发 on/off/toggle/moveToLevel,`onOff` 状态随之变化(含无参命令)。
5. 两个补丁仍成功应用(sentinel 命中或重新打上)。
6. 与 hacore 栈的共存行为符合 `preinst`/`postinst` 预期:`/srv/homeassistant`、
   `/srv/matter_server` 仍在,HA / 原生 matter-server 的 enabled 状态未被改动,mosquitto 未被
   误停,两个 unit 各自按对端状态决定是否启动。
