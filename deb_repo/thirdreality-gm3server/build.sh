#!/bin/bash
# =============================================================================
# build.sh - ThirdReality GM3Server deb packaging script
#
# GM3Server is the device-side server that takes over Home Assistant's
# server-side role. Its source lives OUTSIDE this repo (a sibling GM checkout),
# so this script is given the source tree rather than owning it:
#
#   GM3_SRC=/path/to/gm/src/GM3Server ./build.sh
#
# Default is ../../tmp/gm/src/GM3Server, which is where it sits during
# development. The LocalWeb frontend is expected at $GM3_SRC/../LocalWeb.
#
# Two things this build deliberately does NOT do:
#   - No libdatachannel / P2P. It needs a GitHub fetch plus a heavy native
#     build, and the cloud path it serves still has TLS verification disabled
#     upstream (wsclient.c has an LS_TODO saying so) and a TURN secret
#     committed in plaintext. LAN access and the cloud long-connection work
#     without it.
#   - No npm run inside this script. The frontend must be built first (see
#     below); we only embed the existing dist. That keeps the deb build off the
#     node toolchain, and matches how the upstream cross-compile doc does it.
#
# LS_ENV is forced to staging/online rather than left at its default: with
# LS_ENV=local the compiled-in MQTT host is a developer's machine (10.1.0.14),
# which must never reach a shipped device.
# =============================================================================

set -euo pipefail

current_dir=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
output_dir="${current_dir}/output"

GM3_SRC="${GM3_SRC:-${current_dir}/../../tmp/gm/src/GM3Server}"
LS_ENV="${LS_ENV:-staging}"

print_info()  { echo -e "\e[1;34m[BUILD] INFO:\e[0m $1"; }
print_error() { echo -e "\e[1;31m[BUILD] ERROR:\e[0m $1"; }
print_step()  { echo -e "\e[1;32m[BUILD] ===== $1 =====\e[0m"; }

CLEAN=false
REBUILD=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --rebuild) REBUILD=true ;;
        --clean)   CLEAN=true ;;
        *) print_error "Unknown argument: $1"; exit 1 ;;
    esac
    shift
done

version=$(awk '/^Version:/{print $2}' "${current_dir}/DEBIAN/control")

if [[ "$CLEAN" == true ]]; then
    rm -rf "${output_dir}" "${current_dir}"/*.deb
    print_info "Cleaned."
    exit 0
fi

print_info "Version: ${version}  LS_ENV: ${LS_ENV}"
print_info "Source:  ${GM3_SRC}"

# =============================================================================
# Step 1: check the source tree and the prebuilt frontend
# =============================================================================
print_step "Step 1: check sources"

if [[ ! -f "${GM3_SRC}/CMakeLists.txt" ]]; then
    print_error "GM3Server source not found: ${GM3_SRC}"
    print_error "Pass it explicitly: GM3_SRC=/path/to/GM3Server ./build.sh"
    exit 1
fi

WEB_DIST="${GM3_SRC}/../LocalWeb/dist"
if [[ ! -f "${WEB_DIST}/index.html" ]]; then
    print_error "LocalWeb frontend not built: ${WEB_DIST}/index.html missing."
    print_error "Build it first:  cd ${GM3_SRC}/../LocalWeb && npm install && npx vite build"
    exit 1
fi
print_info "frontend dist: $(du -sh "${WEB_DIST}" | awk '{print $1}')"

for t in cmake gcc python3; do
    command -v "$t" >/dev/null || { print_error "missing build tool: $t"; exit 1; }
done
# The C code includes mosquitto.h and links libssl directly.
[[ -f /usr/include/mosquitto.h ]] || { print_error "missing libmosquitto-dev"; exit 1; }
[[ -f /usr/include/openssl/ssl.h ]] || { print_error "missing libssl-dev"; exit 1; }

# =============================================================================
# Step 2: compile
# =============================================================================
print_step "Step 2: compile (LS_ENV=${LS_ENV})"

BUILD_DIR="${GM3_SRC}/build-deb"
[[ "$REBUILD" == true ]] && rm -rf "${BUILD_DIR}"

# LOCAL_BUILD_WEB=OFF: the dist is already built, cmake only embeds it.
cmake -S "${GM3_SRC}" -B "${BUILD_DIR}" \
    -DLOCAL_BUILD_WEB=OFF \
    -DLOCAL_MQTT=ON \
    -DLS_ENV="${LS_ENV}" \
    -DCMAKE_BUILD_TYPE=Release
cmake --build "${BUILD_DIR}" -j"$(nproc)" --target gm3_server

BIN="${BUILD_DIR}/gm3_server"
[[ -f "$BIN" ]] || { print_error "build produced no binary"; exit 1; }

# >1MB means the real frontend got embedded rather than the placeholder page.
asset_sz=$(wc -c < "${BUILD_DIR}/web_assets_gen.c" 2>/dev/null || echo 0)
if (( asset_sz < 1000000 )); then
    print_error "embedded web assets look like the placeholder page (${asset_sz} bytes)"
    exit 1
fi
print_info "embedded web assets: $((asset_sz/1024)) KB"

# The target is arm64; refuse to ship anything else.
arch=$(readelf -h "$BIN" | awk -F: '/Machine:/{gsub(/^ +/,"",$2); print $2}')
print_info "binary arch: ${arch}"
[[ "$arch" == *"AArch64"* ]] || { print_error "binary is not AArch64 — wrong toolchain?"; exit 1; }

# =============================================================================
# Step 3: lay out the package
# =============================================================================
print_step "Step 3: assemble package"

rm -rf "${output_dir}"
mkdir -p "${output_dir}"/{DEBIAN,usr/bin,usr/lib/systemd/system,etc/default}
cp -R "${current_dir}/DEBIAN/." "${output_dir}/DEBIAN/"
chmod 0755 "${output_dir}/DEBIAN"/{preinst,postinst,prerm}

install -m 0755 "$BIN" "${output_dir}/usr/bin/gm3-server"
strip "${output_dir}/usr/bin/gm3-server" 2>/dev/null || true

install -m 0644 "${current_dir}/prebuild/gm3-server.service" \
                "${output_dir}/usr/lib/systemd/system/gm3-server.service"
# conffile: operators edit this, so dpkg must not clobber it on upgrade.
install -m 0644 "${current_dir}/prebuild/gm3-server" \
                "${output_dir}/etc/default/gm3-server"
echo "/etc/default/gm3-server" > "${output_dir}/DEBIAN/conffiles"

# Record what the binary was actually built from, so a deb can be traced back.
{
    echo "ls-env: ${LS_ENV}"
    if git -C "${GM3_SRC}" rev-parse --git-dir >/dev/null 2>&1; then
        echo "gm3-commit: $(git -C "${GM3_SRC}" log -1 --format=%H 2>/dev/null || echo unknown)"
    fi
} >> "${output_dir}/DEBIAN/control"

# =============================================================================
# Step 4: build the deb
# =============================================================================
print_step "Step 4: dpkg-deb"

find "${output_dir}" -type f | grep -v "^${output_dir}/DEBIAN" | sed "s|${output_dir}|  |"
dpkg-deb --build "${output_dir}" "${current_dir}/gm3server_${version}.deb"
print_info "Build complete: gm3server_${version}.deb"
