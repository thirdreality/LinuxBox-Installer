#!/bin/bash
# Build thirdreality-matter2mqtt: ThirdReality matterjs-server fork (matter-server + native
# MQTT bridge, no Home Assistant). Installed from the fork's release tarball -- the old
# "official npm package + MQTT patches" approach is retired; the bridge lives in the fork
# (packages/mqtt-bridge, enabled via --mqtt-url). BLE commissioning via a standalone
# matter-ble-proxy venv (bleak/BlueZ, coexists with bluetoothd) using --ble-proxy mode.
# Node comes from the system (>=22.13); mosquitto from the OS/z2m.

current_dir=$(pwd)
output_dir="${current_dir}/output"
matter2mqtt_path="/opt/matter2mqtt"
matter_server_entry="${matter2mqtt_path}/node_modules/matter-server/dist/esm/MatterServer.js"
commissioning_flow="${matter2mqtt_path}/node_modules/@matter/protocol/dist/esm/peer/ControllerCommissioningFlow.js"
ble_venv="${matter2mqtt_path}/ble-venv"
PY314="/usr/local/python3/bin/python3"   # from thirdreality-python3 (>=3.12 for matter-ble-proxy)

# OOM guard + stop unrelated services during install (npm/pip pull a lot; ~2GiB box).
source "$(dirname "$(readlink -f "$0")")/../build_common.sh"

REBUILD=false
CLEAN=false
SCRIPT="M2M"
print_info()  { echo -e "\e[1;34m[${SCRIPT}] INFO:\e[0m $1"; }
print_error() { echo -e "\e[1;31m[${SCRIPT}] ERROR:\e[0m $1"; }

# Idempotent patch: only apply when the sentinel is absent, so an in-place npm reinstall
# (which overwrites patched files) gets the patch re-applied on every build.
tr_apply_patch_idempotent() {
    local target="$1" patchfile="$2" sentinel="$3"
    if [ ! -f "$patchfile" ]; then print_info "patch not found, skip: $patchfile"; return 0; fi
    if [ ! -f "$target" ];    then print_error "patch target not found, skip: $target"; return 0; fi
    if [ -n "$sentinel" ] && grep -q -- "$sentinel" "$target"; then
        print_info "patch already applied (found '$sentinel'), skip: $(basename "$patchfile")"; return 0
    fi
    if patch "$target" < "$patchfile"; then print_info "patch applied: $(basename "$patchfile")"
    else print_error "patch FAILED: $(basename "$patchfile") -> $target"; fi
}

print_info "Build script for ThirdReality matter2mqtt (matter.js server + MQTT bridge, no HA)"
print_info "Usage: build.sh [--rebuild] [--clean]"
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --rebuild) REBUILD=true ;;
        --clean)   CLEAN=true ;;
        *) print_info "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

# ThirdReality fork release (matter.js 0.17.9 base + mqtt-bridge). The "0.17.9 commissioning
# regression" suspected earlier was disproved: the root cause was device firmware dropping BLE
# ~5s after addOrUpdateWiFiNetwork, handled by matterjs_commissioning_timing.patch below.
export MATTER_SERVER_VERSION="1.4.0-tr.1"
export MATTER_BLE_PROXY_VERSION="0.7.1"
# Tarball source: local file wins (offline/dev), else GitHub Release download + sha256.
TARBALL="matter-server-${MATTER_SERVER_VERSION}.tgz"
TARBALL_FILE="${TARBALL_FILE:-${current_dir}/prebuild/${TARBALL}}"
TARBALL_BASE="${TARBALL_BASE:-https://github.com/thirdreality/matterjs-server/releases/download}"
NPM_REGISTRY_URL="${NPM_REGISTRY_URL:-}"
PIP_INDEX_URL="${PIP_INDEX_URL:-}"

version=$(grep '^Version:' ${current_dir}/prebuild/DEBIAN/control | awk '{print $2}')
print_info "Version: $version"

if [[ "$CLEAN" == true ]]; then
    rm -rf "${output_dir}" >/dev/null 2>&1
    systemctl stop    matter-ble-proxy.service matter2mqtt.service 2>/dev/null || true
    systemctl disable matter-ble-proxy.service matter2mqtt.service 2>/dev/null || true
    rm -f  /lib/systemd/system/matter2mqtt.service /lib/systemd/system/matter-ble-proxy.service \
           /usr/lib/systemd/system/matter2mqtt.service /usr/lib/systemd/system/matter-ble-proxy.service
    rm -rf ${matter2mqtt_path}
    systemctl daemon-reload 2>/dev/null || true
    print_info "clean finished"; exit 0
fi

mkdir -p "${output_dir}"
cp ${current_dir}/prebuild/DEBIAN ${output_dir}/ -R

# OOM guard: on low memory adds temp swap + stops unrelated services (auto-restored on exit);
# called unconditionally so the repackage-only path is protected too. No-op if RAM is ok.
tr_build_guard_start

