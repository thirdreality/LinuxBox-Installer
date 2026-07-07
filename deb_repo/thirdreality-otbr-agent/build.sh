#!/bin/bash
# =============================================================================
# build.sh - ThirdReality OTBR Agent deb 打包脚本
#
# 对应版本: ot-br-posix v2026.07.0 (commit ec16e396, Thread 1.4, OTBR_MDNS=openthread)
#
# 与旧版主要变化:
#   - 编译方式: setup → bootstrap + cmake-build
#   - mDNS: 外部 mDNSResponder → 内置，无需 mdnsd/libdns_sd/libnss_mdns
#   - 删除: otbr-nat44（NAT64 内置）、mdns init.d、dbus conf、nss_mdns.conf
#   - 删除: otbr-agent-init.sh（ExecStartPre 改为 firewall start）
#   - CMAKE_INSTALL_PREFIX=/usr → 路径与旧版一致
#   - Web GUI: WEB_GUI=1/OTBR_WEB=ON，前端用系统已装的 nodejs/npm 构建
#     (bootstrap 仅在缺少 npm 时才 apt 安装；本机使用 NodeSource v24)
# =============================================================================

set -euo pipefail

current_dir=$(pwd)
output_dir="${current_dir}/output"

COMMIT="ec16e396382b4559e70a2c6fdeecb7d596a5e915"   # tag v2026.07.0
SRC_DIR="${current_dir}/ot-br-posix"
# npm 镜像（前端 web gui 的 npm install 走国内镜像，默认 registry 在国内会超时）
NPM_REGISTRY="${NPM_REGISTRY:-https://mirrors.tencent.com/npm/}"
HA_ADDONS_RAW="https://raw.githubusercontent.com/home-assistant/addons/master/openthread_border_router"

REBUILD=false
CLEAN=false

print_info()  { echo -e "\e[1;34m[BUILD] INFO:\e[0m $1"; }
print_error() { echo -e "\e[1;31m[BUILD] ERROR:\e[0m $1"; }
print_step()  { echo -e "\e[1;32m[BUILD] ===== $1 =====\e[0m"; }

# =============================================================================
# OOM 保护：这台设备内存很小(~2GiB)，-j 全核编译 OpenThread 的 C++ 峰值会超内存。
# 编译前按需创建临时 swap，编译结束(含失败/中断)由 trap 自动 swapoff 并删除。
# 可用 OTBR_SKIP_SWAP=1 跳过；用 OTBR_SWAP_TARGET_MIB 调整目标(默认 4096MiB)。
# =============================================================================
OTBR_SWAPFILE="${current_dir}/.otbr-build-swap"
OTBR_SWAP_CREATED=false

# 编译期间临时停止的、与 otbr 编译无关的重内存服务（结束后自动恢复）。
# 用 OTBR_KEEP_SERVICES=1 可保留不停。
OTBR_MEM_SERVICES=(home-assistant.service matter-server.service zigbee2mqtt.service)
OTBR_STOPPED_SERVICES=()

cleanup_swap() {
    if [[ "${OTBR_SWAP_CREATED}" == true ]]; then
        print_info "清理临时 swap: ${OTBR_SWAPFILE}"
        swapoff "${OTBR_SWAPFILE}" 2>/dev/null || true
        rm -f "${OTBR_SWAPFILE}"
        OTBR_SWAP_CREATED=false
    fi
}

