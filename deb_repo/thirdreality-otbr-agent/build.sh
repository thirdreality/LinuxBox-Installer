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
# `ninja install` 的落地目录。以前直接 install 进构建机的真实 /usr，再从根文件系统 cp 回来
# （这套 cp 清单当年是照着 openthread 项目的安装过程"观察"出来的）。那样做有三个后果：
#   1. 构建即改动构建机 —— 这台机器同时是网关，等于给运行中的服务换二进制，而且这些文件
#      绕过了 dpkg，dpkg 的 md5sums 会与磁盘失配；
#   2. deb 装过一次后，/usr/lib/systemd/system/otbr-*.service 既可能是 cmake 刚装的、也可能
#      是上一版 deb 留下的，cp 出来分辨不出，出错也不报错；
#   3. 上游改了安装布局，硬编码的 cp 清单不会跟着变，静默漏文件，装到设备上才炸。
# 改为 DESTDIR 安装到这个 staging 目录，再从 staging 按清单收集，构建机的 /usr 不再被碰，
# 并且可以校验清单与 staging 的实际内容是否还对得上。
staging_dir="${current_dir}/staging"

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
# OOM 保护 + 编译期临时停无关重内存服务（含运行中的 otbr-agent/otbr-web）。
# 逻辑抽到仓库根 deb_repo/build_common.sh 复用（tr_* 前缀），避免与其它包重复。
# 开关: TR_SKIP_SWAP=1 / TR_KEEP_SERVICES=1 / TR_SWAP_TARGET_MIB=N
# =============================================================================
source "$(dirname "$(readlink -f "$0")")/../build_common.sh"
TR_SWAPFILE="${current_dir}/.build-swap"

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
    # 先停总闸 hubv3（连带停 agent→触发防火墙 teardown、web 跟随），再逐个兜底
    for svc in hubv3-otbr-agent otbr-web otbr-agent; do
        systemctl stop    "${svc}" 2>/dev/null || true
        systemctl disable "${svc}" 2>/dev/null || true
    done
    killall otbr-web otbr-agent 2>/dev/null || true

    # 兜底拆防火墙（万一 ExecStopPost 没跑）
    [ -x /usr/lib/thirdreality/otbr-firewall.sh ] && /usr/lib/thirdreality/otbr-firewall.sh teardown 2>/dev/null || true

    # 清理 drop-in
    rm -f /etc/systemd/system/otbr-agent.service.d/firewall.conf
    rm -f /etc/systemd/system/otbr-web.service.d/ordering.conf
    rmdir /etc/systemd/system/otbr-agent.service.d 2>/dev/null || true
    rmdir /etc/systemd/system/otbr-web.service.d 2>/dev/null || true

    systemctl daemon-reload

    # 路由表
    sed -i.bak '/88[[:space:]]\+openthread/d' /etc/iproute2/rt_tables

    # sysctl
    rm -f /etc/sysctl.d/60-otbr-accept-ra.conf
    rm -f /etc/sysctl.d/60-otbr-ip-forward.conf
    sysctl -p /etc/sysctl.conf || true

    # 二进制 & 数据。包管理优先：装过 deb 就走 purge，别手工删 dpkg 拥有的文件 ——
    # 否则 dpkg 仍认为包装着而文件已消失，之后同版本 deb 会被 U 盘安装器判为"已最新"跳过，
    # 反而修不回来。手工删只用于旧版 build.sh 那种 ninja 直接写进 /usr、不受 dpkg 管理的遗留。
    if dpkg -l 2>/dev/null | grep -q "^ii[[:space:]]*thirdreality-otbr-agent"; then
        echo "thirdreality-otbr-agent 已由 dpkg 管理，走 apt-get purge"
        apt-get purge -y thirdreality-otbr-agent || \
            echo "警告: purge 失败，包文件保留（不手工删，以免 dpkg 状态与磁盘不一致）"
    else
        rm -f /usr/sbin/otbr-agent /usr/sbin/otbr-web /usr/sbin/ot-ctl
        rm -rf /usr/share/otbr-web
        # 只删本包自己的三个脚本。绝不 `rm -rf /usr/lib/thirdreality`：那个目录里还放着
        # hubv3-usb-sync.sh / post-fix-zigbee2mqtt.sh / resetupwifi.sh /
        # hubv3-generate-ota-indexes.sh / conf/ / archives_zigbee2mqtt/ 等，多数不属于任何
        # deb（镜像直接放的），删掉连重装包都恢复不了。
        rm -f /usr/lib/thirdreality/hubv3-otbr-agent.sh \
              /usr/lib/thirdreality/otbr_database \
              /usr/lib/thirdreality/otbr-firewall.sh
        # 目录本身一律留着（连 rmdir 都不做）：它是多个包和镜像的共用落脚点，
        # 由谁创建、谁该回收并不清晰，留一个空目录的代价远小于误删。
    fi
    rm -rf /var/lib/thread

    echo "清理完成。"
}