# matter2mqtt moved from /srv to /opt (zigbee2mqtt-style layout); clear a stale old install
if [ -d /srv/matter2mqtt ]; then
    print_info "Removing legacy /srv/matter2mqtt (program dir moved to /opt; data in /var/lib is kept)"
    rm -rf /srv/matter2mqtt
fi

if [[ "$REBUILD" == true ]]; then
    rm -rf ${matter2mqtt_path}
fi

# ---------------------------------------------------------------------------
# [1] Install the ThirdReality matter-server fork from the release tarball.
#     Skip only when the entry exists AND the installed version matches (a stale
#     official install with a different version must be replaced).
# ---------------------------------------------------------------------------
installed_ver=""
if [ -e "${matter_server_entry}" ]; then
    installed_ver=$(node -p "require('${matter2mqtt_path}/node_modules/matter-server/package.json').version" 2>/dev/null)
fi
if [ "$installed_ver" != "${MATTER_SERVER_VERSION}" ]; then
    print_info "[1] Installing matter-server ${MATTER_SERVER_VERSION} (found: ${installed_ver:-none}) into ${matter2mqtt_path} ..."
    if ! command -v node >/dev/null 2>&1; then
        print_error "Node.js not found; matter-server requires >= 22.13 (armbian ships 24.x)."; exit 1
    fi
    NODE_VERSION=$(node --version | sed -E 's/^v//')
    if tr_ver_lt "$NODE_VERSION" "22.13.0"; then
        print_error "Node.js ${NODE_VERSION} too old; matter-server requires >= 22.13. abort"; exit 1
    fi
    print_info "Using Node.js $(node --version) / npm $(npm --version 2>/dev/null || echo '?')"

    # Resolve the tarball: local file wins, else download from GitHub Release + verify sha256
    if [ -f "${TARBALL_FILE}" ]; then
        print_info "Using local tarball: ${TARBALL_FILE}"
        tarball_path="${TARBALL_FILE}"
    else
        print_info "Downloading ${TARBALL} from ${TARBALL_BASE} ..."
        curl -fL -o "/tmp/${TARBALL}" "${TARBALL_BASE}/v${MATTER_SERVER_VERSION}/${TARBALL}" || {
            print_error "Failed to download ${TARBALL}"; exit 1; }
        curl -fL -o "/tmp/${TARBALL}.sha256" "${TARBALL_BASE}/v${MATTER_SERVER_VERSION}/${TARBALL}.sha256" || {
            print_error "Failed to download ${TARBALL}.sha256"; exit 1; }
        (cd /tmp && sha256sum -c "${TARBALL}.sha256") || { print_error "sha256 mismatch for ${TARBALL}"; exit 1; }
        tarball_path="/tmp/${TARBALL}"
    fi

    # A stale install (e.g. the retired official-npm layout) is replaced wholesale
    rm -rf "${matter2mqtt_path}/node_modules" "${matter2mqtt_path}/package.json" \
           "${matter2mqtt_path}/package-lock.json" "${matter2mqtt_path}/tr-commission-bridge.mjs"
    mkdir -p ${matter2mqtt_path}
    cd ${matter2mqtt_path}

    # native build deps (matter-server pulls a noble binding even though we use --ble-proxy).
    # best-effort (no-op if present / offline).
    if command -v apt-get >/dev/null 2>&1; then
        apt-get install -y --no-install-recommends make gcc g++ libbluetooth-dev libudev-dev >/dev/null 2>&1 || \
            print_info "Warning: native build deps not installed (may be present / offline)"
    fi

    NPM_ARGS=(--omit=dev --foreground-scripts --no-audit --no-fund)
    [ -n "$NPM_REGISTRY_URL" ] && { print_info "npm registry: ${NPM_REGISTRY_URL}"; NPM_ARGS+=(--registry "$NPM_REGISTRY_URL"); }

    npm install "${NPM_ARGS[@]}" "${tarball_path}" || {
        print_error "Failed to install matter-server from ${tarball_path}"; exit 1; }
    [ -e "${matter_server_entry}" ] || { print_error "entry not found after install: ${matter_server_entry}"; exit 1; }

    npm cache clean --force >/dev/null 2>&1 || true
    find "${matter2mqtt_path}/node_modules" -type d -name "cjs" -path "*/@matter/*" -exec rm -rf {} + 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# [1b] Guard assertions (run on every build, outside any skip logic).
# ---------------------------------------------------------------------------
installed_ver=$(node -p "require('${matter2mqtt_path}/node_modules/matter-server/package.json').version" 2>/dev/null)
if [[ "$installed_ver" != *"-tr."* ]]; then
    print_error "Installed matter-server ${installed_ver} is NOT the ThirdReality build, abort"; exit 1
fi
if ! node "${matter_server_entry}" --help 2>/dev/null | grep -q "mqtt-url"; then
    print_error "matter-server has no MQTT bridge support, wrong package installed, abort"; exit 1
fi
print_info "matter-server ${installed_ver} verified (MQTT bridge present)"

