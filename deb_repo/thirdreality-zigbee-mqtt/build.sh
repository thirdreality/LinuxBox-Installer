#!/bin/bash

current_dir=$(pwd)
output_dir="${current_dir}/output"

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
    apt-get install --download-only mosquitto mosquitto-clients libdlt2 libmosquitto1 
    apt install -y mosquitto mosquitto-clients
    systemctl disable mosquitto.service
    systemctl stop mosquitto.service
    #mosquitto -v

    mkdir -p ${current_dir}/deb/mosquitto
    cp /var/cache/apt/archives/mosquitto*.deb ${current_dir}/deb/mosquitto/ 2>/dev/null || true
    cp /var/cache/apt/archives/libmosquitto*.deb ${current_dir}/deb/mosquitto/ 2>/dev/null || true
    cp /var/cache/apt/archives/libdlt2*.deb ${current_dir}/deb/mosquitto/ 2>/dev/null || true
    cp /var/cache/apt/archives/mosquitto-clients*.deb ${current_dir}/deb/mosquitto/ 2>/dev/null || true    
fi

# post install

if [ -f "/usr/bin/mosquitto_passwd" ]; then 
    print_info "Config mosquitto and mosquitto-clients..."
	mkdir -p /etc/mosquitto
	rm -rf /etc/mosquitto/passwd
	mosquitto_passwd -b -c /etc/mosquitto/passwd thirdreality thirdreality
fi

mkdir -p /etc/mosquitto
cp ${current_dir}/mosquitto.conf /etc/mosquitto/mosquitto.conf

systemctl start mosquitto.service

if ! dpkg -l | grep -q "nodejs "; then
    print_info "Installing nodejs..."
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    apt-get install --download-only nodejs libsystemd-dev
    apt-get install -y nodejs libsystemd-dev   

    mkdir -p ${current_dir}/deb/nodejs
    cp /var/cache/apt/archives/nodejs*.deb ${current_dir}/deb/nodejs/ 2>/dev/null || true
    cp /var/cache/apt/archives/libsystemd-dev*.deb ${current_dir}/deb/nodejs/ 2>/dev/null || true    
fi

if [ ! -d "/lib/node_modules/pnpm" ]; then
    print_info "Installing pnpm..."
    #npm install -g pnpm
    npm install -g pnpm@10.12.1
fi

print_info "node version should output V22.x, V24.x, current: \e[1;31m $(node --version)\e[0m "

print_info "npm version should output 10.X, current: \e[1;31m $(npm --version)\e[0m "
#npm --version # Should output 9.X or 10.X

print_info "pnpm version should output 10.X, current: \e[1;31m $(pnpm --version)\e[0m "


