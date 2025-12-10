#!/bin/bash

current_dir=$(pwd)
output_dir="${current_dir}/output"
music_assistant_path="/srv/music-assistant"
widevine_cdm_path="/usr/local/bin/widevine_cdm"
python3_dir="/usr/local/python3" # install target directory

UV_INSTALLED=false

REBUILD=false
CLEAN=false

SCRIPT="R3"
print_info() { echo -e "\e[1;34m[${SCRIPT}] INFO:\e[0m $1"; }
print_error() { echo -e "\e[1;31m[${SCRIPT}] ERROR:\e[0m $1"; }

print_info "Build script for ThirdReality Music-Assistant-Server"
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
export MUSIC_ASSISTANT_VERSION="2.6.3"

version=$(grep '^Version:' ${current_dir}/prebuild/DEBIAN/control | awk '{print $2}')
print_info "Version: $version"

if [[ "$CLEAN" == true ]]; then
    rm -rf "${output_dir}" > /dev/null 2>&1
    rm -rf ${current_dir}/*.deb > /dev/null 2>&1

    systemctl stop music-assistant.service || true
    systemctl disable music-assistant.service || true

    rm -rf /lib/systemd/system/music-assistant.service

    rm -rf ${widevine_cdm_path} || true
    rm -rf /usr/local/bin/ffmpeg || true
    rm -rf /usr/local/bin/ffprobe || true
    rm -rf /var/lib/homeassistant/music-assistant || true

    print_info "Removing ${music_assistant_path} ..."
    rm -rf ${music_assistant_path}

    systemctl daemon-reload

    print_info "music-assistant_${version}.deb clear finished ..."
    exit 0
fi

if [[ "$REBUILD" == true ]]; then
    rm -rf "${output_dir}" > /dev/null 2>&1
    mkdir -p "${output_dir}"
fi

mkdir -p "${output_dir}"

cp ${current_dir}/prebuild/DEBIAN ${output_dir}/ -R

download_file() {
    local url=$1
    local output=$2
    if [[ ! -f "$output" ]]; then
        curl -L \
             --http1.1 \
             --fail \
             --retry 5 \
             --retry-delay 2 \
             --connect-timeout 10 \
             --max-time 600 \
             -H "User-Agent: wget" \
             -H "Accept: application/octet-stream" \
             -o "$output" "$url" || {
            print_error "Failed to download $url via curl"
            rm -f "$output"
            exit 1
        }
        chmod +x "$output"
    fi
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
if [ -z "$MUSIC_ASSISTANT_VERSION" ]; then
    print_error "One or more version variables are not set. Please set MUSIC_ASSISTANT_VERSION"
    exit 1
fi

if [ ! -e "${music_assistant_path}/bin/mass" ]; then
    print_info "Building python music assistant venv for music-assistant_${version}.deb ..."
    mkdir -p ${music_assistant_path}

    print_info "Using python[music_assistant]: ${python3_dir}/bin/python3"
    cd ${music_assistant_path}
    ${python3_dir}/bin/python3 -m venv .
    source ${music_assistant_path}/bin/activate

    if [ $UV_INSTALLED == false ]; then
        pip3 config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple/
        pip3 config set install.trusted-host pypi.tuna.tsinghua.edu.cn
    else
        export UV_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple/
        export UV_HTTP_TIMEOUT=300
    fi

    # 下载 requirements_all.txt 从 GitHub
    requirements_url="https://raw.githubusercontent.com/music-assistant/server/${MUSIC_ASSISTANT_VERSION}/requirements_all.txt"
    requirements_file="${music_assistant_path}/requirements_all.txt"
    print_info "Downloading requirements_all.txt from ${requirements_url} ..."

    curl -L \
         --http1.1 \
         --fail \
         --retry 5 \
         --retry-delay 2 \
         --connect-timeout 10 \
         --max-time 600 \
         -H "User-Agent: curl" \
         -o "${requirements_file}" "${requirements_url}" || {
        print_error "Failed to download requirements_all.txt from ${requirements_url}"
        exit 1
    }
    print_info "Downloaded requirements_all.txt successfully"

    ${UV_INSTALLED_COMMAND} --find-links "https://wheels.home-assistant.io/musllinux/" \
                -r requirements_all.txt

    # 下载并安装 music-assistant wheel 文件
    wheel_url="https://github.com/music-assistant/server/releases/download/${MUSIC_ASSISTANT_VERSION}/music_assistant-${MUSIC_ASSISTANT_VERSION}-py3-none-any.whl"
    wheel_file="${music_assistant_path}/music_assistant-${MUSIC_ASSISTANT_VERSION}-py3-none-any.whl"
    print_info "Downloading music-assistant wheel from ${wheel_url} ..."
    curl -L \
         --http1.1 \
         --fail \
         --retry 5 \
         --retry-delay 2 \
         --connect-timeout 10 \
         --max-time 600 \
         -H "User-Agent: curl" \
         -o "${wheel_file}" "${wheel_url}" || {
        print_error "Failed to download music-assistant wheel from ${wheel_url}"
        exit 1
    }
    print_info "Downloaded music-assistant wheel successfully"
    
    print_info "Installing music-assistant from local wheel file ..."
    ${UV_INSTALLED_COMMAND} --no-cache --link-mode=copy \
            --find-links "https://wheels.home-assistant.io/musllinux/" \
            "${wheel_file}"
    
    # 清理下载的 wheel 文件
    rm -f "${wheel_file}"

    deactivate
fi

print_info "Install help scripts and service ..."

mkdir -p /var/lib/homeassistant
mkdir -p /var/lib/homeassistant/music_assistant

if [ -d "${current_dir}/prebuild/widevine_cdm" ]; then
    cp ${current_dir}/prebuild/widevine_cdm /usr/local/bin/ -R
else
    print_info "Warning: widevine_cdm directory not found in prebuild, skipping..."
fi

if [ -f "${current_dir}/prebuild/ffmpeg.tar.gz" ]; then
    tar -xzf ${current_dir}/prebuild/ffmpeg.tar.gz -C /usr/local/bin/
    chmod +x /usr/local/bin/ffmpeg
    chmod +x /usr/local/bin/ffprobe
else
    print_info "Warning: ffmpeg.tar.gz not found in prebuild, skipping..."
fi

if [ -d "${music_assistant_path}/bin" ]; then
    find ${music_assistant_path} -name "*.pyc" -delete
    find ${music_assistant_path} -name "__pycache__" -type d -exec rm -rf {} +
fi

if [ ! -f "/lib/systemd/system/music-assistant.service" ]; then
    if [ -f "${current_dir}/prebuild/music-assistant.service" ]; then
        cp ${current_dir}/prebuild/music-assistant.service /lib/systemd/system/music-assistant.service
        systemctl daemon-reload
    else
        print_info "Warning: music-assistant.service not found in prebuild, skipping..."
    fi
fi

print_info "Backup files for music-assistant_${version}.deb ..."
rm -rf ${output_dir}/srv
rm -rf ${output_dir}/usr
rm -rf ${output_dir}/lib

mkdir -p ${output_dir}/usr/local/bin/
chmod 755 ${output_dir}/usr/local

if [ -f "/usr/local/bin/widevine_cdm/private_key.pem" ]; then
    cp /usr/local/bin/widevine_cdm ${output_dir}/usr/local/bin/ -R
else
    print_info "Warning: widevine_cdm not found."
fi

if [ -f "/usr/local/bin/ffmpeg" ]; then
    cp /usr/local/bin/ffmpeg ${output_dir}/usr/local/bin/
else
    print_info "Warning: ffmpeg not found."
fi

if [ -f "/usr/local/bin/ffprobe" ]; then
    cp /usr/local/bin/ffprobe ${output_dir}/usr/local/bin/
else
    print_info "Warning: ffprobe not found."
fi

mkdir -p ${output_dir}/srv/music-assistant
chmod 755 ${output_dir}/srv/music-assistant

cp ${current_dir}/prebuild/generate_mass_config.py /srv/music-assistant/bin/generate_mass_config.py
cp ${current_dir}/prebuild/template.json /srv/music-assistant/template.json
cp ${current_dir}/prebuild/options.json /srv/music-assistant/options.json
chmod 755 /srv/music-assistant/bin/generate_mass_config.py
chmod 644 /srv/music-assistant/template.json
chmod 644 /srv/music-assistant/options.json

cp /srv/music-assistant ${output_dir}/srv/ -R

mkdir -p ${output_dir}/lib/systemd/system/
if [ -f "/lib/systemd/system/music-assistant.service" ]; then
    cp /lib/systemd/system/music-assistant.service ${output_dir}/lib/systemd/system/
else
    print_info "Warning: music-assistant.service not found in /lib/systemd/system/, skipping..."
fi

# 清理输出目录中的Python缓存文件与目录，避免打包冗余内容
find "${output_dir}" -type d -name "__pycache__" -exec rm -rf {} +
find "${output_dir}" -type f -name "*.pyc" -delete

print_info "Start to build music-assistant_${version}.deb ..."
dpkg-deb --build ${output_dir} ${current_dir}/music-assistant_${version}.deb

# rm -rf ${output_dir}/srv > /dev/null 2>&1
# rm -rf ${output_dir}/usr > /dev/null 2>&1
# rm -rf ${output_dir}/lib > /dev/null 2>&1
#rm -rf ${output_dir} > /dev/null 2>&1

print_info "Build music-assistant_${version}.deb finished ..."

