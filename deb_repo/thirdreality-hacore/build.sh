#!/bin/bash

current_dir=$(pwd)
output_dir="${current_dir}/output"
home_assistant_path="/srv/homeassistant"
matter_server_path="/srv/matter_server"
python3_dir="/usr/local/python3" # install target directory

# OOM 保护 + 装包期临时停无关服务（HA 安装大量 wheel，内存吃紧）
source "$(dirname "$(readlink -f "$0")")/../build_common.sh"
TR_SWAPFILE="${current_dir}/.build-swap"

UV_INSTALLED=false

REBUILD=false
CLEAN=false

SCRIPT="R3"
print_info() { echo -e "\e[1;34m[${SCRIPT}] INFO:\e[0m $1"; }
print_error() { echo -e "\e[1;31m[${SCRIPT}] ERROR:\e[0m $1"; }

print_info "Build script for ThirdReality Home Assistant Core"
print_info "Usage: Build.sh [--rebuild] [--clean]"
print_info "Options:"
print_info "  --rebuild: Rebuild the env"
print_info "  --clean: Clean the output directory and remove the env"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --rebuild) REBUILD=true ;;
        --clean) CLEAN=true ;;
        *) print_info "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

# 全局定义版本号
export HOME_ASSISTANT_VERSION="2026.7.3"

#home-assistant-frontend==20250509.0
export FRONTEND_VERSION="20260624.6" 

# HA 2026.7 起，matter 集成的客户端库从 python-matter-server 改名拆分为
# matter-python-client + matter-ble-proxy（见 core matter/manifest.json）。
export MATTER_PYTHON_CLIENT_VERSION="0.7.1"
export MATTER_BLE_PROXY_VERSION="0.7.1"

# 服务端已从 python-matter-server[server] 迁移到 Node.js 的 matter.js server
# (npm 包名 matter-server)。系统（armbian/buildroot）自带 Node.js 24.x。
export MATTER_SERVER_NPM_VERSION="1.2.8"
# 允许离线/局域网环境覆盖 npm 源（例如内网 registry 或 npmmirror 镜像）。
# 只有外网不通、但内网有镜像时设置它即可；已安装则完全不联网。
NPM_REGISTRY_URL="${NPM_REGISTRY_URL:-}"

# Python version requirement
REQUIRED_PYTHON_MAJOR="3.14"

version=$(grep '^Version:' ${current_dir}/prebuild/DEBIAN/control | awk '{print $2}')
print_info "Version: $version"

