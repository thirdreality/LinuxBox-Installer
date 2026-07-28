# Bug report draft — matter-js/matterjs-server

> 供粘贴到 matterjs-server 的 **Bug report** 模板。字段名按常见 Bug report 模板排布，
> 实际提交时以仓库模板为准，把对应段落填进去即可。
> **日志已脱敏**（WiFi SSID/密码、BLE MAC、证书/密钥/passcode 全部替换为占位符）。

---

## Title

Commissioning aborts on BLE disconnect before ConnectNetwork for a device that advertises concurrent connection but behaves non-concurrently

---

## Describe the bug

When commissioning a Wi-Fi + BLE device that reports
`GeneralCommissioning.SupportsConcurrentConnection = true` but, in practice,
tears down the BLE link a few seconds after `AddOrUpdateWiFiNetwork` (i.e.
**before** the commissioner sends `ConnectNetwork`), matter-server aborts the
whole commissioning with a fatal `[ble-channel-closed]` error.

At the point of failure the Node Operational Credentials have already been
installed successfully (`AddNOC` returned `Ok`), so commissioning could in
principle continue via operational (CASE / mDNS) discovery rather than being
aborted.

**This is a regression for us.** The identical device commissioned reliably in
the same deployment (same fabric admin, same hub, same Wi-Fi/BLE environment)
on **python-matter-server** — the previous Matter Server implementation that
matter.js now replaces. The only thing that changed is the server
implementation: after migrating from python-matter-server to matter-server
(matter.js), this device can no longer be commissioned over BLE. The CHIP SDK
controller underneath python-matter-server is more tolerant of this timing
(sends `ConnectNetwork` immediately with no intervening full read, and does not
treat a post-`AddNOC` BLE drop as fatal).

I want to be upfront: **the device firmware is the root cause** — it advertises
concurrent connection but does not honour it. This report is not asking you to
treat a non-compliant device as correct. It asks whether matter.js can be made
more resilient to this specific, recoverable case, the way the reference CHIP
controller already is, to improve real-world interoperability. We are pursuing
the firmware fix in parallel.

---

## To reproduce

Commission a Wi-Fi device with these characteristics:

1. It advertises `SupportsConcurrentConnection = true`.
2. It runs a single-radio SoC, so joining Wi-Fi forces BLE down.
3. Firmware starts the Wi-Fi join immediately upon receiving
   `AddOrUpdateWiFiNetwork`, dropping BLE ~5–6 s later — before the
   commissioner reaches `ConnectNetwork`.

Observed message sequence (see sanitized log below):

1. PASE over BLE — OK
2. ArmFailSafe — errorCode 0
3. SetRegulatoryConfig — errorCode 0
4. DeviceAttestation — accepted (1 non-fatal finding: `PaaTrustStoreTimeMismatch`)
5. CSRRequest / AddTrustedRootCertificate / **AddNOC → Ok (fabricIndex 1)**
6. Re-arm failsafe; AccessControl; NetworkCommissioning.Validate; NetworkCommissioning.Wifi
7. `addOrUpdateWiFiNetwork` → **networkingStatus: 0 (Success)**
8. matter.js issues **`Read 0.networkCommissioning.*`** (full-cluster attribute read)
9. **~5.6 s after step 7, before any `ConnectNetwork` is sent, the device
   disconnects BLE** (`Peripheral ... disconnected unexpectedly`)
10. `ERROR Commission failed: Operation aborted` → `Caused by: [ble-channel-closed]`

Note there is **no `ConnectNetwork` invoke anywhere** between the successful
`addOrUpdateWiFiNetwork` and the abort.

---

## Expected behavior

For a device whose BLE link drops after `AddNOC` has succeeded and the Wi-Fi
credentials have been accepted, matter-server should be able to fall back to
operational (mDNS/CASE) discovery and complete commissioning over the
operational network — instead of treating the BLE disconnect as an
unrecoverable error. This mirrors the CHIP SDK controller behaviour.

---

## Actual behavior

matter-server classifies the post-`AddOrUpdateWiFiNetwork` BLE disconnect as a
fatal transport error and aborts commissioning:

```
Commission failed: Operation aborted
  Caused by: [aborted] Operation aborted
  Caused by: [ble-channel-closed] BLE transport closed on @0:0•<node>(ble)
    at .../@matter/protocol/src/peer/ControllerCommissioner.ts:549:36
    at ProxyBleChannel.emitClosed (.../@matter/protocol/src/ble/Ble.ts:69:22)
```

---

## Analysis

Two independent factors combine:

**Device side (root cause).** The firmware advertises concurrent connection but
its single radio cannot keep BLE up while associating to Wi-Fi. Firmware bug,
fix in progress with the vendor (either set
`SupportsConcurrentConnection = false`, or keep BLE alive until `ConnectNetwork`).

**Controller side (robustness opportunity).** Because the device claims
concurrent support, matter.js follows the concurrent flow, which performs a
full `Read 0.networkCommissioning.*` between `AddOrUpdateWiFiNetwork` and
`ConnectNetwork` (log step 8). That read widens the window during which the
device — already racing to bring up Wi-Fi — drops BLE, and the drop is then
treated as fatal.

By contrast the CHIP SDK controller (a) sends `ConnectNetwork` immediately
after `AddOrUpdateWiFiNetwork` with no intervening full read, landing inside
the device's window, and (b) does not treat a post-`AddNOC` BLE drop as fatal —
it falls through to operational discovery and completes CASE over the
operational network. That is why the same device commissions on CHIP but not
on matter.js.

---

## Proposed improvement (for discussion)

Either or both, whichever fits matter.js's design:

1. **Tighten concurrent-flow timing:** avoid / defer the full
   `Read 0.networkCommissioning.*` between `AddOrUpdateWiFiNetwork` and
   `ConnectNetwork`, sending `ConnectNetwork` promptly (closer to CHIP
   ordering). This alone would likely land inside the device's window.
2. **Tolerate a post-AddNOC BLE drop as recoverable:** if BLE closes after
   `AddNOC` has succeeded and network credentials were accepted, attempt
   operational (mDNS/CASE) discovery instead of aborting. This mirrors the
   reference controller and helps any device that behaves non-concurrently
   regardless of what it advertised.

We understand option 2 has trade-offs (distinguishing "device is joining Wi-Fi"
from "device genuinely failed") and are happy to discuss guardrails such as a
bounded timeout.

---

## What we ruled out

- **AP isolation / reachability:** verified same-AP clients have full IPv4/IPv6
  (incl. link-local fe80) unicast + TCP connectivity. An earlier "address
  discovered but unreachable" symptom was a stale mDNS cache from a device that
  had gone offline mid-commissioning, not isolation.
- **BLE transport implementation:** the abort reproduces with **both** the
  local adapter (noble, `--bluetooth-adapter`) and the BLE proxy
  (`--ble-proxy`), so it is the commissioning state machine's handling of the
  disconnect, not the transport, that decides the outcome.

---

## Environment

- matter-server: 1.2.8 (`@matter/main` 0.17.7-alpha.0-20260720-00d9d6fbf,
  `@matter/protocol` same)
- Node.js: v24.18.0
- OS: Debian 12 (bookworm), aarch64
- BLE path: reproduced on both `--ble-proxy` and `--bluetooth-adapter`
- Device under test: see "Matter device information" below

---

## Matter device information

| Field | Value |
| --- | --- |
| Manufacturer | ThirdReality |
| Vendor ID | `0x1407` (5127) |
| Product ID | `0x1088` (4232) |
| Product name | Smart Color Night Light |
| Product page | https://www.thirdreality.com/products/smart-color-night-light |
| Discriminator | 4 |
| SupportsConcurrentConnection (GeneralCommissioning 0x30 / attr 0x04) | **true** (device follows non-concurrent behaviour in practice) |
| SoC / radio | BouffaloLab, single radio shared by BLE + Wi-Fi |
| Device attestation | DAC chain verified; 1 non-fatal finding (`PaaTrustStoreTimeMismatch`) |
| Software / firmware version | not captured in this trace (can provide on request) |
| HardwareVersion | not captured in this trace (can provide on request) |

> VID/PID/product name/discriminator/concurrent-connection flag are taken
> directly from the commissioning trace (device advertisement + BasicInformation
> report). Software/hardware version were not present in this particular
> BasicInformation report; we can provide them on request.

