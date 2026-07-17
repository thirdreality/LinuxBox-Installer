# =============================================================================
# build_common.sh - ThirdReality deb 构建通用辅助函数（OOM 保护 + 服务停/恢复）
#
# 这台设备内存很小(~2GiB)，编译 Python(PGO)、安装 HA 大量 wheel、pnpm 构建
# zigbee2mqtt 时峰值内存都可能触发 OOM。本文件提供两组能力，供各 build.sh
# 在进入重内存步骤前调用：
#   1) 临时 swap：内存不足时按需创建 swap 文件，构建结束(含失败/中断)自动清理。
#   2) 临时停服务：编译期间停掉与本次构建无关的重内存服务，结束后自动恢复。
#
# 用法（在 build.sh 中）：
#   source "$(dirname "$(readlink -f "$0")")/../build_common.sh"
#   TR_SWAPFILE="${current_dir}/.build-swap"                # 可选，默认见下
#   TR_MEM_SERVICES=(home-assistant.service matter-server.service \
#                    zigbee2mqtt.service mosquitto.service music-assistant.service)
#   tr_build_guard_start   # 停无关服务 + 按需加 swap + 注册退出清理 trap
#
# 环境变量开关：
#   TR_SKIP_SWAP=1        跳过 swap 自动配置
#   TR_KEEP_SERVICES=1    编译期间保留所有服务（不停）
#   TR_SWAP_TARGET_MIB=N  目标"可用内存(RAM+swap)"下限，默认 4096 MiB
# =============================================================================

# 防止重复 source
[[ -n "${TR_BUILD_COMMON_LOADED:-}" ]] && return 0
TR_BUILD_COMMON_LOADED=1

tr_ci() { echo -e "\e[1;34m[COMMON] INFO:\e[0m $1"; }
tr_ce() { echo -e "\e[1;31m[COMMON] ERROR:\e[0m $1"; }

# 版本比较（按版本号语义，非字典序）。tr_ver_lt A B：A < B 为真。
# 例：tr_ver_lt 3.9.0 3.13.0 => 真；字典序会误判为假。
tr_ver_lt() {
    [ "$1" = "$2" ] && return 1
    [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$1" ]
}

# 默认值（调用方可在 source 后覆盖）
: "${TR_SWAPFILE:=$(pwd)/.build-swap}"
TR_SWAP_CREATED=false
TR_STOPPED_SERVICES=()
# 默认要临时停止的重内存服务；调用方可用 TR_MEM_SERVICES=(...) 覆盖
if [[ -z "${TR_MEM_SERVICES+x}" ]]; then
    TR_MEM_SERVICES=(home-assistant.service matter-server.service \
                     zigbee2mqtt.service mosquitto.service music-assistant.service)
fi

tr_cleanup_swap() {
    if [[ "${TR_SWAP_CREATED}" == true ]]; then
        tr_ci "清理临时 swap: ${TR_SWAPFILE}"
        swapoff "${TR_SWAPFILE}" 2>/dev/null || true
        rm -f "${TR_SWAPFILE}"
        TR_SWAP_CREATED=false
    fi
}

tr_restart_stopped_services() {
    if (( ${#TR_STOPPED_SERVICES[@]} > 0 )); then
        # 逆序恢复，尽量还原依赖顺序
        local i
        for (( i=${#TR_STOPPED_SERVICES[@]}-1 ; i>=0 ; i-- )); do
            local svc="${TR_STOPPED_SERVICES[$i]}"
            tr_ci "恢复服务: ${svc}"
            systemctl start "${svc}" 2>/dev/null || \
                tr_ce "恢复 ${svc} 失败，请手动: systemctl start ${svc}"
        done
        TR_STOPPED_SERVICES=()
    fi
}

# 退出(成功/失败/中断)时：先 swapoff(此时服务仍停、内存最空)，再恢复服务
tr_cleanup() {
    tr_cleanup_swap
    tr_restart_stopped_services
}

tr_stop_unrelated_services() {
    [[ "${TR_KEEP_SERVICES:-0}" == "1" ]] && { tr_ci "TR_KEEP_SERVICES=1，编译期间保留所有服务"; return 0; }
    [[ "$(id -u)" -eq 0 ]] || { tr_ci "非 root，跳过临时停止服务"; return 0; }
    command -v systemctl >/dev/null 2>&1 || return 0
    local svc
    for svc in "${TR_MEM_SERVICES[@]}"; do
        if systemctl is-active --quiet "${svc}" 2>/dev/null; then
            tr_ci "编译期间临时停止无关服务: ${svc}"
            if systemctl stop "${svc}" 2>/dev/null; then
                TR_STOPPED_SERVICES+=("${svc}")
            fi
        fi
    done
    (( ${#TR_STOPPED_SERVICES[@]} == 0 )) && tr_ci "无可停止的无关服务" || true
}

tr_ensure_swap() {
    [[ "${TR_SKIP_SWAP:-0}" == "1" ]] && { tr_ci "TR_SKIP_SWAP=1，跳过 swap 检查"; return 0; }
    [[ "$(id -u)" -eq 0 ]] || { tr_ci "非 root，跳过 swap 自动配置"; return 0; }

    local want_mib="${TR_SWAP_TARGET_MIB:-4096}"
    local mem_avail swap_free have need_mib disk_free_mib
    mem_avail=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
    swap_free=$(free -m | awk '/Swap:/{print $4}')
    have=$(( mem_avail + swap_free ))
    tr_ci "内存检查: 可用RAM ${mem_avail}MiB + 空闲swap ${swap_free}MiB = ${have}MiB (目标 ${want_mib}MiB)"
    (( have >= want_mib )) && { tr_ci "内存充足，无需临时 swap"; return 0; }

    need_mib=$(( want_mib - have ))
    local swap_dir
    swap_dir=$(dirname "${TR_SWAPFILE}")
    disk_free_mib=$(df -Pm "${swap_dir}" | awk 'NR==2{print $4}')
    if (( disk_free_mib < need_mib + 2048 )); then
        tr_ce "磁盘剩余 ${disk_free_mib}MiB，不足以创建 ${need_mib}MiB swap；继续构建但可能 OOM。"
        return 0
    fi

    tr_ci "内存偏低，创建临时 swap ${need_mib}MiB: ${TR_SWAPFILE}"
    rm -f "${TR_SWAPFILE}"
    if fallocate -l "${need_mib}M" "${TR_SWAPFILE}" 2>/dev/null || \
       dd if=/dev/zero of="${TR_SWAPFILE}" bs=1M count="${need_mib}" status=none; then
        chmod 600 "${TR_SWAPFILE}"
        mkswap "${TR_SWAPFILE}" >/dev/null 2>&1
        if swapon "${TR_SWAPFILE}" 2>/dev/null; then
            TR_SWAP_CREATED=true
            tr_ci "临时 swap 已启用（构建结束自动清理）"
        else
            tr_ce "swapon 失败，继续（构建可能内存吃紧）"
            rm -f "${TR_SWAPFILE}"
        fi
    else
        tr_ce "创建 swap 文件失败，继续"
    fi
}

# 一次性入口：注册清理 trap → 停无关服务 → 按需加 swap
tr_build_guard_start() {
    trap tr_cleanup EXIT
    tr_stop_unrelated_services
    tr_ensure_swap
}
