#!/bin/bash

current_dir=$(pwd)
output_dir="${current_dir}/output"

REBUILD=false
CLEAN=false


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
        *) print_error "未知参数: $1" >&2; exit 1 ;;
    esac
    shift
done

version=$(grep '^Version:' ${current_dir}/DEBIAN/control | awk '{print $2}')
print_info "Version: $version"


#清场
if [[ "$CLEAN" == true ]]; then
    rm -rf /opt/zigbee2mqtt > /dev/null 2>&1
    rm -rf /opt/zigbee-herdsman > /dev/null 2>&1

    rm -rf /etc/systemd/system/zigbee2mqtt.service > /dev/null 2>&1

    rm -rf "${output_dir}" > /dev/null 2>&1
    rm -rf ${current_dir}/*.deb > /dev/null 2>&1

    exit 0
fi

#半清场
if [[ "$REBUILD" == true ]]; then
    print_info "zigbee-mqtt_${version}.deb rebuilding ..."
    rm -rf "${output_dir}" > /dev/null 2>&1

fi

mkdir -p "${output_dir}"
cp ${current_dir}/DEBIAN ${output_dir}/ -R

# 安装软件

# 检查：如果mosquitto-clients, 以及mosquitto没有安装， 则进行如下操作
if ! dpkg -l | grep -q "mosquitto " || ! dpkg -l | grep -q "mosquitto-clients"; then
    print_info "Installing mosquitto and mosquitto-clients..."
    apt update
    apt install -y mosquitto mosquitto-clients
    systemctl enable mosquitto.service
    systemctl disable mosquitto.service
    mosquitto -v
fi

# post install

if [ -f "/usr/bin/mosquitto_passwd" ]; then 
	rm -rf /etc/mosquitto/passwd
	mosquitto_passwd -b -c /etc/mosquitto/passwd thirdreality thirdreality
fi

cp ${current_dir}/mosquitto.conf /etc/mosquitto/mosquitto.conf

systemctl start mosquitto.service

if ! dpkg -l | grep -q "nodejs "; then
    print_info "Installing nodejs..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    apt install -y nodejs libsystemd-dev   
fi

if [ ! -d "/lib/node_modules/pnpm" ]; then
    npm install -g pnpm
fi

print_info "node version should output V18.x, V20.x, V21.X, current: \e[1;31m $(node --version)\e[0m "
#node --version # Should output V18.x, V20.x, V21.X

print_info "npm version should output 9.X or 10.X, current: \e[1;31m $(npm --version)\e[0m "
#npm --version # Should output 9.X or 10.X

if [ ! -d "/opt/zigbee2mqtt" ]; then
    cp ${current_dir}/zigbee2mqtt.service /etc/systemd/system/zigbee2mqtt.service

    print_info "Build zigbee-herdsman ..."
    mkdir -p /opt/zigbee-herdsman
    git clone -b feat/blz https://github.com/fangzheli/zigbee-herdsman.git /opt/zigbee-herdsman
    cd /opt/zigbee-herdsman
    rm -rf /opt/zigbee-herdsman/.git /opt/zigbee-herdsman/.github
    #pnpm i --frozen-lockfile
    pnpm install && pnpm run build

    print_info "Build zigbee2mqtt ..."
    mkdir -p /opt/zigbee2mqtt
    #git clone --depth 1 https://github.com/Koenkk/zigbee2mqtt.git /opt/zigbee2mqtt
    #git clone -b feat/blz-local-dev https://github.com/fangzheli/zigbee2mqtt.git /opt/zigbee2mqtt
    git clone -b feat/blz-local-dev https://github.com/thirdreality/zigbee2mqtt.git /opt/zigbee2mqtt
    cd /opt/zigbee2mqtt
    rm -rf /opt/zigbee2mqtt/.git /opt/zigbee2mqtt/.github
    pnpm install && pnpm run build
    #npm ci
    #pnpm i --frozen-lockfile

    cp ${current_dir}/configuration_zigate.yaml /opt/zigbee2mqtt/data/configuration_zigate.yaml
    cp ${current_dir}/configuration_blz.yaml /opt/zigbee2mqtt/data/configuration_blz.yaml
    #npm run build
fi

systemctl daemon-reload

# 创建软件
print_info "Create output directory ..."
mkdir -p "${output_dir}"

print_info "syncing DEBIAN ..."
rm -rf ${output_dir}/DEBIAN > /dev/null 2>&1
cp ${current_dir}/DEBIAN ${output_dir}/ -R

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

cp ${current_dir}/mosquitto.conf ${output_dir}/lib/thirdreality/conf/mosquitto.conf.default

# ---------------------
print_info "Start to build zigbee-mqtt_${version}.deb ..."
dpkg-deb --build ${output_dir} ${current_dir}/zigbee-mqtt_${version}.deb

#rm -rf ${output_dir} > /dev/null 2>&1

print_info "Build zigbee-mqtt_${version}.deb finished ..."
