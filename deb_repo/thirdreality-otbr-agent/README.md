# thirdreality-otbr-agent

为 ThirdReality LinuxBox Dev Edition 构建的 **OpenThread Border Router (OTBR)**
`.deb` 包（arm64 / Debian 12 bookworm）。提供 `otbr-agent`（Thread 边界路由代理）、
`otbr-web`（Web GUI）、`ot-ctl`，以及配套的 systemd 服务、防火墙/NAT64 规则与
开机配置。

> 构建过程**参考**了 Home Assistant 的 add-on
> [`openthread_border_router`](https://github.com/home-assistant/addons/tree/master/openthread_border_router)，
> 但我们产出的是 `.deb`（跑在宿主 systemd 上），**不是 docker 镜像**——所以 add-on 里
> s6 的 `run`/`finish`、`enable-check.sh` 等逻辑，被我们改写进了 systemd 的
> `ExecStartPre/ExecStopPost` drop-in 和维护脚本。

---

## 一、版本与上游对应关系（重要）

- 源码：`github.com/openthread/ot-br-posix`，checkout 到
  commit `ec16e396382b4559e70a2c6fdeecb7d596a5e915`（tag **v2026.07.0**）。
- **这个 commit 是 add-on 的 `OTBR_BETA_VERSION`，即我们跟的是 beta，不是 stable**
  （add-on 的 stable 是另一个更早的 commit `624a7d98`）。
- 因为跟 beta：add-on 里 stable 专用的两个 patch
  （`0001-rest-SO_REUSEADDR`、`0002-nat64-handle-ipv4-options`）**不打**。
- Thread 版本 1.4；`OTBR_MDNS=openthread`（内置 mDNS，不再依赖旧版 mDNSResponder）。
- 升级 OTBR 版本时，`build.sh` 顶部的 `COMMIT=` 和 `DEBIAN/control` 的 `Version:` 一起改。

---

## 二、构建

```bash
./build.sh            # 构建 deb
./build.sh --rebuild  # 删除已 clone 的源码/output 后重建
./build.sh --clean    # 卸载服务、删除源码/output/deb、清理系统安装的二进制与规则
```

- 依赖前置系统包（见 `DEBIAN/control` 的 `Depends`）：
  `iptables, ipset, iputils-ping, libprotobuf-lite32, libjsoncpp25, iproute2, bind9`。
- **内存/OOM**：本设备内存小（~2GiB），编译 OpenThread C++ 峰值高。`build.sh` 通过
  `source ../build_common.sh` 复用统一的 OOM 守护：编译前按需建临时 swap、临时停无关
  重内存服务（HA / matter / z2m / mosquitto / music-assistant / **otbr-agent / otbr-web**），
  结束（含失败/中断）自动 swapoff + 恢复服务。开关：`TR_SKIP_SWAP=1` / `TR_KEEP_SERVICES=1`
  / `TR_SWAP_TARGET_MIB=N`。
- cmake 关键参数（`build.sh` Step 5）：`CMAKE_INSTALL_PREFIX=/usr`、`OTBR_DBUS=OFF`、
  `OTBR_MDNS=openthread`、`OTBR_WEB=ON`、`OTBR_NAT64=ON`（CIDR `192.168.255.0/24`）、
  `OT_THREAD_VERSION=1.4`、`OT_RCP_RESTORATION_MAX_COUNT=2`（对齐 add-on beta，掉链更稳）。
- `script/bootstrap` 只 apt 装编译/运行依赖，**不做系统配置**；其中会顺带装 `dbus`、
  `rsyslog`、gmock/gtest —— 我们 `DBUS=OFF` 用不到 dbus，属冗余但无害。

### bookworm vs trixie 的 libjsoncpp

add-on 基于 Debian 13 trixie（`libjsoncpp26`/`libncurses6`），**我们目标是 Debian 12
bookworm，用的是 `libjsoncpp25`**（系统实际为 1.9.5-4）。所以 `Depends` 写 `libjsoncpp25`
是对的，不要照抄 add-on 改成 26。

### 用 dpkg 安装时的依赖

`dpkg -i otbr-agent_*.deb` **不会自动解析 Depends**（包名仍是 `thirdreality-otbr-agent`，
只是产出文件名用短名 `otbr-agent_<版本>.deb`）。若提示缺 `libjsoncpp25` 等，安装后补一句：
`apt-get -f install`。

---

## 三、服务拓扑：hubv3-otbr-agent 是总闸

只有 **`hubv3-otbr-agent.service`** 被 `enable`（`WantedBy=multi-user.target`）。
其余两个服务不独立 enable，全部由总闸拉起：

```
hubv3-otbr-agent.service (oneshot, 总闸, 唯一 enable)
        │ Wants + After
        ▼
otbr-agent.service  ──ExecStartPre→ otbr-firewall.sh setup
        │ Wants               ExecStopPost→ otbr-firewall.sh teardown
        ▼                     PartOf = hubv3-otbr-agent.service
otbr-web.service     After + BindsTo = otbr-agent.service
```

- `systemctl enable --now hubv3-otbr-agent` → 拉起 agent（建防火墙）→ 带起 web。
- **`systemctl disable --now hubv3-otbr-agent` → 整套 Thread 全关**
  （`PartOf` 连带停 agent → 触发 teardown 拆防火墙；`BindsTo` 连带停 web；开机也不再启动）。
  这是给**没有 Thread 芯片 / 不想用 Thread** 的设备用的"一键关闭"。
- `hubv3-otbr-agent.sh`（oneshot 内容）：做 GPIO 初始化 + `supervisor thread enabled`；
  agent 已由 systemd 依赖拉起，脚本里的 `systemctl start otbr-agent` 只是兜底 no-op。

---

## 四、防火墙 / NAT64

上游 `otbr-agent.service` 是"裸"的（只有 `ExecStart`），**不自带任何防火墙操作**。
规则的建/拆全部由我们的脚本负责，且**成对**执行，避免旧版"只建不拆"导致重启/升级后
规则累积：

- 脚本：`/usr/lib/thirdreality/otbr-firewall.sh {setup|teardown}`
  （逻辑对齐 add-on 的 s6 `run`/`finish`）。
- 挂点：`otbr-agent.service` drop-in
  `ExecStartPre=…setup` / `ExecStopPost=…teardown`。
- `setup` 幂等：先 `teardown` 再重建，防叠加。
- 内容：ipset `otbr-ingress-{deny-src,allow-dst}(-swap)`（inet6）、ip6tables 链
  `OTBR_FORWARD_INGRESS/EGRESS`、NAT64 的 mangle 打标（`0x1001`）+ nat MASQUERADE +
  `OTBR_FORWARD_NAT64` 链。
- 开关在 `/etc/default/otbr-agent`：`OTBR_FIREWALL`、`OTBR_NAT64`（**默认都开 =1**）。

---

## 五、配置文件与网口

- `/etc/default/otbr-agent`
  - `OTBR_AGENT_OPTS`：`-I wpan0 -B wlan0 -d 5 --rest-listen-address 0.0.0.0
    --rest-listen-port 8081 spinel+hdlc+uart:///dev/ttyAML6?uart-baudrate=115200 trel://wlan0`
  - `OTBR_THREAD_IF=wpan0`、`OTBR_BACKBONE_IF=wlan0`、`OTBR_FIREWALL=1`、`OTBR_NAT64=1`
  - **网口说明**：`-I wpan0` 是 Thread 侧虚拟网口；`-B <backbone>` 是**上行/局域网口**
    （Backbone Router 用它把 Thread 接入现有 IPv6 LAN、组播转发、TREL）。本设备只有
    wifi，所以 backbone = **wlan0**。改网口时 `OTBR_AGENT_OPTS` 的 `-I/-B/trel://`
    与 `OTBR_THREAD_IF/OTBR_BACKBONE_IF` 要一致。
- `/etc/default/otbr-web`：`OTBR_WEB_OPTS="-I wpan0 -p 8080 -a 0.0.0.0"`
  —— Web GUI 端口 **8080**（避开 80）；REST API 在 **8081**（otbr-agent 提供）。
- 开机系统配置由 `DEBIAN/postinst` 写入：`sysctl`（IPv6 转发、`wlan0` accept_ra、
  `optmem_max`）、`/etc/iproute2/rt_tables` 追加 `88 openthread`、`modprobe`
  `ip6table_filter/ip6_tables/xt_set`。

---

## 六、安装 / 升级 / 卸载行为

- **preinst**：先停总闸 hubv3（连带停 agent→teardown、web），再兜底停 web/agent；
  清理旧版 mDNSResponder 遗留文件（`mdnsd`、`libdns_sd`、`libnss_mdns`、旧 init.d 等）。
- **postinst（configure）**：写 sysctl/rt_tables/modprobe → `disable` 旧版可能遗留的
  `otbr-agent/otbr-web` 独立自启 → 只 `enable` 总闸 hubv3 → 启动 hubv3；随后轮询
  `http://localhost:8081/node`，就绪后调用 `otbr_database` 把 Thread 信息写入 HA 配置
  （若 HA 在跑会先停 HA 再写、写完再起）。
  - **备份/恢复流程**：若检测到 `/mnt/R3Backup` 有 `.enable-restore` 且存在
    `setting_*.tar.gz`，则跳过自动配置（`SKIP_AUTO_CONFIG=true`），交给恢复流程。
- **prerm（remove/purge）**：停总闸+服务、兜底 `otbr-firewall.sh teardown`、删 drop-in、
  删 `rt_tables`/`sysctl` 项、删 `/var/lib/thread`。
- **升级路径**：dpkg 升级时 `prerm upgrade` 不匹配 remove/purge，所以
  **`/var/lib/thread`（Thread 网络凭据）在升级时会保留**；防火墙的清理靠 preinst 停服务
  触发 `ExecStopPost` 完成，天然干净，无需在 prerm 里为 upgrade 单独拆。

---

## 七、注意事项 / 已知坑（务必看）

1. **`Requires=dbus.socket` 已被 drop-in 清除**：上游生成的 unit 模板写死了对 dbus 的
   硬依赖，但我们 `-DOTBR_DBUS=OFF`。`otbr-agent.service.d/firewall.conf` 用空 `Requires=`
   重置它，避免没装 dbus 的设备起不来。（bootstrap 会装 dbus，但那只是构建机行为。）
2. **升级残留**：旧版 postinst 曾 `enable otbr-agent/otbr-web`。新模型只 enable 总闸，
   故 postinst 会先 `disable` 这两个，清掉旧的 `WantedBy` 符号链接，否则它们会绕过总闸
   自启。
3. **真机才验证得了防火墙**：`otbr-firewall.sh setup` 会真正写 ip6tables/ipset/NAT64，
   且需要 `wpan0` 存在。在无 Thread 芯片的机器上只能验证 `teardown`（安全 no-op）。
   上设备后建议实测：
   - `systemctl enable --now hubv3-otbr-agent` → `ip6tables -L OTBR_FORWARD_INGRESS`
     有规则、`ipset list -n` 有 `otbr-ingress-*`；
   - 反复 `restart otbr-agent`，确认规则**不累积**；
   - `systemctl disable --now hubv3-otbr-agent` → 链和 ipset 被清空、agent/web 都停。
4. **子模块**：`build.sh` 用 `git submodule update --init`（非 `--recursive`），当前版本
   可正常编译；若将来上游拆分出需递归的子模块，编译报缺文件时改成 `--recursive`。
5. **串口**：`spinel+hdlc+uart:///dev/ttyAML6@115200` 是本硬件的 RCP 串口，换硬件需改。

---

## 八、文件清单

| 路径 | 说明 |
|------|------|
| `build.sh` | 编译打包脚本（clone→bootstrap→cmake→ninja install→收集→dpkg-deb） |
| `openthread-core-ha-config-posix.h` | OpenThread 编译期配置头（首次构建自动下载） |
| `DEBIAN/{preinst,postinst,prerm,control}` | 维护脚本与包元信息 |
| `prebuild/otbr-firewall.sh` | 防火墙/NAT64 建拆脚本（setup/teardown） |
| `prebuild/otbr-agent` | `/etc/default/otbr-agent`：agent 参数 + 防火墙开关 + 网口 |
| `prebuild/otbr-web` | `/etc/default/otbr-web`：web GUI 参数 |
| `prebuild/hubv3-otbr-agent.{service,sh}` | 总闸 oneshot（GPIO 初始化 + 拉起 agent） |
| `prebuild/otbr-agent-init.sh` | GPIO 初始化脚本（备用） |
| `prebuild/otbr_database` | 把 Thread 信息写入 HA 配置的工具 |