# ---------------------------------------------------------------------------
# [2] Commissioning timing patch (idempotent, every build).
#     Fragile device firmware stops serving GATT ~5s after addOrUpdateWiFiNetwork; skip the
#     redundant networks read so connectNetwork fits inside the window (NetworkID == SSID
#     for WiFi per the Matter spec). Root cause verified on ThirdReality night lights.
# ---------------------------------------------------------------------------
tr_apply_patch_idempotent "${commissioning_flow}" \
    "${current_dir}/prebuild/matterjs_commissioning_timing.patch" "TR-PATCH"

# ---------------------------------------------------------------------------
# [2b] BLE proxy venv (bleak/BlueZ). Lightweight: aiohttp + bleak + matter-ble-proxy, built
#      with thirdreality-python3 (matter-ble-proxy requires Python >=3.12). No Home Assistant.
# ---------------------------------------------------------------------------
if [ ! -x "${ble_venv}/bin/matter-ble-proxy" ]; then
    if [ -x "$PY314" ]; then
        print_info "[2b] Creating BLE proxy venv (matter-ble-proxy==${MATTER_BLE_PROXY_VERSION}) ..."
        "$PY314" -m venv "${ble_venv}"
        PIP_ARGS=(--no-cache-dir --disable-pip-version-check)
        if [ -n "$PIP_INDEX_URL" ]; then
            print_info "pip index: ${PIP_INDEX_URL}"; PIP_ARGS+=(--index-url "$PIP_INDEX_URL")
        else
            # System pip.conf may point at a mirror (e.g. tuna) that does NOT carry
            # matter-ble-proxy; default to official PyPI. Set PIP_INDEX_URL for a LAN mirror.
            print_info "pip index: https://pypi.org/simple/ (official; mirror lacks matter-ble-proxy)"
            PIP_ARGS+=(--index-url https://pypi.org/simple/)
        fi
        "${ble_venv}/bin/pip" install "${PIP_ARGS[@]}" "matter-ble-proxy==${MATTER_BLE_PROXY_VERSION}" || \
            print_error "Failed to install matter-ble-proxy; BLE commissioning will not work"
    else
        print_error "thirdreality-python3 not found at ${PY314}; cannot build BLE proxy venv"
    fi
fi

# ---------------------------------------------------------------------------
# [2c] Patch matter-ble-proxy: acquire the negotiated ATT MTU. bleak's BlueZ backend
#      leaves mtu_size at the 23 default unless acquired, which makes the proxy report
#      MTU=23 -> matter.js fragments BTP into 20-byte segments -> the networkCommissioning
#      read after addOrUpdateWiFiNetwork needs many GATT writes and stalls/drops BLE on
#      low-MTU peripherals (commissioning then fails: connectNetwork never sent).
#      Verified: MTU 23->247, that read 5.6s->0.24s, night light commissions.
#      Idempotent (sentinel=_acquire_mtu) since a venv reinstall overwrites client.py.
# ---------------------------------------------------------------------------
ble_client_py=$(ls -d ${ble_venv}/lib/python*/site-packages/matter_ble_proxy/client.py 2>/dev/null | head -1)
if [ -n "$ble_client_py" ] && [ -f "$ble_client_py" ]; then
    tr_apply_patch_idempotent "$ble_client_py" "${current_dir}/prebuild/matter_ble_proxy_mtu.patch" "_acquire_mtu"
else
    print_info "matter-ble-proxy client.py not found; skip MTU patch"
fi

# ---------------------------------------------------------------------------
# [3] Install units on the build host (for local testing) + package the deb.
# ---------------------------------------------------------------------------
cp ${current_dir}/prebuild/matter2mqtt.service      /lib/systemd/system/matter2mqtt.service
cp ${current_dir}/prebuild/matter-ble-proxy.service /lib/systemd/system/matter-ble-proxy.service
systemctl daemon-reload 2>/dev/null || true

print_info "[3] Packaging thirdreality-matter2mqtt_${version}.deb ..."
rm -rf ${output_dir}/opt ${output_dir}/srv ${output_dir}/lib
mkdir -p ${output_dir}/opt ${output_dir}/lib/systemd/system
chmod 755 ${output_dir}/opt
cp ${matter2mqtt_path} ${output_dir}/opt/ -R
cp /lib/systemd/system/matter2mqtt.service      ${output_dir}/lib/systemd/system/
cp /lib/systemd/system/matter-ble-proxy.service ${output_dir}/lib/systemd/system/

chmod 0755 ${output_dir}/DEBIAN/preinst ${output_dir}/DEBIAN/postinst \
           ${output_dir}/DEBIAN/prerm   ${output_dir}/DEBIAN/postrm 2>/dev/null || true
find "${output_dir}" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "${output_dir}" -type f -name "*.pyc" -delete 2>/dev/null || true

dpkg-deb --build ${output_dir} ${current_dir}/thirdreality-matter2mqtt_${version}.deb
print_info "Build thirdreality-matter2mqtt_${version}.deb finished"
