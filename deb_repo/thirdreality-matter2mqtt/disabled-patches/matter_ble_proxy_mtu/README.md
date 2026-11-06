# matter_ble_proxy_mtu.patch（已停用）

**本补丁不再应用。** 2026-11-06 决定：BLE 配网使用 matter-ble-proxy 默认的 20 字节 BTP 分段，与上游 matterjs-server、
Home Assistant、Python Matter Server 一致。补丁文件留在这里备查，`build.sh` 不会打它；如果构建机上已有的 venv 里
还带着它，`build.sh` 会把它撤掉，并在仍然存在时中止打包。

## 它做什么

目标文件：matter-ble-proxy 0.7.1 的 `matter_ble_proxy/client.py`，连接成功之后。

- BlueZ 连接后会和设备协商 ATT MTU（夜灯为 247），这一步与补丁无关、总会发生。
- bleak 默认不读取协商结果，代理按最小值 23 报给 matter.js，matter.js 于是用 20 字节 BTP 分段。
- 补丁调用 bleak 的 `_acquire_mtu()` 读出实际 MTU（247）报上去，matter.js 改用 244 字节分段，
  每次 GATT 写入能带更多数据，往返次数少得多。
- 它不改变连接参数、链路层单包大小（仍是 27 字节）或 ATT MTU 本身。

## 为什么停用

1. **当初的理由已不成立。** 加它是为了让 WiFi 夜灯在 `addOrUpdateWiFiNetwork` 之后的网络列表读取变快
   （20 字节时约 5.6 s，夜灯会断开 BLE）。`matterjs_commissioning_timing.patch` 已经跳过了这次读取。
   去掉本补丁后夜灯配网成功、中途没有断开（2026-11-06，node 19）。
2. **它让部分设备配不上网。** ThirdReality Thread 开关（VID 5127 / PID 12424）在 BTP 握手里同意了 241 字节分段，
   但收到第一个需要链路层分片的大包后链路中断；20 字节分段时正常。IKEA GRILLPLATS 插座有同样的现象，
   matter.js 在 noble 路径上为此加了"握手后卡住就用 20 字节重新握手"的变通做法
   （[matter.js #4269](https://github.com/matter-js/matter.js/pull/4269)），并明确它不是规范行为；
   matterjs-server 的 BLE 代理通道（`ProxyBleChannel`）截至 2026-10-31 的上游 main 没有接入。
   没有查到 Matter 规范要求控制器必须报告协商后的 MTU。
3. 与上游一致，少维护一个补丁。

## 代价

配网变慢，主要慢在 PASE 和证书收发这几步：

| 设备 | 有本补丁（244 字节） | 无本补丁（20 字节） |
|---|---|---|
| ThirdReality WiFi 夜灯 | 约 17 s（2026-11-06 02:43，node 16） | 约 66 s（2026-11-06 03:12，node 19） |
| ThirdReality Thread 开关 | 配网失败 | 约 67 s（2026-11-05 06:44，node 6） |

## 如果要重新启用

不建议直接恢复。若以后需要更快的配网，应当同时处理会卡住的设备，例如在 `ProxyBleChannel` 里接入 matter.js 的
`BtpSessionHandler.stalledAfterHandshake`，卡住时用 20 字节重新握手（参照 `NobleBleChannel`），或者使用已经做了这一点的上游版本。
恢复时：把本补丁加回 `build.sh` 的 [2c]，并删掉 [2c]/[2d] 中"必须不存在"的检查。

本补丁与 `matter_ble_proxy_pause_scan.patch` 改的是同一个文件，两者先后顺序均可，也可以用 `patch -R` 单独撤掉。

## 记录

matterjs-server 仓库（`tr/feature/mqtt-bridge`）：
- `docs/history/2026-11-05-real-device-commissioning.zh-CN.md` 第 1 节：开关失败的 HCI 抓包分析，以及 2026-11-06 的
  停用决定和配网耗时对比。
