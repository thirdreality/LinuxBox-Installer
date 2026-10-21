#!/bin/bash
# =============================================================================
# build.sh - ThirdReality OTBR Agent deb packaging script
#
# Target version: ot-br-posix v2026.10.0 (commit cb4bdae2, Thread 1.4, OTBR_MDNS=openthread)
#
# Main differences from the pre-v2026.07.0 layout:
#   - Build flow: setup -> bootstrap + cmake-build
#   - mDNS: external mDNSResponder -> built in, no mdnsd/libdns_sd/libnss_mdns
#   - Dropped: otbr-nat44 (NAT64 is built in), mdns init.d, dbus conf, nss_mdns.conf
#   - Dropped: otbr-agent-init.sh (ExecStartPre now runs the firewall script)
#   - CMAKE_INSTALL_PREFIX=/usr -> same paths as the old layout
#   - Web GUI: WEB_GUI=1/OTBR_WEB=ON, frontend built with the system nodejs/npm
#     (bootstrap only apt-installs npm when it is missing; this host uses NodeSource v24)
#
# v2026.07.0 -> v2026.10.0 notes:
#   - Upstream added an opt-in in-process nftables firewall backend
#     (-DOTBR_NFTABLES, Linux-only) and a pf backend (-DOTBR_PF, macOS-only).
#     We keep BOTH OFF and stay on our own otbr-firewall.sh (ipset/ip6tables),
#     so the firewall behaviour is unchanged.
#   - Even with both backends off, the build now always installs two marker
#     files, /usr/share/otbr/{nftables-backend,pf-backend}, which the legacy
#     firewall scripts read to decide who owns the rules. They are listed in
#     STAGED_FILES below so the manifest check stays honest.
#   - Frontend gained an npm dependency (qrcode-generator) and now also copies
#     package-lock.json; nothing to do here, npm install covers it.
# =============================================================================

set -euo pipefail

current_dir=$(pwd)
output_dir="${current_dir}/output"
# Landing directory for `ninja install`. This used to install straight into the
# build host's real /usr and then copy the files back out of the root filesystem
# (that cp list was originally "observed" from the openthread project's install).
# That had three consequences:
#   1. Building mutated the build host -- this machine is also the gateway, so it
#      swapped binaries under running services, and those files bypassed dpkg,
#      leaving dpkg's md5sums out of sync with the disk;
#   2. Once the deb had been installed, /usr/lib/systemd/system/otbr-*.service
#      could be either what cmake had just installed or a leftover from the
#      previous deb; the copy could not tell them apart and failed silently;
#   3. When upstream changed the install layout, the hardcoded cp list did not
#      follow, silently dropping files that only broke on the device.
# Now DESTDIR installs into this staging directory and files are collected from
# staging against a manifest, so the build host's /usr is never touched and the
# manifest can be checked against what was actually installed.
staging_dir="${current_dir}/staging"

COMMIT="cb4bdae242b22287cded07ae3aa10347c2d16d9b"   # tag v2026.10.0
SRC_DIR="${current_dir}/ot-br-posix"
# npm mirror (the web gui frontend's npm install uses a local mirror; the default
# registry times out from here)
NPM_REGISTRY="${NPM_REGISTRY:-https://mirrors.tencent.com/npm/}"
HA_ADDONS_RAW="https://raw.githubusercontent.com/home-assistant/addons/master/openthread_border_router"

REBUILD=false
CLEAN=false

print_info()  { echo -e "\e[1;34m[BUILD] INFO:\e[0m $1"; }
print_error() { echo -e "\e[1;31m[BUILD] ERROR:\e[0m $1"; }
print_step()  { echo -e "\e[1;32m[BUILD] ===== $1 =====\e[0m"; }

