# thirdreality-otbr-agent

An **OpenThread Border Router (OTBR)** `.deb` package (arm64 / Debian 12 bookworm)
built for the ThirdReality LinuxBox Dev Edition. It provides `otbr-agent` (the Thread
border router agent), `otbr-web` (the Web GUI) and `ot-ctl`, together with the
matching systemd services, firewall/NAT64 rules and boot-time configuration.

> The build is **modelled on** the Home Assistant add-on
> [`openthread_border_router`](https://github.com/home-assistant/addons/tree/master/openthread_border_router),
> but what we produce is a `.deb` running under the host's systemd, **not a docker
> image** -- so the add-on's s6 `run`/`finish` and `enable-check.sh` logic has been
> rewritten into systemd `ExecStartPre`/`ExecStopPost` drop-ins and maintainer scripts.

---

## 1. Version and upstream correspondence (important)

- Source: `github.com/openthread/ot-br-posix`, checked out at
  commit `cb4bdae242b22287cded07ae3aa10347c2d16d9b` (tag **v2026.10.0**).
- **This commit is the add-on's `OTBR_BETA_VERSION`, i.e. we follow the beta, not the
  stable** (the add-on's stable is a different commit, `fd872ab9`).
- Thread version 1.4; `OTBR_MDNS=openthread` (built-in mDNS, no longer dependent on
  the old mDNSResponder).
- When upgrading the OTBR version, change `COMMIT=` at the top of `build.sh` and
  `Version:` in `DEBIAN/control` together.

### What changed in v2026.07.0 -> v2026.10.0

- Upstream added an **opt-in in-process nftables firewall backend**
  (`-DOTBR_NFTABLES`, Linux only) and a pf backend (`-DOTBR_PF`, macOS only). We keep
  **both OFF** and stay on our own `otbr-firewall.sh` (ipset/ip6tables), so firewall
  behaviour is unchanged. `build.sh` passes both flags explicitly rather than relying
  on the upstream defaults.
- Even with both backends off, the build now **always installs two marker files**,
  `/usr/share/otbr/{nftables-backend,pf-backend}`, which the legacy firewall scripts
  read to decide who owns the rules. They contain `0` for us. Both are listed in
  `STAGED_FILES` so the manifest check stays honest.
- The frontend gained an npm dependency (`qrcode-generator`) and now also copies
  `package-lock.json`. Nothing to do here -- `npm install` covers it.
- `script/bootstrap` now also apt-installs `libnftnl-dev` and `libmnl-dev`
  unconditionally. Both exist on bookworm (1.2.4-2 / 1.0.4-3); they are only needed
  when `OTBR_NFTABLES=ON`, so for us they are redundant but harmless.
- Note: the two stable-only patches an earlier version of this document mentioned
  (`0001-rest-SO_REUSEADDR`, `0002-nat64-handle-ipv4-options`) **no longer exist
  upstream** -- the add-on dropped its `patches/` directory entirely and applies no
  patches to either stage. There is nothing to skip any more.

---

## 2. Building

```bash
./build.sh            # build the deb
./build.sh --rebuild  # delete the cloned source/output, then rebuild
./build.sh --clean    # uninstall services, delete source/output/staging/deb, clean up rules
```

> `--clean` uninstalls **package manager first**: when `thirdreality-otbr-agent` is
> dpkg-managed it uses `apt-get purge`, and only hand-deletes those few paths when
> there is no dpkg record (i.e. the legacy case where the old `build.sh` had
> `ninja install` write straight into `/usr`). It also **only removes this package's
> own three scripts** (`hubv3-otbr-agent.sh` / `otbr_database` /
> `otbr-firewall.sh`) and no longer does `rm -rf /usr/lib/thirdreality` -- that
> directory also holds `hubv3-usb-sync.sh`, `post-fix-zigbee2mqtt.sh`,
> `resetupwifi.sh`, `hubv3-generate-ota-indexes.sh`, `conf/` and more, most of which
> belong to no deb (they ship in the image), so deleting them cannot even be undone by
> reinstalling the package. The directory itself is **never removed** (not even an
> `rmdir`): it is a shared landing spot for several packages and the image, and
> leaving an empty directory costs far less than deleting it by mistake.

- Required system packages (see `Depends` in `DEBIAN/control`):
  `iptables, ipset, iputils-ping, libprotobuf-lite32, libjsoncpp25, iproute2, python3`.
  `python3` is the interpreter for `otbr_database`; it only uses the standard library,
  so the system python3 is enough and hacore's `/srv/homeassistant` is not required.
- **Memory/OOM**: this device has little RAM (~2GiB) and compiling OpenThread's C++
  peaks high. `build.sh` reuses the shared OOM guard via
  `source ../build_common.sh`: it provisions temporary swap as needed before
  compiling and temporarily stops unrelated memory-heavy services (HA / matter / z2m /
  mosquitto / music-assistant / **otbr-agent / otbr-web**), then automatically
  swapoffs and restores the services on exit (including on failure or interrupt).
  Toggles: `TR_SKIP_SWAP=1` / `TR_KEEP_SERVICES=1` / `TR_SWAP_TARGET_MIB=N`.
- **Packaged content is collected from `staging/`, never from the build host's
  `/usr`**: `ninja install` lands via `DESTDIR=staging/`
  (`CMAKE_INSTALL_PREFIX=/usr`, so the paths are `staging/usr/...`), and Step 6 copies
  from `staging/` into `output/` against an explicit manifest. It used to install into
  the build host's real `/usr` and copy back out of the root filesystem (that `cp`
  list was originally observed from the openthread project's install), which caused
  three problems, now eliminated: the build swapped binaries under a running gateway
  and those files bypassed dpkg; once the deb had been installed, a copied unit could
  be a leftover from the previous deb rather than this build's output; and when
  upstream changed the install layout the hardcoded list did not follow, silently
  dropping files. There is now a two-way check as well: a manifest file missing from
  `staging/` **aborts the build**, and an executable or unit in `staging/` that is not
  in the manifest **prints a warning** that the manifest needs updating.
- Key cmake arguments (`build.sh` Step 5): `CMAKE_INSTALL_PREFIX=/usr`,
  `OTBR_DBUS=OFF`, `OTBR_MDNS=openthread`, `OTBR_WEB=ON`, `OTBR_NAT64=ON`
  (CIDR `192.168.255.0/24`), `OT_THREAD_VERSION=1.4`,
  `OT_RCP_RESTORATION_MAX_COUNT=2` (matching the add-on beta, more robust against
  dropped links), `OTBR_NFTABLES=OFF`, `OTBR_PF=OFF`.
- `script/bootstrap` only apt-installs build/runtime dependencies and **makes no
  system configuration changes**; it incidentally installs `dbus`, `rsyslog` and
  gmock/gtest -- we use `DBUS=OFF` so dbus is unused, redundant but harmless.

### libjsoncpp on bookworm vs trixie

The add-on is based on Debian 13 trixie (`libjsoncpp26`/`libncurses6`), but **we
target Debian 12 bookworm and use `libjsoncpp25`** (1.9.5-4 on this system). So
`Depends` naming `libjsoncpp25` is correct -- do not copy the add-on and change it
to 26.

### Dependencies when installing with dpkg

`dpkg -i otbr-agent_*.deb` **does not resolve Depends automatically** (the package
name is still `thirdreality-otbr-agent`; only the output file name uses the short
form `otbr-agent_<version>.deb`). If it reports `libjsoncpp25` or similar missing,
follow up with `apt-get -f install`.

---

## 3. Service topology: hubv3-otbr-agent is the master switch

Only **`hubv3-otbr-agent.service`** is `enable`d (`WantedBy=multi-user.target`). The
other two services are not enabled on their own and are pulled in by the master:

```
hubv3-otbr-agent.service (oneshot, master switch, the only enabled unit)
        │ Wants + After
        ▼
otbr-agent.service  ──ExecStartPre→ otbr-firewall.sh setup
        │ Wants               ExecStopPost→ otbr-firewall.sh teardown
        ▼                     PartOf = hubv3-otbr-agent.service
otbr-web.service     After + BindsTo = otbr-agent.service
```

- `systemctl enable --now hubv3-otbr-agent` -> starts the agent (building the
  firewall) -> brings up web.
- **`systemctl disable --now hubv3-otbr-agent` -> turns the whole Thread stack off**
  (`PartOf` stops the agent, triggering the firewall teardown; `BindsTo` stops web;
  and it no longer starts at boot). This is the "one-switch off" for devices with
  **no Thread chip / that do not want Thread**.
- `hubv3-otbr-agent.sh` (the oneshot body): does GPIO initialisation plus
  `supervisor thread enabled`; the agent has already been pulled in by the systemd
  dependency, so the `systemctl start otbr-agent` in the script is just a fallback
  no-op.

---

## 4. Firewall / NAT64

The upstream `otbr-agent.service` is "bare" (only `ExecStart`) and **ships no
firewall handling at all**. Building and tearing down the rules is entirely our
script's job, and it happens **in pairs** so that rules cannot accumulate across
restarts/upgrades the way the old "build but never tear down" version did:

- Script: `/usr/lib/thirdreality/otbr-firewall.sh {setup|teardown}`
  (logic mirroring the add-on's s6 `run`/`finish`).
- Hook points: the `otbr-agent.service` drop-in,
  `ExecStartPre=…setup` / `ExecStopPost=…teardown`.
- `setup` is idempotent: it tears down first, then rebuilds, to prevent stacking.
- Contents: ipsets `otbr-ingress-{deny-src,allow-dst}(-swap)` (inet6), ip6tables
  chains `OTBR_FORWARD_INGRESS/EGRESS`, and for NAT64 the mangle mark (`0x1001`) plus
  nat MASQUERADE plus the `OTBR_FORWARD_NAT64` chain.
- Toggles live in `/etc/default/otbr-agent`: `OTBR_FIREWALL`, `OTBR_NAT64`
  (**both default to 1**).
- Since v2026.10.0 upstream can own these rules in-process instead
  (`-DOTBR_NFTABLES=ON`) and writes `/usr/share/otbr/nftables-backend` to say so.
  We build with it **OFF** (the marker contains `0`), so our script remains the
  owner. If that flag is ever turned on, the script's rules must be revisited so the
  two do not both install a filter.

---

## 5. Config files and network interfaces

- `/etc/default/otbr-agent`
  - `OTBR_AGENT_OPTS`: `-I wpan0 -B wlan0 -d 5 --rest-listen-address 0.0.0.0
    --rest-listen-port 8081 spinel+hdlc+uart:///dev/ttyAML6?uart-baudrate=115200 trel://wlan0`
  - `OTBR_THREAD_IF=wpan0`, `OTBR_BACKBONE_IF=wlan0`, `OTBR_FIREWALL=1`, `OTBR_NAT64=1`
  - **About the interfaces**: `-I wpan0` is the Thread-side virtual interface;
    `-B <backbone>` is the **uplink/LAN interface** (the Backbone Router uses it to
    join Thread to the existing IPv6 LAN, for multicast forwarding and TREL). This
    device only has wifi, so backbone = **wlan0**. When changing interfaces, keep
    `-I`/`-B`/`trel://` in `OTBR_AGENT_OPTS` consistent with
    `OTBR_THREAD_IF`/`OTBR_BACKBONE_IF`.
- `/etc/default/otbr-web`: `OTBR_WEB_OPTS="-I wpan0 -p 8080 -a 0.0.0.0"` -- the Web
  GUI is on port **8080** (avoiding 80); the REST API is on **8081** (served by
  otbr-agent).
- Boot-time system configuration is written by `DEBIAN/postinst`: `sysctl` (IPv6
  forwarding, `wlan0` accept_ra, `optmem_max`), appending `88 openthread` to
  `/etc/iproute2/rt_tables`, and `modprobe` of
  `ip6table_filter`/`ip6_tables`/`xt_set`.

---

## 6. Install / upgrade / uninstall behaviour

- **preinst**: stop the hubv3 master switch first (which stops the agent -> teardown,
  and web), then stop web/agent individually as a fallback; clean up leftovers from
  the old mDNSResponder setup (`mdnsd`, `libdns_sd`, `libnss_mdns`, old init.d, ...).
- **postinst (configure)**: write sysctl/rt_tables/modprobe -> `disable` any
  standalone autostart of `otbr-agent`/`otbr-web` left over from older versions ->
  `enable` only the hubv3 master -> start hubv3; then poll
  `http://localhost:8081/node` and, once ready, call `otbr_database` to write the
  Thread information into the HA config (stopping HA first and restarting it
  afterwards if HA is running).
  - `otbr_database` creates the active dataset when there is none
    (`dataset init new` -> `dataset commit active` -> `ifconfig up` ->
    `thread start`). If it fails, postinst prints a `[WARN]` instead of swallowing
    the error: without it Thread stays `disabled` with no dataset.
  - **Backup/restore flow**: if `/mnt/R3Backup` is found to have `.enable-restore`
    and `setting_*.tar.gz` exists, auto-configuration is skipped
    (`SKIP_AUTO_CONFIG=true`) and left to the restore flow.
- **prerm (remove/purge)**: stop the master and services, fall back to
  `otbr-firewall.sh teardown`, remove the drop-ins, remove the `rt_tables`/`sysctl`
  entries, and delete `/var/lib/thread`.
- **Upgrade path**: on a dpkg upgrade, `prerm upgrade` does not match remove/purge, so
  **`/var/lib/thread` (the Thread network credentials) is preserved across
  upgrades**; firewall cleanup happens because preinst stops the services, which
  triggers `ExecStopPost`, so it is naturally clean and needs no separate upgrade
  handling in prerm.

---

## 7. Notes and known pitfalls (please read)

1. **`Requires=dbus.socket` is cleared by a drop-in**: the unit template generated
   upstream hardcodes a hard dependency on dbus, but we build with `-DOTBR_DBUS=OFF`.
   `otbr-agent.service.d/firewall.conf` resets it with an empty `Requires=` so that
   devices without dbus can still start. (bootstrap does install dbus, but that is
   build-host behaviour only.)
2. **Upgrade leftovers**: the old postinst used to `enable otbr-agent/otbr-web`. The
   new model enables only the master, so postinst `disable`s those two first to clear
   the stale `WantedBy` symlinks; otherwise they would start at boot bypassing the
   master switch.
3. **`otbr_database` must not hardcode HA's interpreter**: its shebang is
   `#!/usr/bin/env python3`. It used to be `#!/srv/homeassistant/bin/python3`, which
   meant that on a machine where hacore was not installed the interpreter did not
   exist, the script failed with "cannot execute: required file not found", the
   dataset was never created, and Thread came up `disabled` on first boot. The script
   uses the standard library only and runs under both the system python3 (3.11) and
   HA's (3.14).
4. **The firewall can only really be verified on hardware**:
   `otbr-firewall.sh setup` genuinely writes ip6tables/ipset/NAT64 and needs `wpan0`
   to exist. On a machine with no Thread chip only `teardown` can be verified (a safe
   no-op). Once on the device, the suggested checks are:
   - `systemctl enable --now hubv3-otbr-agent` -> `ip6tables -L OTBR_FORWARD_INGRESS`
     has rules and `ipset list -n` shows `otbr-ingress-*`;
   - `restart otbr-agent` repeatedly and confirm the rules **do not accumulate**;
   - `systemctl disable --now hubv3-otbr-agent` -> the chains and ipsets are cleared
     and both agent and web stop.
5. **Submodules**: `build.sh` uses `git submodule update --init` (not `--recursive`),
   which compiles fine for the current version; if upstream later splits out a
   submodule that needs recursion, switch to `--recursive` when the build reports
   missing files.
6. **Serial port**: `spinel+hdlc+uart:///dev/ttyAML6@115200` is this hardware's RCP
   serial port and must change with the hardware.
7. **Latent issue (known, not addressed yet)**: `build.sh` takes its working
   directory from `current_dir=$(pwd)`, so `output/`, `staging/` and `ot-br-posix/`
   all follow **the caller's current directory** rather than the script's location.
   You must therefore `cd` into this package's directory before running
   `./build.sh`; running `bash /path/to/build.sh` from elsewhere clones the source
   into whatever the working directory was and creates staging there too. The
   `thirdreality-matter2mqtt/build.sh` in the same repo already avoids this with
   `$(cd "$(dirname "$(readlink -f "$0")")" && pwd)`; this package should be brought
   in line.

---

## 8. File list

| Path | Description |
|------|-------------|
| `build.sh` | Build/packaging script (clone -> bootstrap -> cmake -> `DESTDIR=staging/ ninja install` -> collect -> dpkg-deb) |
| `staging/` | Landing directory for `ninja install` (gitignored). Packaged content is collected only from here |
| `openthread-core-ha-config-posix.h` | OpenThread compile-time config header (downloaded automatically on first build) |
| `DEBIAN/{preinst,postinst,prerm,control}` | Maintainer scripts and package metadata |
| `prebuild/otbr-firewall.sh` | Firewall/NAT64 build and teardown script (setup/teardown) |
| `prebuild/otbr-agent` | `/etc/default/otbr-agent`: agent options + firewall toggles + interfaces |
| `prebuild/otbr-web` | `/etc/default/otbr-web`: web GUI options |
| `prebuild/hubv3-otbr-agent.{service,sh}` | The master-switch oneshot (GPIO init + starting the agent) |
| `prebuild/otbr-agent-init.sh` | GPIO initialisation script (spare) |
| `prebuild/otbr_database` | Tool that writes the Thread information into the HA config |