restart_stopped_services() {
    if (( ${#OTBR_STOPPED_SERVICES[@]} > 0 )); then
        for svc in "${OTBR_STOPPED_SERVICES[@]}"; do
            print_info "恢复服务: ${svc}"
            systemctl start "${svc}" 2>/dev/null || print_error "恢复 ${svc} 失败，请手动: systemctl start ${svc}"
        done
        OTBR_STOPPED_SERVICES=()
    fi
}

# 退出(含成功/失败/中断)时：先 swapoff(此时服务仍停、内存最空)，再恢复服务
cleanup() {
    cleanup_swap
    restart_stopped_services
}
trap cleanup EXIT

stop_unrelated_services() {
    [[ "${OTBR_KEEP_SERVICES:-0}" == "1" ]] && { print_info "OTBR_KEEP_SERVICES=1，编译期间保留所有服务"; return 0; }
    [[ "$(id -u)" -eq 0 ]] || { print_info "非 root，跳过临时停止服务"; return 0; }
    command -v systemctl >/dev/null 2>&1 || return 0
    for svc in "${OTBR_MEM_SERVICES[@]}"; do
        if systemctl is-active --quiet "${svc}" 2>/dev/null; then
            print_info "编译期间临时停止无关服务: ${svc}"
            if systemctl stop "${svc}" 2>/dev/null; then
                OTBR_STOPPED_SERVICES+=("${svc}")
            fi
        fi
    done
    [[ ${#OTBR_STOPPED_SERVICES[@]} -eq 0 ]] && print_info "无可停止的无关服务" || true
}

ensure_swap() {
    [[ "${OTBR_SKIP_SWAP:-0}" == "1" ]] && { print_info "OTBR_SKIP_SWAP=1，跳过 swap 检查"; return 0; }
    [[ "$(id -u)" -eq 0 ]] || { print_info "非 root，跳过 swap 自动配置"; return 0; }

    local want_mib="${OTBR_SWAP_TARGET_MIB:-4096}"
    local mem_avail swap_free have need_mib disk_free_mib
    mem_avail=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
    swap_free=$(free -m | awk '/Swap:/{print $4}')
    have=$(( mem_avail + swap_free ))
    print_info "内存检查: 可用RAM ${mem_avail}MiB + 空闲swap ${swap_free}MiB = ${have}MiB (目标 ${want_mib}MiB)"
    (( have >= want_mib )) && { print_info "内存充足，无需临时 swap"; return 0; }

    need_mib=$(( want_mib - have ))
    disk_free_mib=$(df -Pm "${current_dir}" | awk 'NR==2{print $4}')
    if (( disk_free_mib < need_mib + 2048 )); then
        print_error "磁盘剩余 ${disk_free_mib}MiB，不足以创建 ${need_mib}MiB swap；继续编译但可能 OOM。建议先停掉 HA/matter-server/zigbee2mqtt 释放内存。"
        return 0
    fi

    print_info "内存偏低，创建临时 swap ${need_mib}MiB: ${OTBR_SWAPFILE}"
    rm -f "${OTBR_SWAPFILE}"
    if fallocate -l "${need_mib}M" "${OTBR_SWAPFILE}" 2>/dev/null || \
       dd if=/dev/zero of="${OTBR_SWAPFILE}" bs=1M count="${need_mib}" status=none; then
        chmod 600 "${OTBR_SWAPFILE}"
        mkswap "${OTBR_SWAPFILE}" >/dev/null 2>&1
        if swapon "${OTBR_SWAPFILE}" 2>/dev/null; then
            OTBR_SWAP_CREATED=true
            print_info "临时 swap 已启用（编译结束自动清理）"
        else
            print_error "swapon 失败，继续（编译可能内存吃紧）"
            rm -f "${OTBR_SWAPFILE}"
        fi
    else
        print_error "创建 swap 文件失败，继续"
    fi
}

print_info "Usage: build.sh [--rebuild] [--clean]"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --rebuild) REBUILD=true ;;
        --clean)   CLEAN=true ;;
        *) print_error "未知参数: $1"; exit 1 ;;
    esac
    shift
done

version=$(grep '^Version:' "${current_dir}/DEBIAN/control" | awk '{print $2}')
print_info "Version: ${version}  Commit: ${COMMIT}"

# =============================================================================
# --clean: 卸载并清理
# =============================================================================
otbr_uninstall() {
    echo "停止并禁用服务..."
    for svc in otbr-web otbr-agent otbr-firewall hubv3-otbr-agent; do
        systemctl stop    "${svc}" 2>/dev/null || true
        systemctl disable "${svc}" 2>/dev/null || true
    done
    killall otbr-web otbr-agent 2>/dev/null || true

    # 清理 firewall
    update-rc.d otbr-firewall remove 2>/dev/null || true
    rm -f /etc/init.d/otbr-firewall
    rm -f /etc/systemd/system/otbr-agent.service.d/firewall.conf
    rmdir /etc/systemd/system/otbr-agent.service.d 2>/dev/null || true

    systemctl daemon-reload

    # 路由表
    sed -i.bak '/88[[:space:]]\+openthread/d' /etc/iproute2/rt_tables

    # sysctl
    rm -f /etc/sysctl.d/60-otbr-accept-ra.conf
    rm -f /etc/sysctl.d/60-otbr-ip-forward.conf
    sysctl -p /etc/sysctl.conf || true

    # 二进制 & 数据
    rm -f /usr/sbin/otbr-agent /usr/sbin/otbr-web /usr/sbin/ot-ctl
    rm -rf /usr/share/otbr-web
    rm -rf /usr/lib/thirdreality
    rm -rf /var/lib/thread

    echo "清理完成。"
}

if [[ "$CLEAN" == true ]]; then
    rm -rf "${output_dir}" "${current_dir}"/*.deb "${SRC_DIR}"
    otbr_uninstall
    exit 0
fi

if [[ "$REBUILD" == true ]]; then
    print_info "重新构建..."
    rm -rf "${output_dir}" "${SRC_DIR}"
fi

# =============================================================================
# Step 1: 准备 output 目录结构
# =============================================================================
print_step "Step 1: 准备目录"

mkdir -p "${output_dir}"
rm -rf "${output_dir}/DEBIAN"
cp -R "${current_dir}/DEBIAN" "${output_dir}/"

# 目标目录（对应 /usr prefix）
mkdir -p "${output_dir}/usr/sbin"
mkdir -p "${output_dir}/usr/share"
mkdir -p "${output_dir}/usr/lib/systemd/system"
mkdir -p "${output_dir}/usr/lib/thirdreality"
mkdir -p "${output_dir}/etc/default"
mkdir -p "${output_dir}/etc/init.d"
mkdir -p "${output_dir}/etc/sysctl.d"
mkdir -p "${output_dir}/etc/modules-load.d"
mkdir -p "${output_dir}/etc/systemd/system/otbr-agent.service.d"

# =============================================================================
# Step 2: 下载 HA 配置文件
# =============================================================================
print_step "Step 2: 下载 HA 附件"

HA_CONFIG_H="${current_dir}/openthread-core-ha-config-posix.h"
if [[ ! -f "${HA_CONFIG_H}" ]]; then
    wget -q -O "${HA_CONFIG_H}" "${HA_ADDONS_RAW}/openthread-core-ha-config-posix.h"
fi

# =============================================================================
# Step 3: Clone & checkout
# =============================================================================
print_step "Step 3: Clone ot-br-posix @ ${COMMIT}"

if [[ ! -d "${SRC_DIR}/.git" ]]; then
    git clone --depth 1 -b main https://github.com/openthread/ot-br-posix.git "${SRC_DIR}"
fi

cd "${SRC_DIR}"
CURRENT=$(git rev-parse HEAD)
if [[ "${CURRENT}" != "${COMMIT}"* ]]; then
    git fetch origin "${COMMIT}"
    git checkout "${COMMIT}"
fi

git submodule update --init

# 记录 commit 到 control
dirty_id=$(git describe --dirty --always)
commit_id=$(git log -1 --format=%H)
print_info "dirty-id: ${dirty_id}  commit: ${commit_id}"
echo "dirty-id: ${dirty_id}" >> "${output_dir}/DEBIAN/control"
echo "commit: ${commit_id}"  >> "${output_dir}/DEBIAN/control"

cd "${current_dir}"

# =============================================================================
# Step 4: Bootstrap（安装编译依赖）
# =============================================================================
print_step "Step 4: Bootstrap"

# Web GUI 前端(AngularJS/d3)在 cmake 阶段通过 `npm install` 拉取依赖。
# 我们使用系统已安装的 nodejs/npm（不让 bootstrap 用 apt 拉一个旧版本）。
# bootstrap 的逻辑是: WEB_GUI 开启且缺少 npm 时才 apt 安装 nodejs npm；
# 因此只要系统已有 node/npm，就会沿用系统版本。
if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    print_info "Using system nodejs: $(node --version) / npm $(npm --version)"
else
    print_error "系统未检测到 nodejs/npm，web gui 需要它们。请先安装 nodejs(含 npm)后再构建。"
    exit 1
fi
# 前端 npm install 走国内镜像，避免默认 registry 超时
export npm_config_registry="${NPM_REGISTRY}"
print_info "npm registry: $(npm config get registry)"

cd "${SRC_DIR}"
BORDER_ROUTING=1 BACKBONE_ROUTER=1 PLATFORM=debian RELEASE=1 \
WEB_GUI=1 REST_API=1 DOCKER=1 OTBR_MDNS=openthread \
./script/bootstrap

# 删除 libsystemd-dev 避免不必要的链接
apt-get purge -y libsystemd-dev 2>/dev/null || true
cd "${current_dir}"

# =============================================================================
# Step 5: 复制 HA config.h，cmake-build + ninja install
# =============================================================================
print_step "Step 5: cmake-build (PREFIX=/usr)"

# 编译前：先停掉无关重内存服务(结束自动恢复)，再按需配置临时 swap，避免 OOM
stop_unrelated_services
ensure_swap

CONFIG_H_DEST="${SRC_DIR}/third_party/openthread/repo/openthread-core-ha-config-posix.h"
cp "${HA_CONFIG_H}" "${CONFIG_H_DEST}"

# beta(1.4) 不需要打 patch

cd "${SRC_DIR}"
BORDER_ROUTING=1 BACKBONE_ROUTER=1 PLATFORM=debian RELEASE=1 \
WEB_GUI=1 REST_API=1 DOCKER=1 OTBR_MDNS=openthread \
./script/cmake-build \
    -DBUILD_TESTING=OFF \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DOTBR_FEATURE_FLAGS=ON \
    -DOTBR_MDNS=openthread \
    -DOTBR_VERSION= \
    -DOT_PACKAGE_VERSION= \
    -DOTBR_DBUS=OFF \
    -DOT_POSIX_RCP_HDLC_BUS=ON \
    "-DOTBR_VENDOR_NAME=Home Assistant" \
    "-DOTBR_PRODUCT_NAME=OpenThread Border Router" \
    -DOTBR_WEB=ON \
    -DOTBR_BORDER_ROUTING=ON \
    -DOTBR_REST=ON \
    -DOTBR_BACKBONE_ROUTER=ON \
    -DOTBR_TREL=ON \
    -DOTBR_NAT64=ON \
    "-DOT_POSIX_NAT64_CIDR=192.168.255.0/24" \
    -DOTBR_DNS_UPSTREAM_QUERY=ON \
    -DOT_CHANNEL_MONITOR=ON \
    -DOT_COAP=OFF \
    -DOT_COAPS=OFF \
    -DOT_THREAD_VERSION=1.4 \
    "-DOT_PROJECT_CONFIG=${CONFIG_H_DEST}"

cd "${SRC_DIR}/build/otbr"
ninja install

cd "${current_dir}"

# =============================================================================
# Step 6: 打包文件收集
# =============================================================================
print_step "Step 6: 收集文件"

# --- 二进制 ---
cp /usr/sbin/otbr-agent "${output_dir}/usr/sbin/"
cp /usr/sbin/otbr-web   "${output_dir}/usr/sbin/"
cp /usr/sbin/ot-ctl     "${output_dir}/usr/sbin/"

# --- Web 前端静态文件 ---
cp -R /usr/share/otbr-web "${output_dir}/usr/share/"

# --- systemd service 文件（cmake 安装到 /usr/lib/systemd/system/）---
cp /usr/lib/systemd/system/otbr-agent.service "${output_dir}/usr/lib/systemd/system/"
cp /usr/lib/systemd/system/otbr-web.service   "${output_dir}/usr/lib/systemd/system/"

# --- ThirdReality 专属脚本 ---
cp "${current_dir}/prebuild/hubv3-otbr-agent.sh"      "${output_dir}/usr/lib/thirdreality/"
cp "${current_dir}/prebuild/hubv3-otbr-agent.service"  "${output_dir}/usr/lib/systemd/system/"
cp "${current_dir}/prebuild/otbr_database"             "${output_dir}/usr/lib/thirdreality/"
chmod +x "${output_dir}/usr/lib/thirdreality/hubv3-otbr-agent.sh"
chmod +x "${output_dir}/usr/lib/thirdreality/otbr_database"

# --- otbr-firewall init.d 脚本 ---
cp "${SRC_DIR}/script/otbr-firewall" "${output_dir}/etc/init.d/otbr-firewall"
chmod +x "${output_dir}/etc/init.d/otbr-firewall"

# --- otbr-agent drop-in：ExecStartPre 先建 ipset ---
cat > "${output_dir}/etc/systemd/system/otbr-agent.service.d/firewall.conf" << 'EOF'
[Service]
ExecStartPre=-/etc/init.d/otbr-firewall start
EOF

# --- env 配置文件（路径与旧版一致：/etc/default/otbr-agent）---
cp "${current_dir}/prebuild/otbr-agent" "${output_dir}/etc/default/otbr-agent"

# --- otbr-web env：自定义 web GUI 端口(避开常见的 80)与监听地址 ---
cp "${current_dir}/prebuild/otbr-web" "${output_dir}/etc/default/otbr-web"

# --- sysctl：开启 IPv6 转发和 RA ---
cat > "${output_dir}/etc/sysctl.d/60-otbr-ip-forward.conf" << 'EOF'
net.ipv6.conf.all.forwarding=1
net.ipv4.ip_forward=1
net.core.optmem_max=65536
EOF

cat > "${output_dir}/etc/sysctl.d/60-otbr-accept-ra.conf" << 'EOF'
net.ipv6.conf.wlan0.accept_ra=2
net.ipv6.conf.wlan0.accept_ra_rt_info_max_plen=64
EOF

# --- 内核模块开机自动加载 ---
cat > "${output_dir}/etc/modules-load.d/otbr.conf" << 'EOF'
ip6table_filter
ip6_tables
xt_set
EOF

# =============================================================================
# Step 7: 列出产出文件
# =============================================================================
print_step "Step 7: 产出文件"
find "${output_dir}" -type f | grep -v "^${output_dir}/DEBIAN" | sort

# =============================================================================
# Step 8: 构建 deb
# =============================================================================
print_step "Step 8: dpkg-deb"

dpkg-deb --build "${output_dir}" "${current_dir}/thirdreality-otbr-agent_${version}.deb"

print_info "构建完成: thirdreality-otbr-agent_${version}.deb"