# =============================================================================
# OOM protection + temporarily stopping unrelated memory-heavy services during
# the build (including the running otbr-agent/otbr-web).
# The logic lives in deb_repo/build_common.sh (tr_* prefix) so it is shared
# instead of duplicated across packages.
# Toggles: TR_SKIP_SWAP=1 / TR_KEEP_SERVICES=1 / TR_SWAP_TARGET_MIB=N
# =============================================================================
source "$(dirname "$(readlink -f "$0")")/../build_common.sh"
TR_SWAPFILE="${current_dir}/.build-swap"

print_info "Usage: build.sh [--rebuild] [--clean]"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --rebuild) REBUILD=true ;;
        --clean)   CLEAN=true ;;
        *) print_error "Unknown argument: $1"; exit 1 ;;
    esac
    shift
done

version=$(grep '^Version:' "${current_dir}/DEBIAN/control" | awk '{print $2}')
print_info "Version: ${version}  Commit: ${COMMIT}"

# =============================================================================
# --clean: uninstall and clean up
# =============================================================================
otbr_uninstall() {
    echo "Stopping and disabling services..."
    # Stop the hubv3 master switch first (PartOf stops the agent, which triggers the
    # firewall teardown, and web follows), then each one as a fallback
    for svc in hubv3-otbr-agent otbr-web otbr-agent; do
        systemctl stop    "${svc}" 2>/dev/null || true
        systemctl disable "${svc}" 2>/dev/null || true
    done
    killall otbr-web otbr-agent 2>/dev/null || true

    # Fallback firewall teardown (in case ExecStopPost did not run)
    [ -x /usr/lib/thirdreality/otbr-firewall.sh ] && /usr/lib/thirdreality/otbr-firewall.sh teardown 2>/dev/null || true

    # Remove drop-ins
    rm -f /etc/systemd/system/otbr-agent.service.d/firewall.conf
    rm -f /etc/systemd/system/otbr-web.service.d/ordering.conf
    rmdir /etc/systemd/system/otbr-agent.service.d 2>/dev/null || true
    rmdir /etc/systemd/system/otbr-web.service.d 2>/dev/null || true

    systemctl daemon-reload

    # Routing table
    sed -i.bak '/88[[:space:]]\+openthread/d' /etc/iproute2/rt_tables

    # sysctl
    rm -f /etc/sysctl.d/60-otbr-accept-ra.conf
    rm -f /etc/sysctl.d/60-otbr-ip-forward.conf
    sysctl -p /etc/sysctl.conf || true

    # Binaries & data. Package manager first: if the deb was installed, purge it
    # instead of hand-deleting files dpkg owns -- otherwise dpkg still believes the
    # package is installed while the files are gone, and the USB installer will then
    # consider the same version "already up to date" and skip it, so it cannot be
    # repaired. Hand-deletion is only for the legacy case where the old build.sh had
    # ninja write directly into /usr outside of dpkg's control.
    if dpkg -l 2>/dev/null | grep -q "^ii[[:space:]]*thirdreality-otbr-agent"; then
        echo "thirdreality-otbr-agent is dpkg-managed, using apt-get purge"
        apt-get purge -y thirdreality-otbr-agent || \
            echo "Warning: purge failed, package files kept (not hand-deleted, to keep dpkg state and disk in sync)"
    else
        rm -f /usr/sbin/otbr-agent /usr/sbin/otbr-web /usr/sbin/ot-ctl
        rm -rf /usr/share/otbr-web
        # Upstream firewall-backend markers (v2026.10.0 and later)
        rm -f /usr/share/otbr/nftables-backend /usr/share/otbr/pf-backend
        rmdir /usr/share/otbr 2>/dev/null || true
        # Only remove this package's own three scripts. NEVER `rm -rf
        # /usr/lib/thirdreality`: that directory also holds hubv3-usb-sync.sh,
        # post-fix-zigbee2mqtt.sh, resetupwifi.sh, hubv3-generate-ota-indexes.sh,
        # conf/, archives_zigbee2mqtt/ and more, most of which belong to no deb
        # (they ship in the image), so deleting them cannot even be undone by
        # reinstalling the package.
        rm -f /usr/lib/thirdreality/hubv3-otbr-agent.sh \
              /usr/lib/thirdreality/otbr_database \
              /usr/lib/thirdreality/otbr-firewall.sh
        # The directory itself is always kept (not even an rmdir): it is a shared
        # landing spot for several packages and the image, it is not clear who
        # created it or who should reclaim it, and leaving an empty directory costs
        # far less than deleting it by mistake.
    fi
    rm -rf /var/lib/thread

    echo "Cleanup complete."
}