if [[ "$CLEAN" == true ]]; then
    rm -rf "${output_dir}" > /dev/null 2>&1
    #rm -rf ${current_dir}/*.deb > /dev/null 2>&1

    systemctl stop home-assistant.service || true
    systemctl disable home-assistant.service || true

    systemctl stop matter-server.service || true
    systemctl disable matter-server.service || true

    rm -rf /lib/systemd/system/home-assistant.service
    rm -rf /lib/systemd/system/matter-server.service

    rm -rf /usr/local/bin/chip-ota-provider-app
    rm -rf /usr/local/bin/zigpy_help.sh

    rm -rf /var/lib/homeassistant/homeassistant/*.* || true
    rm -rf /var/lib/homeassistant/matter_server/*.* || true

    print_info "Removing ${home_assistant_path} ..."
    rm -rf ${home_assistant_path}

    print_info "Removing ${matter_server_path} ..."
    rm -rf ${matter_server_path}

    systemctl daemon-reload

    print_info "hacore_${version}.deb clear finished ..."
    exit 0
fi

if [[ "$REBUILD" == true ]]; then
    rm -rf "${output_dir}" > /dev/null 2>&1
    mkdir -p "${output_dir}"
fi

mkdir -p "${output_dir}"

cp ${current_dir}/prebuild/DEBIAN ${output_dir}/ -R

# matter.js server 自带 OTA Provider 功能，不再需要外部 chip-ota-provider-app。
# matter server 入口（Node.js / matter.js）
matter_server_entry="${matter_server_path}/node_modules/matter-server/dist/esm/MatterServer.js"

CURRENT_PYTHON=$(python3 --version | sed -E 's/Python\s+//')
if [ -f "${python3_dir}/bin/python3" ]; then
    CURRENT_PYTHON=$("${python3_dir}/bin/python3" --version | sed -E 's/Python\s+//')
else  
    print_error "Python ${REQUIRED_PYTHON_MAJOR}+ is needed, abort ..."
    exit 1  
fi

if tr_ver_lt "$CURRENT_PYTHON" "${REQUIRED_PYTHON_MAJOR}.0"; then
    print_info "Python ${REQUIRED_PYTHON_MAJOR}+ is needed (current: $CURRENT_PYTHON), abort ..."
    exit 1
fi

UV_INSTALLED_COMMAND="python3 -m pip install"
if command -v uv >/dev/null 2>&1; then
    UV_INSTALLED=true
    echo "uv is installed, version: $(uv --version)"
    UV_INSTALLED_COMMAND="uv pip install"
else
    UV_INSTALLED=false
    echo "uv is not installed or not in PATH"
fi

# 检查是否设置了 Home Assistant 和其他版本号
if [ -z "$HOME_ASSISTANT_VERSION" ] || [ -z "$FRONTEND_VERSION" ] || [ -z "$MATTER_SERVER_NPM_VERSION" ]; then
    print_error "One or more version variables are not set. Please set HOME_ASSISTANT_VERSION, FRONTEND_VERSION, and MATTER_SERVER_NPM_VERSION."
    exit 1
fi

if [ ! -e "${home_assistant_path}/bin/hass" ] || [ ! -e "${matter_server_entry}" ]; then
    # 进入实际装包前：停无关服务 + 按需加 swap（结束自动清理/恢复）
    tr_build_guard_start
fi

if [ ! -e "${home_assistant_path}/bin/hass" ]; then
    print_info "[1]Building python homeassistant venv for hacore_${version}.deb ..."
    mkdir -p ${home_assistant_path}

    print_info "Using python[home_assistant]: ${python3_dir}/bin/python3"
    cd ${home_assistant_path}
    ${python3_dir}/bin/python3 -m venv .
    source ${home_assistant_path}/bin/activate

    if [ $UV_INSTALLED == false ]; then
        pip3 config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple/
        pip3 config set install.trusted-host pypi.tuna.tsinghua.edu.cn
    else
        export UV_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple/
    fi

    ${UV_INSTALLED_COMMAND} --upgrade pip wheel

    ${UV_INSTALLED_COMMAND} homeassistant=="$HOME_ASSISTANT_VERSION" 
    ${UV_INSTALLED_COMMAND} home-assistant-frontend=="$FRONTEND_VERSION"

    # Check it https://github.com/home-assistant/core/blob/master/script/hassfest/docker/Dockerfile
    ${UV_INSTALLED_COMMAND} \
        stdlib-list==0.10.0 \
        pipdeptree==2.26.1 \
        tqdm==4.67.1 \
        ruff==0.12.1 \
        PyTurboJPEG==1.8.3 \
        go2rtc-client==0.4.0 \
        ha-ffmpeg==3.2.2 \
        hassil==3.8.0 \
        home-assistant-intents==2026.6.24 \
        mutagen==1.47.0 \
        pymicro-vad==1.0.1 \
        pyspeex-noise==1.0.2

    ${UV_INSTALLED_COMMAND} music-assistant-client==1.3.6

    #以下是一个强制换行符号
    ${UV_INSTALLED_COMMAND} universal-silabs-flasher==1.1.0 ha-silabs-firmware-client==0.3.0 psutil-home-assistant==0.0.1
    
    # homeassistant.components.matter
    # HA 2026.7 起 matter 集成客户端库改名拆分（服务端改用 Node.js matter.js server）。
    ${UV_INSTALLED_COMMAND} matter-python-client==0.7.1 matter-ble-proxy==0.7.1

    # homeassistant.components.thread
    ${UV_INSTALLED_COMMAND} python-otbr-api==2.10.0 pyroute2==0.9.6

    # homeassistant.components.zha
    # 注意：zha 2.0.0 依赖 zigpy 2.0.0，而 zigpy 2.0.0 要求 serialx>=1.4.0（旧的 0.6.2 会冲突）。
    # zha-quirks 是 zha 运行期必需（旧流程靠首启预热补装），这里显式固定以便一次装全。
    ${UV_INSTALLED_COMMAND} zha==2.0.0 zha-quirks==2.1.1 serialx==1.8.2

    # zigpy-cli 默认会拉入 zigpy-zboss，而 zigpy-zboss (2.0.3) 约束 zigpy<2，与 HA 2026.7
    # 的 zha 2.0.0（需 zigpy 2.0）冲突，会导致 zha 装不上。我们不支持 zboss 无线，
    # 因此用 --no-deps 安装 zigpy-cli（其余 radio 后端 bellows/deconz/xbee/zigate/znp 由 zha 带入），
    # 再补上 zigpy-cli 运行所需的 click/coloredlogs/scapy。
    ${UV_INSTALLED_COMMAND} --no-deps zigpy-cli
    ${UV_INSTALLED_COMMAND} click coloredlogs scapy

    #以下是从首次启动日志中获取的，关键字：[homeassistant.util.package]
    ${UV_INSTALLED_COMMAND} ha-ffmpeg==3.2.2
    ${UV_INSTALLED_COMMAND} aiousbwatcher==1.1.2
    ${UV_INSTALLED_COMMAND} async-upnp-client==0.46.2
    ${UV_INSTALLED_COMMAND} aiodhcpwatcher==1.2.7
    ${UV_INSTALLED_COMMAND} aiodiscover==3.3.2
    ${UV_INSTALLED_COMMAND} hassil==3.8.0
    ${UV_INSTALLED_COMMAND} home-assistant-intents==2026.6.24
    ${UV_INSTALLED_COMMAND} mutagen==1.47.0
    ${UV_INSTALLED_COMMAND} bleak==3.0.2
    ${UV_INSTALLED_COMMAND} bluetooth-adapters==2.4.0
    ${UV_INSTALLED_COMMAND} bluetooth-auto-recovery==1.6.4
    ${UV_INSTALLED_COMMAND} pymicro-vad==1.0.1
    ${UV_INSTALLED_COMMAND} pyspeex-noise==1.0.2
    ${UV_INSTALLED_COMMAND} PyTurboJPEG==1.8.3
    ${UV_INSTALLED_COMMAND} radios==0.3.2
    ${UV_INSTALLED_COMMAND} universal-silabs-flasher==1.1.0
    ${UV_INSTALLED_COMMAND} ha-silabs-firmware-client==0.3.0
    ${UV_INSTALLED_COMMAND} gTTS==2.5.4
    ${UV_INSTALLED_COMMAND} av==17.0.1
    ${UV_INSTALLED_COMMAND} go2rtc-client==0.4.0
    ${UV_INSTALLED_COMMAND} PyNaCl==1.6.2
    ${UV_INSTALLED_COMMAND} aioesphomeapi==45.3.1
    ${UV_INSTALLED_COMMAND} esphome-dashboard-api==1.3.0
    ${UV_INSTALLED_COMMAND} bleak-esphome==3.9.7
    ${UV_INSTALLED_COMMAND} paho-mqtt==2.1.0
    ${UV_INSTALLED_COMMAND} aioruuvigateway==0.1.0
    ${UV_INSTALLED_COMMAND} aioshelly==13.26.2
    ${UV_INSTALLED_COMMAND} ibeacon-ble==1.2.0
    ${UV_INSTALLED_COMMAND} kegtron-ble==1.0.2
    ${UV_INSTALLED_COMMAND} xiaomi-ble==1.11.0    
    ${UV_INSTALLED_COMMAND} numpy==2.3.2
    ${UV_INSTALLED_COMMAND} pyotp==2.9.0
    ${UV_INSTALLED_COMMAND} PyQRCode==1.2.1
    ${UV_INSTALLED_COMMAND} pyatv==0.18.0
    ${UV_INSTALLED_COMMAND} PySwitchbot==2.2.0
    ${UV_INSTALLED_COMMAND} cached-ipaddress==1.1.2
    ${UV_INSTALLED_COMMAND} bluetooth-data-tools==1.29.18
    ${UV_INSTALLED_COMMAND} dbus-fast==5.0.22
    ${UV_INSTALLED_COMMAND} habluetooth==6.26.5
    ${UV_INSTALLED_COMMAND} file-read-backwards==2.0.0

    #cd ${home_assistant_path}/lib64/python3.14/site-packages; python3 -m pip install git+https://github.com/bouffalolab/zigpy-blz/@dev
    cd ${home_assistant_path}/lib64/python3.14/site-packages; ${UV_INSTALLED_COMMAND} git+https://github.com/thirdreality/zigpy-blz/@main

    
    # Apply patches
    print_info "Applying patches..."
    
    # Apply zha.patch
    if [ -f "${current_dir}/prebuild/zha.patch" ]; then
        print_info "Applying zha.patch to const.py..."
        if [ -f "${home_assistant_path}/lib64/python3.14/site-packages/zha/application/const.py" ]; then
            if patch ${home_assistant_path}/lib64/python3.14/site-packages/zha/application/const.py < "${current_dir}/prebuild/zha.patch"; then
                print_info "zha.patch applied successfully"
            else
                print_error "Failed to apply zha.patch, continuing without patch"
            fi
        else
            print_error "Target file const.py not found, skipping zha.patch"
        fi
    else
        print_info "zha.patch not found in ${current_dir}/prebuild, skipping"
    fi
    
    # Apply zigpy_cli.patch
    if [ -f "${current_dir}/prebuild/zigpy_cli.patch" ]; then
        print_info "Applying zigpy_cli.patch to zigpy_cli..."
        if [ -f "${home_assistant_path}/lib64/python3.14/site-packages/zigpy_cli/const.py" ]; then
            if patch ${home_assistant_path}/lib64/python3.14/site-packages/zigpy_cli/const.py < "${current_dir}/prebuild/zigpy_cli.patch"; then
                print_info "zigpy_cli.patch applied successfully"
            else
                print_error "Failed to apply zigpy_cli.patch, continuing without patch"
            fi
        else
            print_error "Target directory zigpy_cli not found, skipping zigpy_cli.patch"
        fi
    else
        print_info "zigpy_cli.patch not found in ${current_dir}/prebuild, skipping"
    fi

    # Apply zigpy_cli_asyncio.patch
    # Python 3.14 移除了 asyncio.get_event_loop() 在无运行 loop 时自动创建的旧行为，
    # 会直接抛 RuntimeError，导致 zigpy-cli 的 `zigpy radio ... info` 等命令全部崩溃
    # （zigpy_help.sh / home_assistant_init.sh 均依赖它）。此补丁改为无 loop 时新建。
    if [ -f "${current_dir}/prebuild/zigpy_cli_asyncio.patch" ]; then
        print_info "Applying zigpy_cli_asyncio.patch to zigpy_cli/cli.py..."
        if [ -f "${home_assistant_path}/lib64/python3.14/site-packages/zigpy_cli/cli.py" ]; then
            if patch ${home_assistant_path}/lib64/python3.14/site-packages/zigpy_cli/cli.py < "${current_dir}/prebuild/zigpy_cli_asyncio.patch"; then
                print_info "zigpy_cli_asyncio.patch applied successfully"
            else
                print_error "Failed to apply zigpy_cli_asyncio.patch, continuing without patch"
            fi
        else
            print_error "Target file zigpy_cli/cli.py not found, skipping zigpy_cli_asyncio.patch"
        fi
    else
        print_info "zigpy_cli_asyncio.patch not found in ${current_dir}/prebuild, skipping"
    fi

    deactivate
fi

# matter.js server (Node.js) —— 官方 Matter Server add-on 使用的服务端实现，
# 与 python-matter-server 的 WebSocket 协议兼容（drop-in 替代）。npm 包名: matter-server。
# 系统（armbian / buildroot）自带 Node.js 24.x，这里不打包 Node，仅安装 matter-server。
# https://github.com/matter-js/matterjs-server
if [ ! -e "${matter_server_entry}" ]; then
    print_info "[2]Installing matter.js server (matter-server@${MATTER_SERVER_NPM_VERSION}) for hacore_${version}.deb ..."

    # 校验 Node.js（matter-server 要求 >= 22.13）
    if ! command -v node >/dev/null 2>&1; then
        print_error "Node.js not found. matter.js server requires Node.js >= 22.13 (armbian/buildroot ships 24.x)."
        exit 1
    fi
    NODE_VERSION=$(node --version | sed -E 's/^v//')
    if tr_ver_lt "$NODE_VERSION" "22.13.0"; then
        print_error "Node.js ${NODE_VERSION} is too old; matter-server requires >= 22.13. abort ..."
        exit 1
    fi
    print_info "Using Node.js: $(node --version) / npm $(npm --version 2>/dev/null || echo '?')"

    mkdir -p ${matter_server_path}
    cd ${matter_server_path}

    # native 模块编译依赖（BLE: noble / libudev）。best-effort：无网或已安装时不影响
    # （已装为 no-op；缺失且无网则依赖构建机预置环境）。
    if command -v apt-get >/dev/null 2>&1; then
        apt-get install -y --no-install-recommends make gcc g++ libbluetooth-dev libudev-dev python3 >/dev/null 2>&1 || \
            print_info "Warning: failed to install some native build deps (may already be present / offline)"
    fi

    # 局域网/离线场景：可用 NPM_REGISTRY_URL 指定内网 registry 或镜像；
    # 若 ${matter_server_entry} 已存在则整段跳过，完全不联网。
    NPM_ARGS=(--omit=dev --foreground-scripts --no-audit --no-fund)
    if [ -n "$NPM_REGISTRY_URL" ]; then
        print_info "Using npm registry: ${NPM_REGISTRY_URL}"
        NPM_ARGS+=(--registry "$NPM_REGISTRY_URL")
    fi

    npm install "${NPM_ARGS[@]}" matter-server@"${MATTER_SERVER_NPM_VERSION}" || {
        print_error "Failed to install matter-server@${MATTER_SERVER_NPM_VERSION} from npm"
        exit 1
    }

    if [ ! -e "${matter_server_entry}" ]; then
        print_error "matter-server installed but entry not found: ${matter_server_entry}"
        exit 1
    fi

    # 瘦身：清理 npm 缓存与冗余 cjs 产物（参考官方 add-on）
    npm cache clean --force >/dev/null 2>&1 || true
    find "${matter_server_path}/node_modules" -type d -name "cjs" -path "*/@matter/*" -exec rm -rf {} + 2>/dev/null || true
    find "${matter_server_path}/node_modules" -type d -name "cjs" -path "*/@project-chip/*" -exec rm -rf {} + 2>/dev/null || true
fi


print_info "Install help scripts and service ..."

mkdir -p /var/lib/homeassistant
mkdir -p /var/lib/homeassistant/homeassistant
mkdir -p /var/lib/homeassistant/matter_server

if [ ! -f "/usr/local/bin/zigpy_help.sh" ]; then
    cp ${current_dir}/prebuild/zigpy_help.sh /usr/local/bin/zigpy_help.sh
    chmod +x /usr/local/bin/zigpy_help.sh
fi

if [ -d "${home_assistant_path}/bin" ]; then

    find /srv/homeassistant -name "*.pyc" -delete
    find /srv/homeassistant -name "__pycache__" -type d -exec rm -rf {} +

    cp ${current_dir}/prebuild/home_assistant_init.sh ${home_assistant_path}/bin/home_assistant_init.sh
    chmod +x ${home_assistant_path}/bin/home_assistant_init.sh

    cp ${current_dir}/prebuild/home_assistant_zigbee_fix.sh ${home_assistant_path}/bin/home_assistant_zigbee_fix.sh
    chmod +x ${home_assistant_path}/bin/home_assistant_zigbee_fix.sh

    cp ${current_dir}/prebuild/home_assistant_blz_reset.sh ${home_assistant_path}/bin/home_assistant_blz_reset.sh
    chmod +x ${home_assistant_path}/bin/home_assistant_blz_reset.sh

    cp ${current_dir}/prebuild/home_assistant_boot_check.sh ${home_assistant_path}/bin/home_assistant_boot_check.sh
    cp ${current_dir}/prebuild/home_assistant_boot_check.py ${home_assistant_path}/bin/home_assistant_boot_check.py
    chmod +x ${home_assistant_path}/bin/home_assistant_boot_check.sh
    chmod +x ${home_assistant_path}/bin/home_assistant_boot_check.py

    cp ${current_dir}/prebuild/home_assistant_zha_enable.py ${home_assistant_path}/bin/home_assistant_zha_enable.py
    chmod +x ${home_assistant_path}/bin/home_assistant_zha_enable.py

    cp ${current_dir}/prebuild/config_v2026.yaml ${home_assistant_path}/config.yaml
    # z2m 脚本已弃用，不再复制
fi

if [ ! -f "/usr/lib/systemd/system/home-assistant.service" ]; then
    cp ${current_dir}/prebuild/home-assistant.service /usr/lib/systemd/system/home-assistant.service
    systemctl daemon-reload
fi

if [ ! -f "/usr/lib/systemd/system/matter-server.service" ]; then
    cp ${current_dir}/prebuild/matter-server.service /usr/lib/systemd/system/matter-server.service
    systemctl daemon-reload
fi

print_info "Backup files for hacore_${version}.deb ..."
rm -rf ${output_dir}/srv
rm -rf ${output_dir}/usr
rm -rf ${output_dir}/lib

mkdir -p ${output_dir}/usr/local/bin/
chmod 755 ${output_dir}/usr/local

if [ -f "/usr/local/bin/zigpy_help.sh" ]; then
    cp /usr/local/bin/zigpy_help.sh ${output_dir}/usr/local/bin/
fi

mkdir -p ${output_dir}/srv
chmod 755 ${output_dir}/srv
cp /srv/homeassistant ${output_dir}/srv/ -R
cp /srv/matter_server ${output_dir}/srv/ -R

mkdir -p ${output_dir}/lib/systemd/system/
cp /lib/systemd/system/home-assistant.service ${output_dir}/lib/systemd/system/
cp /lib/systemd/system/matter-server.service ${output_dir}/lib/systemd/system/

# 清理输出目录中的Python缓存文件与目录，避免打包冗余内容
find "${output_dir}" -type d -name "__pycache__" -exec rm -rf {} +
find "${output_dir}" -type f -name "*.pyc" -delete

print_info "Start to build hacore_${version}.deb ..."
dpkg-deb --build ${output_dir} ${current_dir}/hacore_${version}.deb

# rm -rf ${output_dir}/srv > /dev/null 2>&1
# rm -rf ${output_dir}/usr > /dev/null 2>&1
# rm -rf ${output_dir}/lib > /dev/null 2>&1
#rm -rf ${output_dir} > /dev/null 2>&1

print_info "Build hacore_${version}.deb finished ..."