---

## Spec context (offered as context, not a compliance claim)

The Matter core commissioning flow allows the commissioner to complete via
operational discovery (CASE over the operational network) after
`ConnectNetwork`; for a non-concurrent device, BLE teardown at network-join
time is expected and the commissioner continues over the operational network.
The gap here is that the device mislabels itself as concurrent, so matter.js
does not fall back to that path even though, after `AddNOC`, it has everything
needed to discover the node operationally.

---

## Willing to help

I can provide the full anonymised commissioning trace (both adapter and proxy
paths) plus a matching CHIP controller trace for the same device, and can test
candidate fixes on real hardware.

---

## Sanitized log excerpt (matter-server, `--ble-proxy`)

> Cryptographic material, Wi-Fi SSID/credentials, BLE MAC addresses, passcode
> and node/fabric identifiers have been replaced with placeholders.

```
04:29:47 INFO ControllerCommandHandler BLE is enabled (proxy mode)
05:53:48 INFO ProxyBleClient Discovered commissionable device <BLE_MAC> ... via proxy
         (advert: D=4, CM=1, VP=<VID>+<PID>)
05:53:48 INFO ControllerCommissioner Establish PASE to device VP: <VID>+<PID>
05:54:05 INFO ControllerCommissioner Start commissioning of node @1:<n> into fabric <f>
05:54:11 INFO ControllerCommissioner Executing step 7.1: GeneralCommissioning.ArmFailsafe
05:54:14 INFO ClientInteraction Invoke « ...generalCommissioning.armFailSafe errorCode: 0
05:54:16 INFO ClientInteraction Invoke « ...generalCommissioning.setRegulatoryConfig errorCode: 0
05:54:16 INFO ControllerCommissioner Executing step 10.1: OperationalCredentials.DeviceAttestation
05:54:34 INFO ControllerCommandHandler Attestation finding (info): PaaTrustStoreTimeMismatch ... (non-fatal)
05:54:34 INFO ControllerCommandHandler Attestation accepted
05:54:34 INFO ControllerCommissioner Device attestation successfully verified with 1 accepted finding(s)
05:54:34 INFO ControllerCommissioner Executing step 11.1: OperationalCredentials.Certificates
05:54:46 DEBUG ControllerCommissioner Commissioning step addNoc returned Ok (0), fabricIndex: 1
05:54:46 INFO  ControllerCommissioner After step 11.1 succeeded, 27.7s left for failsafe timer, re-arming
05:54:48 INFO ControllerCommissioner Executing step 15.1: AccessControl
05:54:48 INFO ControllerCommissioner Executing step 16.1: NetworkCommissioning.Validate
05:54:48 INFO ControllerCommissioner Executing step 16.2: NetworkCommissioning.Wifi
05:54:49 DEBUG ControllerCommissioner Root Networks found: {wiFiNetworkInterface:true, thread:false, ethernet:false}
05:54:49 DEBUG ControllerCommissioner Configuring WiFi network ...
05:54:56 INFO ClientInteraction Invoke » ...networkCommissioning.addOrUpdateWiFiNetwork ssid: <REDACTED> credentials: <REDACTED> breadcrumb: 3
05:54:58 INFO ClientInteraction Invoke « ...networkCommissioning.addOrUpdateWiFiNetwork networkingStatus: 0 networkIndex: 0
05:54:58 DEBUG ControllerCommissioner Commissionee added WiFi network <SSID> with network index 0
05:54:58 INFO ClientInteraction Read » ...0.networkCommissioning.*        <-- full-cluster read, no ConnectNetwork yet
05:54:59 DEBUG BtpSessionHandler (read response fragments over BTP)
05:55:04 INFO ProxyBleChannel Peripheral <BLE_MAC> disconnected unexpectedly   <-- ~5.6s after add success
05:55:04 INFO Session ... Session ended
05:55:04 ERROR WebSocketControllerHandler Commission failed: Operation aborted
         Caused by: [aborted] Operation aborted
         Caused by: [ble-channel-closed] BLE transport closed on @0:0•<node>(ble)
           at .../@matter/protocol/src/peer/ControllerCommissioner.ts:549:36
```
