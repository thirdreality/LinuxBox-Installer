#!/bin/bash

current_dir=$(pwd)
output_dir="${current_dir}/output"

# OOM 保护 + 构建期临时停无关服务（pnpm 构建 herdsman/z2m 内存吃紧）。
# 不含 mosquitto：本脚本自身负责启停 mosquitto。
source "$(dirname "$(readlink -f "$0")")/../build_common.sh"
TR_SWAPFILE="${current_dir}/.build-swap"
TR_MEM_SERVICES=(home-assistant.service matter-server.service music-assistant.service \
                 otbr-agent.service otbr-web.service)

REBUILD=false
CLEAN=false
DISTCLEAN=false


SCRIPT="R3"
print_info() { echo -e "\e[1;34m[${SCRIPT}] INFO:\e[0m $1"; }
print_error() { echo -e "\e[1;31m[${SCRIPT}] ERROR:\e[0m $1"; }

print_info "Usage: Build.sh [--rebuild] [--clean]"
print_info "Options:"
print_info "  --rebuild: Rebuild the env"
print_info "  --clean: Clean the output directory and remove the env"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --rebuild) REBUILD=true ;;
        --clean) CLEAN=true ;;
        *) print_error "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

version=$(grep '^Version:' ${current_dir}/DEBIAN/control | awk '{print $2}')
print_info "Version: $version"

