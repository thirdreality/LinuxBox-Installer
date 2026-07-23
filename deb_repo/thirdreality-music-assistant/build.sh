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

# OOM 保护 + 编译期临时停无关重内存服务（结束自动恢复）。逻辑复用仓库根
# deb_repo/build_common.sh。开关: TR_SKIP_SWAP=1 / TR_KEEP_SERVICES=1 / TR_SWAP_TARGET_MIB=N
source "$(dirname "$(readlink -f "$0")")/../build_common.sh"
TR_SWAPFILE="${current_dir}/.build-swap"

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
# 说明: 2.9.0 起 Music Assistant 要求 Python 3.14 (pyproject requires-python>=3.14)。
# 设备运行时已升级到 Python 3.14.6 (thirdreality-python3 3.14.6)，因此解除 2.8.9
# 的锁定，跟进最新稳定版 2.9.9 (2026-07-17)。
export MUSIC_ASSISTANT_VERSION="2.9.9"

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
    print_error "Python 3.14+ is needed (MA >= 2.9.0), abort ..."
    exit 1  
fi

if tr_ver_lt "$CURRENT_PYTHON" "3.14.0"; then
    print_info "Python 3.14+ is needed (MA >= 2.9.0, current: $CURRENT_PYTHON), abort ..."
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
    # 编译前：停无关重内存服务(结束自动恢复) + 按需临时 swap，避免 OOM
    tr_build_guard_start
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

    # 上游 2.9.9 的 requirements_all.txt 存在坏 pin：audible==0.10.0 的元数据要求
    # Python <3.13，与 MA 2.9 自身 requires-python>=3.14 矛盾，会导致整个 -r 安装
    # 被 pip 中止（0.11.0 又与 pillow==12.2.0 冲突，无法简单替换）。这里直接移除
    # 该行预装——Audible provider 的 manifest pin ==0.10.0，在 Python 3.14 上
    # 本就不可用（上游问题），其余 provider 不受影响。上游修复后可移除此 sed。
    sed -i '/^audible==/d' requirements_all.txt

    # usearch==2.25.3 依赖 numkong（不 pin 版本）；numkong 最新 7.7.1 未发布
    # aarch64 wheel（上游 CI 缺失），pip 会回退源码编译并在 gcc 12 上失败
    # （NEON dotprod intrinsics 目标选项问题）。显式 pin 到有 aarch64/cp314
    # wheel 的 7.7.0。numkong 恢复发布 aarch64 wheel 后可移除。
    echo "numkong==7.7.0" >> requirements_all.txt

    ${UV_INSTALLED_COMMAND} --find-links "https://wheels.home-assistant.io/musllinux/" \
                -r requirements_all.txt || {
        print_error "Failed to install requirements_all.txt"
        exit 1
    }

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
    # 注意: --link-mode=copy 是 uv 专属参数，pip 不支持；按工具区分并强制失败中断
    # （此前 pip 路径下该步骤静默失败，会打出缺 music-assistant 本体的坏包）。
    if [ $UV_INSTALLED == true ]; then
        ${UV_INSTALLED_COMMAND} --no-cache --link-mode=copy \
                --find-links "https://wheels.home-assistant.io/musllinux/" \
                "${wheel_file}" || { print_error "Failed to install music-assistant wheel"; exit 1; }
    else
        ${UV_INSTALLED_COMMAND} --no-cache-dir \
                --find-links "https://wheels.home-assistant.io/musllinux/" \
                "${wheel_file}" || { print_error "Failed to install music-assistant wheel"; exit 1; }
    fi
    
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


cp ${current_dir}/prebuild/post-fix-music-assistant.sh /srv/music-assistant/bin/post-fix-music-assistant.sh
chmod 755 /srv/music-assistant/bin/post-fix-music-assistant.sh

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

if [ -d "${current_dir}/prebuild/debs/" ]; then
    mkdir -p ${output_dir}/lib/thirdreality/archives_music_assistant/
    for deb_file in ${current_dir}/prebuild/debs/*.deb; do
        if [ -f "$deb_file" ]; then
            cp "$deb_file" ${output_dir}/lib/thirdreality/archives_music_assistant/
        fi
    done
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

