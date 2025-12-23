#!/bin/bash

current_dir=$(pwd)
output_dir="${current_dir}/output"

REBUILD=false
CLEAN=false

SCRIPT="R3"
print_info() { echo -e "\e[1;34m[${SCRIPT}] INFO:\e[0m $1"; }
print_error() { echo -e "\e[1;31m[${SCRIPT}] ERROR:\e[0m $1"; }
print_warn() { echo -e "\e[1;33m[${SCRIPT}] WARN:\e[0m $1"; }

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

    systemctl stop linuxbox-hubv3-bridge.service || true
    systemctl disable linuxbox-hubv3-bridge.service || true
    rm -rf /lib/systemd/system/linuxbox-hubv3-bridge.service > /dev/null 2>&1
    rm -rf /usr/local/bin/linuxbox-hubv3-bridge > /dev/null 2>&1
    rm -rf /var/lib/hubv3-bridge > /dev/null 2>&1

    systemctl daemon-reload > /dev/null 2>&1
    exit 0
fi

if [[ "$REBUILD" == true ]]; then
    rm -rf "${output_dir}" > /dev/null 2>&1

    mkdir -p "${output_dir}"
    cp ${current_dir}/DEBIAN ${output_dir}/ -R
fi

print_info "Create output directory ..."
mkdir -p "${output_dir}"

print_info "Sync DEBIAN ..."
cp ${current_dir}/DEBIAN ${output_dir}/ -R

# Copy files from prebuild directory
prebuild_dir="${current_dir}/prebuild"

if [ -d "${prebuild_dir}" ]; then
    print_info "Copying files from prebuild directory ..."
    
    # Create target directories
    mkdir -p "${output_dir}/usr/local/bin"
    mkdir -p "${output_dir}/var/lib/hubv3-bridge"
    mkdir -p "${output_dir}/lib/systemd/system"
    
    # Copy binary
    if [ -f "${prebuild_dir}/linuxbox-hubv3-bridge" ]; then
        cp "${prebuild_dir}/linuxbox-hubv3-bridge" "${output_dir}/usr/local/bin/"
        chmod +x "${output_dir}/usr/local/bin/linuxbox-hubv3-bridge"
    else
        print_error "linuxbox-hubv3-bridge binary not found in prebuild directory"
        exit 1
    fi
    
    # Copy service file
    if [ -f "${prebuild_dir}/linuxbox-hubv3-bridge.service" ]; then
        cp "${prebuild_dir}/linuxbox-hubv3-bridge.service" "${output_dir}/lib/systemd/system/"
    else
        print_error "linuxbox-hubv3-bridge.service not found in prebuild directory"
        exit 1
    fi
    
    # Copy configuration files
    if [ -f "${prebuild_dir}/command.sh" ]; then
        cp "${prebuild_dir}/command.sh" "${output_dir}/var/lib/hubv3-bridge/"
        chmod +x "${output_dir}/var/lib/hubv3-bridge/command.sh"
    else
        print_error "command.sh not found in prebuild directory"
        exit 1
    fi
    
    if [ -f "${prebuild_dir}/configuration.yaml" ]; then
        cp "${prebuild_dir}/configuration.yaml" "${output_dir}/var/lib/hubv3-bridge/"
    else
        print_warn "configuration.yaml not found in prebuild directory (optional)"
    fi
    
    if [ -f "${prebuild_dir}/configuration.yaml.example" ]; then
        cp "${prebuild_dir}/configuration.yaml.example" "${output_dir}/var/lib/hubv3-bridge/"
    else
        print_warn "configuration.yaml.example not found in prebuild directory (optional)"
    fi
else
    print_error "prebuild directory not found"
    exit 1
fi

print_info "Start to build thirdreality-bridge_${version}.deb ..."
dpkg-deb --build ${output_dir} ${current_dir}/thirdreality-bridge_${version}.deb

print_info "Build thirdreality-bridge_${version}.deb finished ..."