# Full clean because Node.js may conflict with other packages
if [[ "$CLEAN" == true ]]; then
    print_info "zigbee-mqtt_${version}.deb cleaning ..."
    rm -rf /opt/zigbee2mqtt > /dev/null 2>&1
    rm -rf /opt/zigbee-herdsman > /dev/null 2>&1

    systemctl stop mosquitto.service || true
    systemctl disable mosquitto.service || true

    systemctl stop zigbee2mqtt.service || true
    systemctl disable zigbee2mqtt.service || true

    rm -rf /etc/systemd/system/zigbee2mqtt.service > /dev/null 2>&1

    rm -rf "${output_dir}" > /dev/null 2>&1
    rm -rf ${current_dir}/*.deb > /dev/null 2>&1

    rm -rf /etc/mosquitto/passwd > /dev/null 2>&1

    # Clean Node.js and mosquitto related packages
    print_info "Cleaning mosquitto, nodejs ..."
    apt-get remove --purge nodejs npm libsystemd-dev -y 2>/dev/null || true
    apt-get remove --purge mosquitto mosquitto-clients libdlt2 libmosquitto1 -y 2>/dev/null || true
    apt-get autoremove -y
    apt-get clean

    # Manually clean residual files
    print_info "Cleaning data files ..."
    rm -rf /usr/bin/node
    rm -rf /usr/bin/npm  
    rm -rf /usr/bin/npx
    rm -rf /usr/lib/node_modules
    rm -rf /usr/include/node
    rm -rf /usr/share/nodejs
    rm -rf /etc/nodejs

    rm -rf /etc/mosquitto

    # Clean man pages
    rm -rf /usr/share/man/man1/node*
    rm -rf /usr/share/man/man1/npm*

    # Clean user directories
    rm -rf ~/.npm
    rm -rf ~/.pnpm-store
    rm -rf ~/.pnpm-global
    rm -rf ~/.cache/npm
    rm -rf ~/.cache/pnpm
    rm -rf ~/.config/pnpm

    # Update package database
    apt update

    print_info "zigbee-mqtt_${version}.deb cleaning finished ..."
    exit 0
fi

# Partial clean
if [[ "$REBUILD" == true ]]; then
    print_info "zigbee-mqtt_${version}.deb rebuilding ..."
    rm -rf "${output_dir}" > /dev/null 2>&1
    rm -rf ${current_dir}/*.deb > /dev/null 2>&1
    rm -rf /opt/zigbee2mqtt > /dev/null 2>&1
    rm -rf /opt/zigbee-herdsman > /dev/null 2>&1
    rm -rf /etc/systemd/system/zigbee2mqtt.service > /dev/null 2>&1
fi

mkdir -p "${output_dir}"
cp ${current_dir}/DEBIAN ${output_dir}/ -R

# Install software

# Check: if mosquitto or mosquitto-clients is not installed, install them
if ! dpkg -l | grep -q "mosquitto " || ! dpkg -l | grep -q "mosquitto-clients"; then
    print_info "Installing mosquitto and mosquitto-clients..."
    apt update
    apt-get install -y --download-only mosquitto mosquitto-clients libdlt2 libmosquitto1 
    apt install -y mosquitto mosquitto-clients
    systemctl disable mosquitto.service
    systemctl stop mosquitto.service
    #mosquitto -v

    mkdir -p ${current_dir}/prebuild/deb/mosquitto
    cp /var/cache/apt/archives/mosquitto*.deb ${current_dir}/prebuild/deb/mosquitto/ 2>/dev/null || true
    cp /var/cache/apt/archives/libmosquitto*.deb ${current_dir}/prebuild/deb/mosquitto/ 2>/dev/null || true
    cp /var/cache/apt/archives/libdlt2*.deb ${current_dir}/prebuild/deb/mosquitto/ 2>/dev/null || true
    cp /var/cache/apt/archives/mosquitto-clients*.deb ${current_dir}/prebuild/deb/mosquitto/ 2>/dev/null || true    
fi

# post install

if [ -f "/usr/bin/mosquitto_passwd" ]; then 
    print_info "Config mosquitto and mosquitto-clients..."
	mkdir -p /etc/mosquitto
	rm -rf /etc/mosquitto/passwd
	mosquitto_passwd -b -c /etc/mosquitto/passwd thirdreality thirdreality
fi

mkdir -p /etc/mosquitto
cp ${current_dir}/prebuild/mosquitto.conf /etc/mosquitto/mosquitto.conf

systemctl start mosquitto.service

if ! dpkg -l | grep -q "nodejs "; then
    print_info "Installing nodejs (pinned to v24.x)..."
    # Pin to Node.js v24.x major line (NodeSource) instead of tracking latest LTS,
    # to avoid unwanted major-version drift. z2m 2.11.0 supports ^20.15 || ^22.2 || ^24.
    curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
    apt-get install -y --download-only nodejs libsystemd-dev
    apt-get install -y nodejs libsystemd-dev   

    mkdir -p ${current_dir}/prebuild/deb/nodejs
    cp /var/cache/apt/archives/nodejs*.deb ${current_dir}/prebuild/deb/nodejs/ 2>/dev/null || true
    cp /var/cache/apt/archives/libsystemd-dev*.deb ${current_dir}/prebuild/deb/nodejs/ 2>/dev/null || true    
    
fi

if ! command -v pnpm >/dev/null 2>&1; then
    print_info "Installing pnpm@10.18.3 (via China npm mirror)..."
    #npm install -g pnpm
    # Use a China-accessible registry; the default registry.npmjs.org times out here.
    npm install -g pnpm@10.18.3 --registry=https://mirrors.tencent.com/npm/
fi

print_info "node version should output V24.x, current: \e[1;31m $(node --version)\e[0m "

print_info "npm version should output 10.X, current: \e[1;31m $(npm --version)\e[0m "
#npm --version # Should output 9.X or 10.X

print_info "pnpm version should output 10.X, current: \e[1;31m $(pnpm --version)\e[0m "


# node-gyp 默认从 nodejs.org 下载 Node 头文件，国内会 ETIMEDOUT，导致原生模块
# (如 zigbee2mqtt 的可选依赖 unix-dgram) 编译失败；失败回滚还会污染 node-gyp 缓存
# (留下缺 common.gypi 的半成品目录)。这里改用国内可达镜像下载头文件，并在缓存残缺时
# 清理，保证原生模块能干净编译。
export npm_config_disturl="https://mirrors.tencent.com/nodejs-release"
print_info "node-gyp disturl: ${npm_config_disturl}"
NODE_FULL_VER="$(node --version 2>/dev/null | sed 's/^v//')"
if [ -n "${NODE_FULL_VER}" ] && [ ! -f "${HOME}/.cache/node-gyp/${NODE_FULL_VER}/common.gypi" ]; then
    print_info "Cleaning incomplete node-gyp cache for ${NODE_FULL_VER} ..."
    rm -rf "${HOME}/.cache/node-gyp/${NODE_FULL_VER}"
fi


# --------------------- 自动清理deb目录旧包，只保留每个包类型的最新版 ---------------------
print_info "Cleaning old debs in prebuild/deb/ (top-level), only keeping the latest version for each software..."
cd ${current_dir}/prebuild/deb 2>/dev/null || exit 0
for pkg in $(ls *.deb 2>/dev/null | sed 's/_.*//;' | sort -u); do
    newest=$(ls ${pkg}_*.deb 2>/dev/null | sort -V | tail -n1)
    for f in ${pkg}_*.deb; do
        if [ "$f" != "$newest" ]; then
            print_info "Deleting old deb: $f"
            rm -f "$f"
        fi
    done
    print_info "Keeping: $newest"
done
cd - >/dev/null

for subdir in ${current_dir}/prebuild/deb/*/; do
    [ -d "$subdir" ] || continue
    print_info "Cleaning old debs in $subdir, only keeping the latest version for each software..."
    cd "$subdir" || continue
    for pkg in $(ls *.deb 2>/dev/null | sed 's/_.*//;' | sort -u); do
        newest=$(ls ${pkg}_*.deb 2>/dev/null | sort -V | tail -n1)
        for f in ${pkg}_*.deb; do
            if [ "$f" != "$newest" ]; then
                print_info "Deleting old deb: $f"
                rm -f "$f"
            fi
        done
        print_info "Keeping: $newest"
    done
    cd - >/dev/null
    done