if [[ "$CLEAN" == true ]]; then
    rm -rf "${output_dir}" "${staging_dir}" "${current_dir}"/*.deb "${SRC_DIR}"
    otbr_uninstall
    exit 0
fi

if [[ "$REBUILD" == true ]]; then
    print_info "重新构建..."
    rm -rf "${output_dir}" "${staging_dir}" "${SRC_DIR}"
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
mkdir -p "${output_dir}/etc/sysctl.d"
mkdir -p "${output_dir}/etc/modules-load.d"
mkdir -p "${output_dir}/etc/systemd/system/otbr-agent.service.d"
mkdir -p "${output_dir}/etc/systemd/system/otbr-web.service.d"

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
tr_build_guard_start

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
    -DOT_RCP_RESTORATION_MAX_COUNT=2 \
    "-DOT_PROJECT_CONFIG=${CONFIG_H_DEST}"

cd "${SRC_DIR}/build/otbr"
# DESTDIR 安装到 staging（CMAKE_INSTALL_PREFIX=/usr，所以落点是 ${staging_dir}/usr/...），
# 构建机真实的 /usr 不再被改动。每次先清空 staging，避免上一轮的残留被当成本轮产物。
rm -rf "${staging_dir}"
mkdir -p "${staging_dir}"
DESTDIR="${staging_dir}" ninja install

cd "${current_dir}"

# =============================================================================
# Step 6: 打包文件收集
# =============================================================================
print_step "Step 6: 收集文件"

# 从 staging 收集，不再从构建机的根文件系统 cp。清单依然是显式的（打包内容要可控），
# 但现在能对着 install 的真实结果做双向校验。
# 上游产物（ninja install 到 ${staging_dir}）
STAGED_FILES=(
    usr/sbin/otbr-agent
    usr/sbin/otbr-web
    usr/sbin/ot-ctl
    usr/lib/systemd/system/otbr-agent.service
    usr/lib/systemd/system/otbr-web.service
)
STAGED_DIRS=(
    usr/share/otbr-web
)

# 正向校验：清单里的东西必须真的被 install 出来。以前从 /usr cp，文件是上一版 deb 留下的
# 也照样 cp 得到，漏装看不出来；现在缺了就直接中止。
missing=0
for f in "${STAGED_FILES[@]}"; do
    if [[ ! -f "${staging_dir}/${f}" ]]; then
        print_error "install 产物缺失: ${f}"
        missing=1
    fi
done
for d in "${STAGED_DIRS[@]}"; do
    if [[ ! -d "${staging_dir}/${d}" ]]; then
        print_error "install 产物缺失: ${d}/"
        missing=1
    fi
done
if (( missing )); then
    print_error "收集清单与 install 结果不符，上游安装布局可能已变更，中止构建"
    exit 1
fi

for f in "${STAGED_FILES[@]}"; do
    mkdir -p "${output_dir}/$(dirname "${f}")"
    cp "${staging_dir}/${f}" "${output_dir}/${f}"
done
for d in "${STAGED_DIRS[@]}"; do
    mkdir -p "${output_dir}/$(dirname "${d}")"
    cp -R "${staging_dir}/${d}" "${output_dir}/$(dirname "${d}")/"
done

# 反向校验：staging 里出现清单之外的可执行文件或 unit（例如上游新增了一个必需的共享库或
# 服务），说明清单该更新了。只告警不中止，但会明确列出来，不再静默漏掉。
# usr/share/otbr-web 整目录收走，其中的静态资源无需逐个比对。
while read -r extra; do
    rel="${extra#"${staging_dir}"/}"
    case " ${STAGED_FILES[*]} " in
        *" ${rel} "*) continue ;;
    esac
    if [[ "${rel}" == usr/share/otbr-web/* ]]; then
        continue
    fi
    print_error "注意: install 产生了清单外的文件，未打包，请确认是否需要: ${rel}"
done < <(find "${staging_dir}" -type f \( -perm -u+x -o -name '*.service' \) 2>/dev/null)

# --- ThirdReality 专属脚本 ---
cp "${current_dir}/prebuild/hubv3-otbr-agent.sh"      "${output_dir}/usr/lib/thirdreality/"
cp "${current_dir}/prebuild/hubv3-otbr-agent.service"  "${output_dir}/usr/lib/systemd/system/"
cp "${current_dir}/prebuild/otbr_database"             "${output_dir}/usr/lib/thirdreality/"
chmod +x "${output_dir}/usr/lib/thirdreality/hubv3-otbr-agent.sh"
chmod +x "${output_dir}/usr/lib/thirdreality/otbr_database"

# --- 防火墙脚本（建/拆 ip6tables/ipset/NAT64，替代旧 init.d otbr-firewall）---
cp "${current_dir}/prebuild/otbr-firewall.sh" "${output_dir}/usr/lib/thirdreality/otbr-firewall.sh"
chmod +x "${output_dir}/usr/lib/thirdreality/otbr-firewall.sh"

# --- otbr-agent drop-in：启动建防火墙、停止拆防火墙；受 hubv3 总闸管控，带起 web ---
cat > "${output_dir}/etc/systemd/system/otbr-agent.service.d/firewall.conf" << 'EOF'
[Unit]
# 我们用 -DOTBR_DBUS=OFF 编译，agent 不需要 dbus；清掉上游模板写死的 dbus 硬依赖
# （空赋值会重置该依赖列表），否则无 dbus 的设备会因 Requires=dbus.socket 起不来。
Requires=
# 受 hubv3-otbr-agent 总闸管控：停/重启 hubv3 时连带停/重启本服务
PartOf=hubv3-otbr-agent.service
# 起 otbr-agent 时连带把 web UI 拉起来
Wants=otbr-web.service

[Service]
# 每次启动成对建/拆防火墙，避免规则残留叠加
ExecStartPre=/usr/lib/thirdreality/otbr-firewall.sh setup
ExecStopPost=/usr/lib/thirdreality/otbr-firewall.sh teardown
EOF

# --- otbr-web drop-in：绑定 otbr-agent 生命周期（agent 停/重启 → web 跟随）---
cat > "${output_dir}/etc/systemd/system/otbr-web.service.d/ordering.conf" << 'EOF'
[Unit]
After=otbr-agent.service
BindsTo=otbr-agent.service
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

dpkg-deb --build "${output_dir}" "${current_dir}/otbr-agent_${version}.deb"

print_info "构建完成: otbr-agent_${version}.deb"
