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


if [[ "$CLEAN" == true ]]; then
    rm -rf "${output_dir}" > /dev/null 2>&1
    rm -rf ${current_dir}/LinuxBox_Supervisor > /dev/null 2>&1

    rm -rf /usr/local/lib/python3.11/dist-packages/supervisor > /dev/null 2>&1
    rm -rf /usr/local/bin/supervisor > /dev/null 2>&1
    rm -rf /etc/systemd/system/supervisor.service > /dev/null 2>&1
    rm -rf /etc/systemd/system/btgatt-config.service > /dev/null 2>&1

    systemctl daemon-reload > /dev/null 2>&1
    exit 0
fi

if [[ "$REBUILD" == true ]]; then
    rm -rf "${output_dir}" > /dev/null 2>&1
    rm -rf ${current_dir}/LinuxBox_Supervisor > /dev/null 2>&1

    mkdir -p "${output_dir}"
    cp ${current_dir}/DEBIAN ${output_dir}/ -R
fi

print_info "Create output directory ..."
mkdir -p "${output_dir}"

print_info "Sync DEBIAN ..."
cp ${current_dir}/DEBIAN ${output_dir}/ -R

supervised_dir="${current_dir}/LinuxBox_Supervisor"


if [ ! -d "${current_dir}/LinuxBox_Supervisor" ]; then
    print_info "Clone LinuxBox_Supervisor from main branch ..."
    /usr/bin/git --version
    /usr/bin/git clone git@github.com:thirdreality/LinuxBox_Supervisor.git -b main

    current_date=$(date +"%Y%m%d-%H%M")
    print_info "Updating DEVICE_BUILD_NUMBER to ${current_date}"
    sed -i "s/DEVICE_BUILD_NUMBER=\"[0-9]*-[0-9]*\"/DEVICE_BUILD_NUMBER=\"${current_date}\"/" "${supervised_dir}/supervisor/const.py"
fi


if [ -d "${supervised_dir}" ]; then
    print_info "Copy supervisor files to output directory ..."

    mkdir -p "${output_dir}/usr/local/bin"
    mkdir -p "${output_dir}/usr/local/lib/python3.11/dist-packages"

    mkdir -p "${output_dir}/etc/systemd/system"
    mkdir -p "${output_dir}/lib/systemd/system"

    cp -r "${supervised_dir}/supervisor" "${output_dir}/usr/local/lib/python3.11/dist-packages"
    cp "${supervised_dir}/bin/supervisor" "${output_dir}/usr/local/bin/"
    chmod +x "${output_dir}/usr/local/bin/supervisor"

    cp "${supervised_dir}/bin/btgatt-config-server" "${output_dir}/usr/local/bin/"
    chmod +x "${output_dir}/usr/local/bin/btgatt-config-server"

    cp "${supervised_dir}/supervisor.service" "${output_dir}/etc/systemd/system/"
    cp "${supervised_dir}/btgatt-config.service" "${output_dir}/etc/systemd/system/"
fi

if [ -f "${current_dir}/prebuild/factory-reset.sh" ]; then
    print_info "Copy factory-reset.sh to output directory ..."
    mkdir -p "${output_dir}/lib/armbian"
    cp "${current_dir}/prebuild/factory-reset.sh" "${output_dir}/lib/armbian/"
    chmod +x "${output_dir}/lib/armbian/factory-reset.sh"
fi

if [ -f "${current_dir}/prebuild/hubv3-usb-sync.sh" ]; then
    print_info "Copy hubv3-usb-sync.sh to output directory ..."
    mkdir -p "${output_dir}/lib/thirdreality"
    # rename the file to avoid conflict
    cp "${current_dir}/prebuild/hubv3-usb-sync.sh" "${output_dir}/lib/thirdreality/hubv3-usb-sync-latest.sh"
    chmod +x "${output_dir}/lib/thirdreality/hubv3-usb-sync-latest.sh"
fi

if [ -f "${current_dir}/prebuild/hubv3-generate-ota-indexes.sh" ]; then
    print_info "Copy hubv3-generate-ota-indexes.sh to output directory ..."
    mkdir -p "${output_dir}/lib/thirdreality"
    cp "${current_dir}/prebuild/hubv3-generate-ota-indexes.sh" "${output_dir}/lib/thirdreality/hubv3-generate-ota-indexes.sh"
    chmod +x "${output_dir}/lib/thirdreality/hubv3-generate-ota-indexes.sh"
fi

if [ -f "${current_dir}/prebuild/armbian-firstrun" ]; then
    print_info "Copy armbian-firstrun to output directory ..."
    mkdir -p "${output_dir}/lib/armbian"
    cp "${current_dir}/prebuild/armbian-firstrun" "${output_dir}/lib/armbian/"
    chmod +x "${output_dir}/lib/armbian/armbian-firstrun"
fi

print_info "Start to build linuxbox-supervisor_${version}.deb ..."
dpkg-deb --build ${output_dir} ${current_dir}/linuxbox-supervisor_${version}.deb

# rm -rf ${output_dir}/usr > /dev/null 2>&1
# rm -rf ${output_dir}/etc > /dev/null 2>&1
# rm -rf ${output_dir}/lib > /dev/null 2>&1

print_info "Build linuxbox-supervisor_${version}.deb finished ..."



