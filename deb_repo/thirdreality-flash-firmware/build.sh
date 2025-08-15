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
    rm -rf ${current_dir}/*.deb > /dev/null 2>&1

    print_info "board_firmware_${version}.deb clear ..."
    exit 0
fi

if [[ "$REBUILD" == true ]]; then
    print_info "board_firmware_${version}.deb rebuilding ..."
    rm -rf "${output_dir}" > /dev/null 2>&1
    mkdir -p "${output_dir}"

    cp ${current_dir}/DEBIAN ${output_dir}/ -R
fi

print_info "Create output directory ..."
mkdir -p "${output_dir}"

print_info "syncing DEBIAN ..."
cp ${current_dir}/DEBIAN ${output_dir}/ -R

mkdir -p ${output_dir}/usr/lib/thirdreality/images
#mkdir -p ${output_dir}/etc/systemd/system

cp ${current_dir}/partition_images ${output_dir}/usr/lib/thirdreality/images/ -R

if [ -f "${current_dir}/bflb_iot.tar.gz" ]; then
    cp ${current_dir}/bflb_iot.tar.gz ${output_dir}/usr/lib/thirdreality/images/
fi

if [ -f "${current_dir}/bl706_func.sh" ]; then
    cp ${current_dir}/bl706_func.sh ${output_dir}/usr/lib/thirdreality/images/
    chmod +x ${output_dir}/usr/lib/thirdreality/images/bl706_func.sh
fi

if [ -f "${current_dir}/upgrade_firmware.sh" ]; then
    cp ${current_dir}/upgrade_firmware.sh ${output_dir}/usr/lib/thirdreality/images/
    chmod +x ${output_dir}/usr/lib/thirdreality/images/upgrade_firmware.sh
    
    # Replace VERSION in upgrade_firmware.sh with dynamic version
    sed -i "s/VERSION=\"1.00.00\"/VERSION=\"${version}\"/" ${output_dir}/usr/lib/thirdreality/images/upgrade_firmware.sh

    # Check if zigbee firmware exists and modify upgrade_firmware.sh accordingly
    if [ ! -f "${current_dir}/partition_images/blz_whole_img.bin" ]; then
        # Comment out zigbee function call if firmware doesn't exist
        sed -i 's/^flash_zigbee$/#flash_zigbee/' ${output_dir}/usr/lib/thirdreality/images/upgrade_firmware.sh
    fi

    # Check if thread firmware exists and modify upgrade_firmware.sh accordingly
    if [ ! -f "${current_dir}/partition_images/thread_whole_img.bin" ]; then
        # Comment out thread function call if firmware doesn't exist
        sed -i 's/^flash_thread$/#flash_thread/' ${output_dir}/usr/lib/thirdreality/images/upgrade_firmware.sh
    fi

fi

# Copy systemd service file
# if [ -f "${current_dir}/thirdreality-firmware-upgrade.service" ]; then
#     cp ${current_dir}/thirdreality-firmware-upgrade.service ${output_dir}/etc/systemd/system/
# fi

print_info "Start to build board_firmware_${version}.deb ..."
dpkg-deb --build ${output_dir} ${current_dir}/board_firmware_${version}.deb


print_info "Build board_firmware_${version}.deb finished ..."