if [[ "$CLEAN" == true ]]; then
    rm -rf "${output_dir}" "${staging_dir}" "${current_dir}"/*.deb "${SRC_DIR}"
    otbr_uninstall
    exit 0
fi

if [[ "$REBUILD" == true ]]; then
    print_info "Rebuilding..."
    rm -rf "${output_dir}" "${staging_dir}" "${SRC_DIR}"
fi

# =============================================================================
# Step 1: prepare the output directory structure
# =============================================================================
print_step "Step 1: prepare directories"

mkdir -p "${output_dir}"
rm -rf "${output_dir}/DEBIAN"
cp -R "${current_dir}/DEBIAN" "${output_dir}/"

# Target directories (matching the /usr prefix)
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
# Step 2: download the HA config file
# =============================================================================
print_step "Step 2: download HA attachment"

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

# Record the commit in control
dirty_id=$(git describe --dirty --always)
commit_id=$(git log -1 --format=%H)
print_info "dirty-id: ${dirty_id}  commit: ${commit_id}"
echo "dirty-id: ${dirty_id}" >> "${output_dir}/DEBIAN/control"
echo "commit: ${commit_id}"  >> "${output_dir}/DEBIAN/control"

cd "${current_dir}"

# =============================================================================
# Step 4: Bootstrap (install build dependencies)
# =============================================================================
print_step "Step 4: Bootstrap"

# The Web GUI frontend (AngularJS/d3) pulls its dependencies via `npm install`
# during the cmake stage. We use the system nodejs/npm (rather than letting
# bootstrap apt-install an older version): bootstrap only apt-installs nodejs
# and npm when WEB_GUI is on AND npm is missing, so an existing system node/npm
# is reused.
if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    print_info "Using system nodejs: $(node --version) / npm $(npm --version)"
else
    print_error "No nodejs/npm found on this system, but the web gui needs them. Install nodejs (with npm) first, then rebuild."
    exit 1
fi
# Point the frontend's npm install at a local mirror to avoid default registry timeouts
export npm_config_registry="${NPM_REGISTRY}"
print_info "npm registry: $(npm config get registry)"

cd "${SRC_DIR}"
BORDER_ROUTING=1 BACKBONE_ROUTER=1 PLATFORM=debian RELEASE=1 \
WEB_GUI=1 REST_API=1 DOCKER=1 OTBR_MDNS=openthread \
./script/bootstrap

# Remove libsystemd-dev to avoid linking against it unnecessarily
apt-get purge -y libsystemd-dev 2>/dev/null || true
cd "${current_dir}"

# =============================================================================
# Step 5: copy the HA config.h, then cmake-build + ninja install
# =============================================================================
print_step "Step 5: cmake-build (PREFIX=/usr)"

# Before compiling: stop unrelated memory-heavy services (restored on exit), then
# provision temporary swap if needed, to avoid OOM
tr_build_guard_start

CONFIG_H_DEST="${SRC_DIR}/third_party/openthread/repo/openthread-core-ha-config-posix.h"
cp "${HA_CONFIG_H}" "${CONFIG_H_DEST}"

# beta(1.4) needs no patches

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
    -DOTBR_NFTABLES=OFF \
    -DOTBR_PF=OFF \
    "-DOT_PROJECT_CONFIG=${CONFIG_H_DEST}"

cd "${SRC_DIR}/build/otbr"
# DESTDIR installs into staging (CMAKE_INSTALL_PREFIX=/usr, so things land in
# ${staging_dir}/usr/...), leaving the build host's real /usr untouched. Staging is
# wiped first each time so leftovers from a previous round are not mistaken for
# this round's output.
rm -rf "${staging_dir}"
mkdir -p "${staging_dir}"
DESTDIR="${staging_dir}" ninja install

# Normalise staging to usrmerge layout. The systemd unit dir comes from
# `pkg-config --variable=systemdsystemunitdir systemd`, which reports
# /lib/systemd/system, so DESTDIR lands the units in staging/lib/... On the real
# system /lib is a symlink to usr/lib so both spellings are the same file, but
# inside staging they are two distinct directories and the manifest's
# usr/lib/... paths would not exist.
if [ -d "${staging_dir}/lib" ] && [ ! -L "${staging_dir}/lib" ]; then
    mkdir -p "${staging_dir}/usr/lib"
    cp -a "${staging_dir}/lib/." "${staging_dir}/usr/lib/"
    rm -rf "${staging_dir}/lib"
fi

cd "${current_dir}"

# =============================================================================
# Step 6: collect the files to package
# =============================================================================
print_step "Step 6: collect files"

# Collected from staging, no longer copied out of the build host's root filesystem.
# The manifest is still explicit (packaged content must stay controlled), but it can
# now be checked both ways against what install actually produced.
# Upstream artifacts (ninja install into ${staging_dir})
STAGED_FILES=(
    usr/sbin/otbr-agent
    usr/sbin/otbr-web
    usr/sbin/ot-ctl
    usr/lib/systemd/system/otbr-agent.service
    usr/lib/systemd/system/otbr-web.service
    # Firewall-backend markers (new in v2026.10.0). Installed unconditionally and
    # contain 0 for us, since both OTBR_NFTABLES and OTBR_PF are OFF; the legacy
    # firewall scripts read them to confirm they still own the rules. Packaged so
    # that a future build with -DOTBR_NFTABLES=ON cannot leave a stale 0 behind.
    usr/share/otbr/nftables-backend
    usr/share/otbr/pf-backend
)
STAGED_DIRS=(
    usr/share/otbr-web
)

# Forward check: everything in the manifest must really have been installed. With the
# old copy-from-/usr approach, a file left behind by the previous deb would be copied
# just the same, so a missing install went unnoticed; now a missing file aborts.
missing=0
for f in "${STAGED_FILES[@]}"; do
    if [[ ! -f "${staging_dir}/${f}" ]]; then
        print_error "missing install artifact: ${f}"
        missing=1
    fi
done
for d in "${STAGED_DIRS[@]}"; do
    if [[ ! -d "${staging_dir}/${d}" ]]; then
        print_error "missing install artifact: ${d}/"
        missing=1
    fi
done
if (( missing )); then
    print_error "collection manifest does not match the install result; the upstream install layout may have changed, aborting build"
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

# Reverse check: an executable or unit in staging that is not in the manifest (for
# example upstream adding a required shared library or service) means the manifest
# needs updating. Warn only, do not abort, but list them explicitly instead of
# silently dropping them.
# usr/share/otbr-web is taken as a whole directory, so its static assets need no
# per-file comparison.
while read -r extra; do
    rel="${extra#"${staging_dir}"/}"
    case " ${STAGED_FILES[*]} " in
        *" ${rel} "*) continue ;;
    esac
    if [[ "${rel}" == usr/share/otbr-web/* ]]; then
        continue
    fi
    print_error "note: install produced a file outside the manifest; it was not packaged, please confirm whether it is needed: ${rel}"
done < <(find "${staging_dir}" -type f \( -perm -u+x -o -name '*.service' \) 2>/dev/null)

# --- ThirdReality-specific scripts ---
cp "${current_dir}/prebuild/hubv3-otbr-agent.sh"      "${output_dir}/usr/lib/thirdreality/"
cp "${current_dir}/prebuild/hubv3-otbr-agent.service"  "${output_dir}/usr/lib/systemd/system/"
cp "${current_dir}/prebuild/otbr_database"             "${output_dir}/usr/lib/thirdreality/"
chmod +x "${output_dir}/usr/lib/thirdreality/hubv3-otbr-agent.sh"
chmod +x "${output_dir}/usr/lib/thirdreality/otbr_database"

# --- Firewall script (builds/tears down ip6tables/ipset/NAT64, replacing the old
#     init.d otbr-firewall) ---
cp "${current_dir}/prebuild/otbr-firewall.sh" "${output_dir}/usr/lib/thirdreality/otbr-firewall.sh"
chmod +x "${output_dir}/usr/lib/thirdreality/otbr-firewall.sh"

# --- otbr-agent drop-in: build the firewall on start, tear it down on stop;
#     governed by the hubv3 master switch, and brings up web ---
cat > "${output_dir}/etc/systemd/system/otbr-agent.service.d/firewall.conf" << 'EOF'
[Unit]
# We build with -DOTBR_DBUS=OFF, so the agent does not need dbus; clear the hard
# dbus dependency hardcoded in the upstream template (an empty assignment resets
# the list), otherwise devices without dbus fail to start on Requires=dbus.socket.
Requires=
# Governed by the hubv3-otbr-agent master switch: stopping/restarting hubv3 stops
# and restarts this service with it
PartOf=hubv3-otbr-agent.service
# Starting otbr-agent also brings up the web UI
Wants=otbr-web.service

[Service]
# Build and tear down the firewall in pairs on every start, so rules cannot accumulate
ExecStartPre=/usr/lib/thirdreality/otbr-firewall.sh setup
ExecStopPost=/usr/lib/thirdreality/otbr-firewall.sh teardown
EOF

# --- otbr-web drop-in: tie it to the otbr-agent lifecycle (web follows when the
#     agent stops or restarts) ---
cat > "${output_dir}/etc/systemd/system/otbr-web.service.d/ordering.conf" << 'EOF'
[Unit]
After=otbr-agent.service
BindsTo=otbr-agent.service
EOF

# --- env config file (same path as the old layout: /etc/default/otbr-agent) ---
cp "${current_dir}/prebuild/otbr-agent" "${output_dir}/etc/default/otbr-agent"

# --- otbr-web env: custom web GUI port (avoiding the usual 80) and listen address ---
cp "${current_dir}/prebuild/otbr-web" "${output_dir}/etc/default/otbr-web"

# --- sysctl: enable IPv6 forwarding and RA ---
cat > "${output_dir}/etc/sysctl.d/60-otbr-ip-forward.conf" << 'EOF'
net.ipv6.conf.all.forwarding=1
net.ipv4.ip_forward=1
net.core.optmem_max=65536
EOF

cat > "${output_dir}/etc/sysctl.d/60-otbr-accept-ra.conf" << 'EOF'
net.ipv6.conf.wlan0.accept_ra=2
net.ipv6.conf.wlan0.accept_ra_rt_info_max_plen=64
EOF

# --- Load kernel modules automatically at boot ---
cat > "${output_dir}/etc/modules-load.d/otbr.conf" << 'EOF'
ip6table_filter
ip6_tables
xt_set
EOF

# =============================================================================
# Step 7: list the produced files
# =============================================================================
print_step "Step 7: output files"
find "${output_dir}" -type f | grep -v "^${output_dir}/DEBIAN" | sort

# =============================================================================
# Step 8: build the deb
# =============================================================================
print_step "Step 8: dpkg-deb"

dpkg-deb --build "${output_dir}" "${current_dir}/otbr-agent_${version}.deb"

print_info "Build complete: otbr-agent_${version}.deb"
