# LinuxBox 周期性升级工作手册（steering）

> 本仓库（LinuxBox-Installer / hubv3 网关）会**周期性升级各个软件包**
> （hacore=Home Assistant + matter.js server、music-assistant、zigbee-mqtt、
> python3、otbr-agent、bridge、board-firmware 等）。
> 目标：升级尽量**一键化、少人工介入**。本手册固化标准流程与历史踩坑，
> Kiro 在处理升级类任务时应默认遵循。

## 运行环境约束（务必牢记）

- 目标/构建机内存很小（**~2GiB**）。任何重构建/打包**不要并发**。
- `dpkg-deb` 的 xz 压缩很吃内存（hacore≈233M / z2m≈121M / MA venv≈1.8G），
  在 2GiB 机器上**极易 OOM 死机**。
- 重任务（`build.sh`、大 deb 打包）一律**后台跑**（`control_bash_process`），
  日志写 `/tmp/*.log`，用户可能离开；打包耗时约 10~20 分钟。

## 标准升级流程（每个包）

1. 改版本号（见下"版本号位置"），必要时同步依赖 pin。
2. 后台跑 `./build.sh`（venv/产物已存在时走"纯重打包"路径，复用已构建内容）。
3. 构建结束后**验证 deb 内容**（见"验证清单"）。
4. `deb` 不进 git（已 gitignore）；源码改动用 **inline git author** 提交，
   **不要改 git config**：
   `git -c user.name="liuguoping1024" -c user.email="guoping.liu@thirdreality.com" commit ...`
5. push 只在用户**明确要求**时执行，push 到 **dev** 分支。
6. deb 产物由用户拷贝到 U 盘 `/mnt/R3Install/`（安装器 `hubv3-usb-sync` 按固定文件名查找）。

## 历史踩坑与现有防护（升级时必须保证不回退）

1. **原地 pip 升级会覆盖打过补丁的文件 → 补丁静默丢失。**
   典型：HA 升级重装 `zha`，冲掉 `zha.patch` 注册的 `blz`（Bouffalo）电台
   → 启动报 `RadioType KeyError: 'blz'`。
   防护：`thirdreality-hacore/build.sh` 用 `tr_apply_patch_idempotent`
   **每次构建都幂等校验并按需重打**三个补丁（zha.patch / zigpy_cli.patch /
   zigpy_cli_asyncio.patch），而非仅首次建 venv 时打。**升级后务必确认补丁仍在。**

2. **Python 大版本切换时，各包 preinst 的版本校验要一起改。**
   例：迁到 3.14 后 MA 的 preinst 仍写死找 `python3.13` → 安装被 dpkg 中止。
   规则：改 `thirdreality-python3` 版本时，同步检查所有包 `DEBIAN/preinst` 的
   `check_python()`（hacore、music-assistant 等），统一到新版本。

3. **安装期不要无谓停 mosquitto（通用 MQTT broker）。**
   - `mosquitto` 已安装则不重装，也就不需要停（`dpkg-query ... install ok installed` 判据）。
     已在 z2m 的 `DEBIAN/preinst`、`DEBIAN/postinst`、`post-fix-zigbee2mqtt.sh` 三处加守卫。
   - **ZHA 模式**：`hacore` 的 `home_assistant_zha_enable.py` 只 disable
     `zigbee2mqtt`，**不要动 mosquitto**（其它 MQTT 集成/设备可能在用；z2m post-fix
     也会保持它运行）。两边行为必须一致，避免"一个杀、一个救"的安装期抖动。

4. **OOM 防护对"纯重打包"路径同样必要。**
   `build.sh` 应**无条件**调用 `tr_build_guard_start`（源自 `deb_repo/build_common.sh`：
   停无关服务 + 内存不足时自动加临时 swap + 退出自动清理/恢复），
   不能只在"全量构建"分支调用。hacore 与 zigbee-mqtt 的 build.sh 均已如此。
   内存充足时该函数会自动跳过加 swap。

## 版本号位置（改版本时逐一核对）

- `thirdreality-hacore`：`build.sh`（`HOME_ASSISTANT_VERSION`、`FRONTEND_VERSION`、
  `MATTER_SERVER_NPM_VERSION`、`MATTER_PYTHON_CLIENT_VERSION` 等）+ `prebuild/DEBIAN/control` 的 `Version`。
- `thirdreality-music-assistant`：`build.sh` + `prebuild/DEBIAN/control`。
- `thirdreality-zigbee-mqtt`：`build.sh`（herdsman/z2m 分支）+ `DEBIAN/control`。
- `thirdreality-python3`：对应 build.sh + control；改动后联动检查各包 preinst 的 Python 校验。

## 验证清单（重打后必查）

- deb 版本：`dpkg-deb -f <deb> Package Version`。
- 只改了控制脚本（preinst/postinst 等）时，可用"外科手术式"改 deb（只换
  `control.tar.xz` 成员，不重压 `data.tar.xz`），秒级完成、避免大 deb 重压：
  `ar x`→改 control 内容→`tar -cJf`→`ar r <deb> control.tar.xz`；改完校验
  `data` 文件数不变。
- hacore 专项：deb 内 `zha/application/const.py` 含 `zigpy_blz`（blz 补丁在）；
  `home_assistant_zha_enable.py` **不含** `stop_and_disable_service('mosquitto`；
  `matter-server.service` 保留 `--ble-proxy`；matter-server npm=目标版本、
  `@matter/main` 含目标提交。
- z2m 专项：`preinst`/`postinst`/`post-fix-zigbee2mqtt.sh` 含
  `install ok installed` 守卫（mosquitto 已装不停）。
- MA 专项：`preinst` 的 `check_python()` 指向当前 Python 版本。

## 敏感数据 / 日志

- 提交/公开前，matter-server 日志需脱敏：用 `tools/sanitize_matter_log.py`
  （WiFi 明文密码、IPK、BLE MAC、BSSID、内网 IP 等）。原始 `*.raw.log`、
  `core_matter_server_*.log` 已 gitignore，**不要提交**。