# ----------------------------------------------------------------------

# Create package
print_info "Create output directory ..."
mkdir -p "${output_dir}"

print_info "syncing DEBIAN ..."
rm -rf ${output_dir}/DEBIAN > /dev/null 2>&1
cp ${current_dir}/DEBIAN ${output_dir}/ -R

# 进入重构建/重打包前：停无关服务 + 按需加 swap（结束自动清理/恢复）。
# 无论 pnpm 全量构建，还是 /opt 已存在时的纯重打包，dpkg-deb 的 xz 压缩在这台
# 2GiB 机器上都可能 OOM，故无条件调用（内存充足时内部自动跳过加 swap）。
tr_build_guard_start

if [ ! -d "/opt/zigbee2mqtt" ]; then
    cp ${current_dir}/prebuild/zigbee2mqtt.service /etc/systemd/system/zigbee2mqtt.service

    print_info "Build zigbee-herdsman ..."
    mkdir -p /opt/zigbee-herdsman
    git clone -b 3r_blz_10.0.8 https://github.com/thirdreality/zigbee-herdsman.git /opt/zigbee-herdsman

    cd /opt/zigbee-herdsman
    dirty_id=$(/usr/bin/git describe --dirty --always)
    print_info "zigbee-herdsman dirty-id '$dirty_id'"
    echo "zigbee-herdsman-dirty-id: $dirty_id" >> ${output_dir}/DEBIAN/control
    commit_id=$(git log -1 --format=%H)
    print_info "zigbee-herdsman commit-id '$commit_id'"
    echo "zigbee-herdsman-commit: $commit_id" >> ${output_dir}/DEBIAN/control

    # Keep .git and .github in /opt, will remove after copying to output_dir
    #pnpm i --frozen-lockfile
    pnpm install --no-frozen-lockfile --registry=https://mirrors.tencent.com/npm/ && pnpm run build
    #pnpm install && pnpm run build

    print_info "Build zigbee2mqtt ..."
    mkdir -p /opt/zigbee2mqtt
    #git clone --depth 1 https://github.com/Koenkk/zigbee2mqtt.git /opt/zigbee2mqtt
    git clone -b 3r_blz_2.11.0 https://github.com/thirdreality/zigbee2mqtt.git /opt/zigbee2mqtt

    cd /opt/zigbee2mqtt
    dirty_id=$(/usr/bin/git describe --dirty --always)
    print_info "zigbee2mqtt dirty-id '$dirty_id'"
    echo "zigbee2mqtt-dirty-id: $dirty_id" >> ${output_dir}/DEBIAN/control
    commit_id=$(git log -1 --format=%H)
    print_info "zigbee2mqtt commit-id '$commit_id'"
    echo "zigbee2mqtt-commit: $commit_id" >> ${output_dir}/DEBIAN/control

    # Keep .git and .github in /opt, will remove after copying to output_dir
    #pnpm install --frozen-lockfile && pnpm run build
    pnpm install --no-frozen-lockfile --registry=https://mirrors.tencent.com/npm/ && pnpm run build
    #npm ci
    #pnpm i --frozen-lockfile

    
    cp ${current_dir}/prebuild/configuration_zigate.yaml /opt/zigbee2mqtt/data/configuration_zigate.yaml
    cp ${current_dir}/prebuild/configuration_blz.yaml /opt/zigbee2mqtt/data/configuration_blz.yaml

    mkdir -p /opt/zigbee2mqtt/data/external_converters
    if [ -d "${current_dir}/prebuild/converters" ]; then
        print_info "Copy converters to /opt/zigbee2mqtt/data/external_converters ..."
        cp ${current_dir}/prebuild/converters/*.js /opt/zigbee2mqtt/data/external_converters/ || true
    fi
else
    cd /opt/zigbee-herdsman
    dirty_id=$(/usr/bin/git describe --dirty --always)
    print_info "zigbee-herdsman dirty-id '$dirty_id'"
    echo "zigbee-herdsman-dirty-id: $dirty_id" >> ${output_dir}/DEBIAN/control
    commit_id=$(git log -1 --format=%H)
    print_info "zigbee-herdsman commit-id '$commit_id'"
    echo "zigbee-herdsman-commit: $commit_id" >> ${output_dir}/DEBIAN/control

    cd /opt/zigbee2mqtt
    dirty_id=$(/usr/bin/git describe --dirty --always)
    print_info "zigbee2mqtt dirty-id '$dirty_id'"
    echo "zigbee2mqtt-dirty-id: $dirty_id" >> ${output_dir}/DEBIAN/control
    commit_id=$(git log -1 --format=%H)
    print_info "zigbee2mqtt commit-id '$commit_id'"
    echo "zigbee2mqtt-commit: $commit_id" >> ${output_dir}/DEBIAN/control        
fi

systemctl daemon-reload

if [ -f "${current_dir}/prebuild/zigee2mqtt_blz_reset.sh" ]; then
    mkdir -p /opt/zigbee2mqtt/scripts/
    cp ${current_dir}/prebuild/zigee2mqtt_blz_reset.sh /opt/zigbee2mqtt/scripts/zigbee2mqtt_blz_reset.sh
    chmod +x /opt/zigbee2mqtt/scripts/zigbee2mqtt_blz_reset.sh
fi

# Install permit-on-passlist script (startup is handled by systemd ExecStartPost)
if [ -f "${current_dir}/prebuild/z2m-permit-on-passlist.sh" ]; then
    mkdir -p /opt/zigbee2mqtt/scripts/
    cp ${current_dir}/prebuild/z2m-permit-on-passlist.sh /opt/zigbee2mqtt/scripts/z2m-permit-on-passlist.sh
    chmod +x /opt/zigbee2mqtt/scripts/z2m-permit-on-passlist.sh
fi

mkdir -p ${output_dir}/lib/thirdreality/archives_zigbee2mqtt
mkdir -p ${output_dir}/lib/thirdreality/conf

print_info "Backup mosquitto debs ..."
cp ${current_dir}/prebuild/deb/mosquitto/*.deb ${output_dir}/lib/thirdreality/archives_zigbee2mqtt/ 2>/dev/null || true

print_info "Backup nodejs debs ..."
cp ${current_dir}/prebuild/deb/nodejs/*.deb ${output_dir}/lib/thirdreality/archives_zigbee2mqtt/ 2>/dev/null || true

cp ${current_dir}/prebuild/post-fix-zigbee2mqtt.sh ${output_dir}/lib/thirdreality/

print_info "Backup zigbee2mqtt ..."

mkdir -p ${output_dir}/opt/zigbee2mqtt
cp /opt/zigbee2mqtt ${output_dir}/opt/ -R

mkdir -p ${output_dir}/opt/zigbee-herdsman
cp /opt/zigbee-herdsman ${output_dir}/opt/ -R

# Remove .git and .github from output_dir after copying
print_info "Removing .git and .github from output_dir ..."
rm -rf ${output_dir}/opt/zigbee2mqtt/.git ${output_dir}/opt/zigbee2mqtt/.github || true
rm -rf ${output_dir}/opt/zigbee-herdsman/.git ${output_dir}/opt/zigbee-herdsman/.github || true

rm -rf ${output_dir}/opt/zigbee2mqtt/data/database.db || true
rm -rf ${output_dir}/opt/zigbee2mqtt/data/database.db.backup || true
rm -rf ${output_dir}/opt/zigbee2mqtt/data/log || true
rm -rf ${output_dir}/opt/zigbee2mqtt/data/state.json || true
rm -rf ${output_dir}/opt/zigbee2mqtt/data/configuration.yaml || true
rm -rf ${output_dir}/opt/zigbee2mqtt/data/configuration_blz.yaml || true
rm -rf ${output_dir}/opt/zigbee2mqtt/data/configuration_zigate.yaml || true

mkdir -p ${output_dir}/usr/lib/node_modules
#cp /lib/node_modules/corepack ${output_dir}/lib/node_modules/ -R
#cp /lib/node_modules/npm ${output_dir}/lib/node_modules/ -R
cp /usr/lib/node_modules/pnpm ${output_dir}/usr/lib/node_modules/ -R

mkdir -p ${output_dir}/etc/systemd/system/
cp /etc/systemd/system/zigbee2mqtt.service ${output_dir}/etc/systemd/system/zigbee2mqtt.service

#
print_info "backup default config files..."
cp ${current_dir}/prebuild/configuration_zigate.yaml ${output_dir}/lib/thirdreality/conf/configuration_zigate.yaml.default
cp ${current_dir}/prebuild/configuration_blz.yaml ${output_dir}/lib/thirdreality/conf/configuration_blz.yaml.default
#cp ${current_dir}/configuration_standalone.yaml ${output_dir}/lib/thirdreality/conf/configuration_standalone.yaml.default

cp ${current_dir}/prebuild/mosquitto.conf ${output_dir}/lib/thirdreality/conf/mosquitto.conf.default

# ---------------------
print_info "Start to build zigbee-mqtt_${version}.deb ..."
dpkg-deb --build ${output_dir} ${current_dir}/zigbee-mqtt_${version}.deb

#rm -rf ${output_dir} > /dev/null 2>&1

print_info "Build zigbee-mqtt_${version}.deb finished ..."
