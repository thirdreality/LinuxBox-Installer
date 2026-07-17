# thirdreality-hacore

为 ThirdReality LinuxBox Dev Edition 构建的 Home Assistant Core + Matter Server
`.deb` 包（arm64）。包含两部分：

- `build.sh` —— 编译打包脚本（HA venv、matter-server venv、辅助脚本与 systemd 服务）。
- `sync_all_versions.py` —— 依赖版本同步工具，自动把 build.sh / `prebuild/DEBIAN/control`
  里的版本号更新到某个 HA Core 版本对应的依赖版本。

---

## 一、构建 `.deb`

依赖前置包 `thirdreality-python3`（提供 `/usr/local/python3`，需 Python ≥ 3.13）。

```bash
./build.sh            # 构建（已存在的 venv 不会重装，直接重新打包）
./build.sh --rebuild  # 删除 venv/output 后从零重建
./build.sh --clean    # 卸载服务、删除 venv、清理产物
```

构建过程会在内存不足时自动创建临时 swap，并临时停止无关重内存服务，结束后自动恢复
（见仓库根 `deb_repo/build_common.sh`）。

### 两阶段打包（重要）

HA 首次启动时会通过 `homeassistant.util.package` 按已加载的集成**动态 pip 安装**一批
依赖到 venv。因此得到"相对完整"的包需要两步（目前为**人工**操作）：

1. 第一次 `./build.sh` —— 装好基础 venv 并打出**初版** deb。
2. 手动启动并让它运行一会，等首启依赖装完，再停掉：
   ```bash
   systemctl start home-assistant.service     # 或直接 /srv/homeassistant/bin/hass --config <dir>
   # 等待若干分钟，直到日志中不再出现 [homeassistant.util.package] 安装动作
   systemctl stop home-assistant.service matter-server.service
   ```
3. 再次 `./build.sh` —— 因 `bin/hass` 已存在，脚本跳过装包，直接把**预热后的 venv**
   重新打包，得到依赖更完整的 deb。

> build.sh 里那一大段"从首次启动日志中获取的"写死包列表，就是历史上手工做完上述预热后，
> 把 HA 首启会下载的包固化进脚本的结果，用于减少每次预热需要补装的量。

---

## 二、版本同步工具 `sync_all_versions.py`

把 build.sh 中的版本号同步到指定 HA Core 版本对应的依赖版本，数据来源：

| 来源 | 用途 |
|------|------|
| `home-assistant/core` GitHub release | HA Core 版本（`--version` 未指定时取 latest） |
| core 仓库 `requirements_all.txt`（对应 tag） | frontend、zha、python-matter-server、各集成依赖 |
| core 仓库 `requirements.txt`（对应 tag） | 预留（当前目标包列表为空） |
| core 仓库 `script/hassfest/docker/Dockerfile` | hassfest 工具链包段（见下方限制） |
| `home-assistant-libs/python-matter-server` GitHub release | matter-server 版本（见下方**注意**） |
| matter-server 的 `Dockerfile` | chip-ota-provider 版本 → `chip_example_url` |

会被更新的目标：`export HOME_ASSISTANT_VERSION` / `MATTER_SERVER_VERSION` /
`FRONTEND_VERSION`、`chip_example_url`、build.sh 中形如 `pkg==x.y.z` 的行，以及
`prebuild/DEBIAN/control` 的 `Version:`。

### 用法

需要 `requests`。系统 Python 可能没有，用 HA venv 的 Python 最稳：

```bash
# 预览（不改文件），强烈建议先跑
/srv/homeassistant/bin/python3 sync_all_versions.py --version 2026.2.3 --dry-run

# 实际写入（会先备份 build.sh 到 build.sh.backup.<时间戳>）
/srv/homeassistant/bin/python3 sync_all_versions.py --version 2026.2.3

# 同步到最新 HA 版本
/srv/homeassistant/bin/python3 sync_all_versions.py

# 指定其它文件
/srv/homeassistant/bin/python3 sync_all_versions.py --file build.sh --version 2026.2.3
```

改完后务必 `git diff build.sh` 复核，并跑一次 `--rebuild` 验证。

### ⚠️ 已知限制 / 注意事项

1. **matter-server 取的是 GitHub “latest”，未与 HA 目标版本绑定。**
   `MATTER_SERVER_VERSION`（独立服务端）来自 matter-server 最新 release，而 HA venv 里的
   `python-matter-server==`（客户端）来自 `requirements_all.txt`，两者可能不一致。
   **注意：Python 版 python-matter-server 已停止演进，`8.1.2` 基本是最后一个受支持的版本。**
   因此 `MATTER_SERVER_VERSION` 应固定保持在 `8.1.2`，同步后请确认它**没有**被意外改动；
   不要让它去追新的 release。

2. **`--restore` 跨进程不可用。** 备份文件名的时间戳在启动时生成，单独再跑 `--restore`
   时时间戳已变、找不到旧备份。需要回滚请直接 `git checkout build.sh` 或手动指定备份文件。

3. **hassfest / Dockerfile 包段不会被写入。** 替换逻辑匹配的是 `python3 -m pip install`
   代码块，而 build.sh 用的是 `${UV_INSTALLED_COMMAND}`，匹配不上；且提取只取了第一个
   `uv pip install` 块。dry-run 里报告的 Dockerfile 包（如 ruff）**仅供参考，不会实际修改**，
   这些包（stdlib-list、ruff 等）需手工维护。

4. **`pkg==` 匹配无词边界。** 短包名（如 `av`）可能误匹配 `libav==` 之类子串，替换前请用
   `--dry-run` + `git diff` 复核。

5. 大小写敏感：包名按 `requirements_all.txt` 中的原始大小写匹配（如 `PyTurboJPEG`、
   `PyNaCl`）。上游改名或改大小写会导致个别包同步不到。

### 命令行参数

| 参数 | 说明 |
|------|------|
| `--version X` | 目标 HA Core 版本，缺省取 GitHub 最新 |
| `--dry-run` | 只预览、不改文件 |
| `--file PATH` | 目标脚本路径，默认 `build.sh` |
| `--restore` | 从备份恢复（见限制 2） |