# --------------------- 自动清理deb目录旧包，只保留每个包类型的最新版 ---------------------
print_info "清理 deb 目录旧包，只保留每个软件的最新deb ..."
for pkg in $(ls ./deb/*.deb 2>/dev/null | sed 's#.*/##;s/_.*//;' | sort -u); do
    newest=$(ls ./deb/${pkg}_*.deb 2>/dev/null | sort -V | tail -n1)
    for f in ./deb/${pkg}_*.deb; do
        if [ "$f" != "$newest" ]; then
            print_info "删除旧包: $f"
            rm -f "$f"
        fi
    done
    print_info "本次保留: $newest"
done
# ----------------------------------------------------------------------

# Create package
print_info "Create output directory ..."
mkdir -p "${output_dir}"

print_info "syncing DEBIAN ..."
rm -rf ${output_dir}/DEBIAN > /dev/null 2>&1
cp ${current_dir}/DEBIAN ${output_dir}/ -R

if [ ! -d "/opt/zigbee2mqtt" ]; then
    cp ${current_dir}/zigbee2mqtt.service /etc/systemd/system/zigbee2mqtt.service

    print_info "Build zigbee-herdsman ..."
    mkdir -p /opt/zigbee-herdsman
    git clone -b feat/blz https://github.com/fangzheli/zigbee-herdsman.git /opt/zigbee-herdsman

    cd /opt/zigbee-herdsman
    dirty_id=$(/usr/bin/git describe --dirty --always)
    print_info "zigbee-herdsman dirty-id '$dirty_id'"
    echo "zigbee-herdsman-dirty-id: $dirty_id" >> ${output_dir}/DEBIAN/control
    commit_id=$(git log -1 --format=%H)
    print_info "zigbee-herdsman commit-id '$commit_id'"
    echo "zigbee-herdsman-commit: $commit_id" >> ${output_dir}/DEBIAN/control

    rm -rf /opt/zigbee-herdsman/.git /opt/zigbee-herdsman/.github
    #pnpm i --frozen-lockfile
    pnpm install --no-frozen-lockfile --registry=https://mirrors.tencent.com/npm/ && pnpm run build
    #pnpm install && pnpm run build

    print_info "Build zigbee2mqtt ..."
    mkdir -p /opt/zigbee2mqtt
    #git clone --depth 1 https://github.com/Koenkk/zigbee2mqtt.git /opt/zigbee2mqtt
    git clone -b feat/blz-local-dev https://github.com/fangzheli/zigbee2mqtt.git /opt/zigbee2mqtt
    #git clone -b feat/blz-local-dev https://github.com/thirdreality/zigbee2mqtt.git /opt/zigbee2mqtt

    cd /opt/zigbee2mqtt
    dirty_id=$(/usr/bin/git describe --dirty --always)
    print_info "zigbee2mqtt dirty-id '$dirty_id'"
    echo "zigbee2mqtt-dirty-id: $dirty_id" >> ${output_dir}/DEBIAN/control
    commit_id=$(git log -1 --format=%H)
    print_info "zigbee2mqtt commit-id '$commit_id'"
    echo "zigbee2mqtt-commit: $commit_id" >> ${output_dir}/DEBIAN/control

    rm -rf /opt/zigbee2mqtt/.git /opt/zigbee2mqtt/.github
    #pnpm install --frozen-lockfile && pnpm run build
    pnpm install --no-frozen-lockfile --registry=https://mirrors.tencent.com/npm/ && pnpm run build
    #npm ci
    #pnpm i --frozen-lockfile

    cp ${current_dir}/configuration_zigate.yaml /opt/zigbee2mqtt/data/configuration_zigate.yaml
    cp ${current_dir}/configuration_blz.yaml /opt/zigbee2mqtt/data/configuration_blz.yaml
    #npm run build
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

if [ -f "${current_dir}/zigee2mqtt_blz_reset.sh" ]; then
    mkdir -p /opt/zigbee2mqtt/scripts/
    cp ${current_dir}/zigee2mqtt_blz_reset.sh /opt/zigbee2mqtt/scripts/zigbee2mqtt_blz_reset.sh
    chmod +x /opt/zigbee2mqtt/scripts/zigbee2mqtt_blz_reset.sh
fi

mkdir -p ${output_dir}/lib/thirdreality/archives_zigbee2mqtt
mkdir -p ${output_dir}/lib/thirdreality/conf

print_info "Backup mosquitto debs ..."
cp ${current_dir}/deb/mosquitto/*.deb ${output_dir}/lib/thirdreality/archives_zigbee2mqtt/

print_info "Backup nodejs debs ..."
cp ${current_dir}/deb/nodejs/*.deb ${output_dir}/lib/thirdreality/archives_zigbee2mqtt/

cp ${current_dir}/post-fix-zigbee2mqtt.sh ${output_dir}/lib/thirdreality/

print_info "Backup zigbee2mqtt ..."

mkdir -p ${output_dir}/opt/zigbee2mqtt
cp /opt/zigbee2mqtt ${output_dir}/opt/ -R

mkdir -p ${output_dir}/opt/zigbee-herdsman
cp /opt/zigbee-herdsman ${output_dir}/opt/ -R

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
cp ${current_dir}/configuration_zigate.yaml ${output_dir}/lib/thirdreality/conf/configuration_zigate.yaml.default
cp ${current_dir}/configuration_blz.yaml ${output_dir}/lib/thirdreality/conf/configuration_blz.yaml.default
#cp ${current_dir}/configuration_standalone.yaml ${output_dir}/lib/thirdreality/conf/configuration_standalone.yaml.default

cp ${current_dir}/mosquitto.conf ${output_dir}/lib/thirdreality/conf/mosquitto.conf.default

# ---------------------
print_info "Start to build zigbee-mqtt_${version}.deb ..."
dpkg-deb --build ${output_dir} ${current_dir}/zigbee-mqtt_${version}.deb

#rm -rf ${output_dir} > /dev/null 2>&1

print_info "Build zigbee-mqtt_${version}.deb finished ..."
