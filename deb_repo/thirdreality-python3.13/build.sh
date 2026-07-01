#!/bin/bash

current_dir=$(pwd)
output_dir="${current_dir}/output"

REBUILD=false
CLEAN=false

PYTHON_VERSION="3.13" # main version
INSTALL_PYTHON_VERSION="3.13.11" # sub verion, for download
python3_dir="/usr/local/python3" # install target directory

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

download_file() {
    local url=$1
    local output=$2
    if [[ ! -f "$output" ]]; then
        curl -Lo "$output" "$url" || { print_error "Failed to download $url"; exit 1; }
        chmod +x "$output"
    fi
}

print_info "Target Python Version: $INSTALL_PYTHON_VERSION"

# ensure DEBIAN/control exists
if [[ ! -f "${current_dir}/DEBIAN/control" ]]; then
    print_error "Missing DEBIAN/control. Please verify the directory."
    exit 1
fi

version=$(grep '^Version:' ${current_dir}/DEBIAN/control | awk '{print $2}')
print_info "Config Python Version: $version"

if [[ "$CLEAN" == true ]]; then
    rm -rf "${output_dir}" > /dev/null 2>&1
    rm -rf ${current_dir}/*.deb > /dev/null 2>&1
    rm -rf ${current_dir}/Python-$INSTALL_PYTHON_VERSION.tgz > /dev/null 2>&1
    rm -rf ${current_dir}/Python-$INSTALL_PYTHON_VERSION > /dev/null 2>&1

    rm -rf ${python3_dir} > /dev/null 2>&1

    print_info "thirdreality-python3.13.deb clear ..."
    exit 0
fi

if [[ "$REBUILD" == true ]]; then
    print_info "thirdreality-python3.13.deb rebuilding ..."
    rm -rf "${output_dir}" > /dev/null 2>&1
    mkdir -p "${output_dir}"

    cp ${current_dir}/DEBIAN ${output_dir}/ -R
fi

print_info "Create output directory ..."
mkdir -p "${output_dir}"

print_info "Sync DEBIAN ..."
cp ${current_dir}/DEBIAN ${output_dir}/ -R

dependencies=(
    make 
    build-essential 
    libssl-dev 
    zlib1g-dev 
    libbz2-dev 
    libreadline-dev 
    libsqlite3-dev 
    wget 
    curl 
    llvm 
    libncurses5-dev 
    libncursesw5-dev 
    xz-utils 
    tk-dev 
    liblzma-dev 
    tk-dev
    libffi-dev 
    libgdbm-dev 
    libgdbm-compat-dev
)

CURRENT_PYTHON=$(python3 --version | sed -E 's/Python\s+//')
if [ -f "${python3_dir}/bin/python${PYTHON_VERSION}" ]; then
    CURRENT_PYTHON=$("${python3_dir}/bin/python${PYTHON_VERSION}" --version | sed -E 's/Python\s+//')
fi

echo "Current python version is ${CURRENT_PYTHON} "

if [[ "$CURRENT_PYTHON" < "3.13.0" ]]; then
    is_apt_installed=$(dpkg -s libreadline-dev &>/dev/null && echo "yes" || echo "no")
    if [ "$is_apt_installed" == "no" ]; then
        echo "Install python dependent packages ..."
        apt-get update
        for package in "${dependencies[@]}"; do
            apt-get install -y "$package" || {
                echo "Warning: Failed to install [$package]."
            }
        done
    fi


    apt-get install -y libsqlite3-dev

    # https://www.python.org/ftp/python/3.13.3/Python-3.13.3.tgz
    if [ ! -e "${current_dir}/Python-$INSTALL_PYTHON_VERSION.tgz" ]; then
        echo "Downloading Python $INSTALL_PYTHON_VERSION ..."
        download_file "https://www.python.org/ftp/python/$INSTALL_PYTHON_VERSION/Python-$INSTALL_PYTHON_VERSION.tgz" "${current_dir}/Python-$INSTALL_PYTHON_VERSION.tgz"
    fi

    if ! tar -xf "${current_dir}/Python-$INSTALL_PYTHON_VERSION.tgz"; then
        echo "Error: extraction failed!" >&2
        echo "Please remove: Python-$INSTALL_PYTHON_VERSION.tgz and retry after checking the network." >&2
        exit 1
    fi

    #https://docs.python.org/3.13/using/unix.html#building-python
    cd ${current_dir}/Python-$INSTALL_PYTHON_VERSION
    ./configure --prefix=${python3_dir} --enable-optimizations --disable-test-modules --with-ensurepip=install
    make -j "$(nproc)"
    make altinstall

    if [ -f "${python3_dir}/bin/python3.13" ]; then
        strip "${python3_dir}/bin/python3.13"
    fi

    ln -snf ${python3_dir}/bin/python3.13 ${python3_dir}/bin/python3
    ln -snf ${python3_dir}/bin/pip3.13 ${python3_dir}/bin/pip3
    echo "Python $PYTHON_VERSION installed."    
fi

if [ ! -f "${python3_dir}/bin/python${PYTHON_VERSION}" ]; then
    echo "Warning: python${PYTHON_VERSION} not found."
    exit 1
fi

if [ ! -f "${python3_dir}/bin/pip${PYTHON_VERSION}" ]; then
    echo "Warning: pip${PYTHON_VERSION} not found."
    exit 1
fi

if [ ! -f "${python3_dir}/bin/python${PYTHON_VERSION}-config" ]; then
    echo "Warning: python${PYTHON_VERSION}-config not found."
    exit 1
fi

CURRENT_PYTHON=$(python3 --version | sed -E 's/Python\s+//')
if [ -f "${python3_dir}/bin/python3" ]; then
    CURRENT_PYTHON=$("${python3_dir}/bin/python${PYTHON_VERSION}" --version | sed -E 's/Python\s+//')
fi

if [[ "$CURRENT_PYTHON" < "3.13.0" ]]; then
    echo "Python install may fail, abort ..."
    exit 1
fi

echo "Backup file for new python_${PYTHON_VERSION}.deb ..."

mkdir -p ${output_dir}/${python3_dir}
chmod 755 ${output_dir}/${python3_dir}

cp ${python3_dir}/* ${output_dir}/${python3_dir}/ -R

echo "Strip ${output_dir}/${python3_dir}/bin/python3.13 ..."
strip ${output_dir}/${python3_dir}/bin/python3.13

echo "Start to build python3_${version}.deb ..."
dpkg-deb --build ${output_dir} ${current_dir}/python3_${version}.deb

#rm -rf ${output_dir}/usr/

echo "Build python3_${version}.deb success ..."
