#!/bin/bash

current_dir=$(pwd)
output_dir="${current_dir}/output"
home_assistant_path="/srv/homeassistant"
matter_server_path="/srv/matter_server"
python3_dir="/usr/local/python3" # install target directory

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
        *) print_info "未知参数: $1" >&2; exit 1 ;;
    esac
    shift
done

# 全局定义版本号
export HOME_ASSISTANT_VERSION="2025.8.3"

#home-assistant-frontend==20250509.0
export FRONTEND_VERSION="20250811.1" 

#python-matter-server==8.0.0
export MATTER_SERVER_VERSION="8.1.0"

CURRENT_PLATFORM=aarch64

version=$(grep '^Version:' ${current_dir}/DEBIAN/control | awk '{print $2}')
print_info "Version: $version"

if [[ "$CLEAN" == true ]]; then
    rm -rf "${output_dir}" > /dev/null 2>&1
    rm -rf ${current_dir}/*.deb > /dev/null 2>&1

    systemctl stop home-assistant.service || true
    systemctl disable home-assistant.service || true

    systemctl stop matter-server.service || true
    systemctl disable matter-server.service || true

    rm -rf /lib/systemd/system/home-assistant.service
    rm -rf /lib/systemd/system/matter-server.service

    rm -rf /usr/local/bin/chip-ota-provider-app
    rm -rf /usr/local/bin/zigpy_help.sh

    rm -rf /var/lib/homeassistant/*.* || true

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

cp ${current_dir}/DEBIAN ${output_dir}/ -R

chip_example_url="https://github.com/home-assistant-libs/matter-linux-ota-provider/releases/download/2025.5.0"

download_file() {
    local url=$1
    local output=$2
    if [[ ! -f "$output" ]]; then
        curl -Lo "$output" "$url" || { print_error "Failed to download $url"; exit 1; }
        chmod +x "$output"
    fi
}

install_ota_provider() {
    local binary_file=""
    case "${CURRENT_PLATFORM}" in
        x86_64) binary_file="chip-ota-provider-app-x86-64" ;;
        aarch64) binary_file="chip-ota-provider-app-aarch64" ;;
        *) print_error "Unsupported platform type: ${CURRENT_PLATFORM}"; exit 1 ;;
    esac

    print_info "Downloading chip-ota-provider-app ..."
    download_file "${chip_example_url}/${binary_file}" "/usr/local/bin/chip-ota-provider-app"
}

CURRENT_PYTHON=$(python3 --version | sed -E 's/Python\s+//')
if [ -f "${python3_dir}/bin/python3" ]; then
    CURRENT_PYTHON=$("${python3_dir}/bin/python3" --version | sed -E 's/Python\s+//')
else  
    print_error "Python 3.13+ is needed, abort ..."
    exit 1  
fi

if [[ "$CURRENT_PYTHON" < "3.13.0" ]]; then
    print_info "Python 3.13+ is needed, abort ..."
    exit 1
fi

if command -v uv >/dev/null 2>&1; then
    UV_INSTALLED=true
    echo "uv 已安装，版本: $(uv --version)"
else
    UV_INSTALLED=false
    echo "uv 未安装或不在 PATH 中"
fi

# 检查是否设置了 Home Assistant 和其他版本号
if [ -z "$HOME_ASSISTANT_VERSION" ] || [ -z "$FRONTEND_VERSION" ] || [ -z "$MATTER_SERVER_VERSION" ]; then
    print_error "One or more version variables are not set. Please set HOME_ASSISTANT_VERSION, FRONTEND_VERSION, and MATTER_SERVER_VERSION."
    exit 1
fi

if [ ! -f "/usr/local/bin/chip-ota-provider-app" ]; then
    install_ota_provider
    if [ -f "/usr/local/bin/chip-ota-provider-app" ]; then
        strip /usr/local/bin/chip-ota-provider-app
    fi
fi

if [ ! -e "${home_assistant_path}/bin/hass" ]; then
    print_info "[1]Building python homeassistant venv for hacore_${version}.deb ..."
    mkdir -p ${home_assistant_path}

    print_info "Using python[home_assistant]: ${python3_dir}/bin/python3"
    cd ${home_assistant_path}
    ${python3_dir}/bin/python3 -m venv .
    source ${home_assistant_path}/bin/activate

    pip3 config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple/
    pip3 config set install.trusted-host pypi.tuna.tsinghua.edu.cn

    python3 -m pip install --upgrade pip wheel
    python3 -m pip install homeassistant=="$HOME_ASSISTANT_VERSION" 
    python3 -m pip install home-assistant-frontend=="$FRONTEND_VERSION"

    # Check it https://github.com/home-assistant/core/blob/master/script/hassfest/docker/Dockerfile
    python3 -m pip install \
        stdlib-list==0.10.0 \
        pipdeptree==2.26.1 \
        tqdm==4.67.1 \
        ruff==0.12.1 \
        PyTurboJPEG==1.8.0 \
        go2rtc-client==0.2.1 \
        ha-ffmpeg==3.2.2 \
        hassil==2.2.3 \
        home-assistant-intents==2025.7.30 \
        mutagen==1.47.0 \
        pymicro-vad==1.0.1 \
        pyspeex-noise==1.0.2
    # homeassistant.components.homeassistant_hardware
    # homeassistant.components.hardware
    python3 -m pip install universal-silabs-flasher==0.0.31 ha-silabs-firmware-client==0.2.0 psutil-home-assistant==0.0.1
    
    # homeassistant.components.matter
    python3 -m pip install python-matter-server==8.0.0

    # homeassistant.components.thread
    python3 -m pip install python-otbr-api==2.7.0 pyroute2==0.7.5

    # homeassistant.components.zha
    python3 -m pip install zha==0.0.68

    python3 -m pip install zigpy-cli

    #cd ${home_assistant_path}/lib64/python3.13/site-packages; python3 -m pip install git+https://github.com/bouffalolab/zigpy-blz/@dev
    cd ${home_assistant_path}/lib64/python3.13/site-packages; python3 -m pip install git+https://github.com/thirdreality/zigpy-blz/@main

    
    # Apply patches
    print_info "Applying patches..."
    
    # Apply zha.patch
    if [ -f "${current_dir}/zha.patch" ]; then
        print_info "Applying zha.patch to const.py..."
        if [ -f "${home_assistant_path}/lib64/python3.13/site-packages/zha/application/const.py" ]; then
            if patch ${home_assistant_path}/lib64/python3.13/site-packages/zha/application/const.py < "${current_dir}/zha.patch"; then
                print_info "zha.patch applied successfully"
            else
                print_error "Failed to apply zha.patch, continuing without patch"
            fi
        else
            print_error "Target file const.py not found, skipping zha.patch"
        fi
    else
        print_info "zha.patch not found in ${current_dir}, skipping"
    fi
    
    # Apply zigpy_cli.patch
    if [ -f "${current_dir}/zigpy_cli.patch" ]; then
        print_info "Applying zigpy_cli.patch to zigpy_cli..."
        if [ -f "${home_assistant_path}/lib64/python3.13/site-packages/zigpy_cli/const.py" ]; then
            if patch ${home_assistant_path}/lib64/python3.13/site-packages/zigpy_cli/const.py < "${current_dir}/zigpy_cli.patch"; then
                print_info "zigpy_cli.patch applied successfully"
            else
                print_error "Failed to apply zigpy_cli.patch, continuing without patch"
            fi
        else
            print_error "Target directory zigpy_cli not found, skipping zigpy_cli.patch"
        fi
    else
        print_info "zigpy_cli.patch not found in ${current_dir}, skipping"
    fi

    deactivate
fi

#/srv/matter_server/bin/matter-server
# https://github.com/home-assistant-libs/python-matter-server/releases
if [ ! -e "${matter_server_path}/bin/matter-server" ]; then
    print_info "[2]Building python matter-server venv for hacore_${version}.deb ..."
    mkdir -p ${matter_server_path}

    mkdir -p /data /updates
    chmod 777 /data /updates
    touch /tmp/chip_kvs && chmod 766 /tmp/chip_kvs || { print_error "Failed to setup directories"; }


    print_info "Using python[matter-server]: ${python3_dir}/bin/python3"
    cd ${matter_server_path}
    ${python3_dir}/bin/python3 -m venv .
    source ${matter_server_path}/bin/activate

    pip3 config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple/
    pip3 config set install.trusted-host pypi.tuna.tsinghua.edu.cn

    python3 -m pip install python-matter-server[server]=="$MATTER_SERVER_VERSION"

    deactivate
fi


print_info "Install help scripts and service ..."

mkdir -p /var/lib/homeassistant
mkdir -p /var/lib/homeassistant/homeassistant
mkdir -p /var/lib/homeassistant/matter_server

if [ ! -f "/usr/local/bin/zigpy_help.sh" ]; then
    cp ${current_dir}/zigpy_help.sh /usr/local/bin/zigpy_help.sh
    chmod +x /usr/local/bin/zigpy_help.sh
fi

if [ -d "${home_assistant_path}/bin" ]; then
    cp ${current_dir}/home_assistant_init.sh ${home_assistant_path}/bin/home_assistant_init.sh
    chmod +x ${home_assistant_path}/bin/home_assistant_init.sh

    cp ${current_dir}/home_assistant_zigbee_fix.sh ${home_assistant_path}/bin/home_assistant_zigbee_fix.sh
    chmod +x ${home_assistant_path}/bin/home_assistant_zigbee_fix.sh

    cp ${current_dir}/home_assistant_blz_reset.sh ${home_assistant_path}/bin/home_assistant_blz_reset.sh
    chmod +x ${home_assistant_path}/bin/home_assistant_blz_reset.sh

    cp ${current_dir}/home_assistant_boot_check.sh ${home_assistant_path}/bin/home_assistant_boot_check.sh
    cp ${current_dir}/home_assistant_boot_check.py ${home_assistant_path}/bin/home_assistant_boot_check.py
    chmod +x ${home_assistant_path}/bin/home_assistant_boot_check.sh
    chmod +x ${home_assistant_path}/bin/home_assistant_boot_check.py

    cp ${current_dir}/home_assistant_zha_enable.py ${home_assistant_path}/bin/home_assistant_zha_enable.py
    chmod +x ${home_assistant_path}/bin/home_assistant_zha_enable.py

    cp ${current_dir}/home_assistant_z2m_enable.py ${home_assistant_path}/bin/home_assistant_z2m_enable.py
    chmod +x ${home_assistant_path}/bin/home_assistant_z2m_enable.py
fi

if [ ! -f "/usr/lib/systemd/system/home-assistant.service" ]; then
    cp ${current_dir}/home-assistant.service /usr/lib/systemd/system/home-assistant.service
    systemctl daemon-reload
fi

if [ ! -f "/usr/lib/systemd/system/matter-server.service" ]; then
    cp ${current_dir}/matter-server.service /usr/lib/systemd/system/matter-server.service
    systemctl daemon-reload
fi

print_info "Backup files for hacore_${version}.deb ..."
rm -rf ${output_dir}/srv
rm -rf ${output_dir}/usr
rm -rf ${output_dir}/lib

mkdir -p ${output_dir}/usr/local/bin/
chmod 755 ${output_dir}/usr/local

if [ -f "/usr/local/bin/chip-ota-provider-app" ]; then
    cp /usr/local/bin/chip-ota-provider-app ${output_dir}/usr/local/bin/
    strip ${output_dir}/usr/local/bin/chip-ota-provider-app
else
    print_info "Warning: chip-ota-provider-app not found."
fi

if [ -f "/usr/local/bin/zigpy_help.sh" ]; then
    cp /usr/local/bin/zigpy_help.sh ${output_dir}/usr/local/bin/
fi

mkdir -p ${output_dir}/srv
chmod 755 ${output_dir}/srv
cp /srv/* ${output_dir}/srv/ -R

mkdir -p ${output_dir}/lib/systemd/system/
cp /lib/systemd/system/home-assistant.service ${output_dir}/lib/systemd/system/
cp /lib/systemd/system/matter-server.service ${output_dir}/lib/systemd/system/

print_info "Start to build hacore_${version}.deb ..."
dpkg-deb --build ${output_dir} ${current_dir}/hacore_${version}.deb

# rm -rf ${output_dir}/srv > /dev/null 2>&1
# rm -rf ${output_dir}/usr > /dev/null 2>&1
# rm -rf ${output_dir}/lib > /dev/null 2>&1
#rm -rf ${output_dir} > /dev/null 2>&1

print_info "Build hacore_${version}.deb finished ..."

