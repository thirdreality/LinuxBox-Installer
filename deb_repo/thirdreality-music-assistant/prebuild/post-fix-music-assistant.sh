#!/bin/bash
#
# Post-installation script for ThirdReality Music Assistant
# Purpose: Install/upgrade bundled snapserver package after Music Assistant
# Version: 2.0.0
#

set -e
shopt -s nullglob

# Constants
DEFAULT_APT_CACHE="/var/cache/apt/archives"
THIRDREALITY_ARCHIVES="/lib/thirdreality/archives_music_assistant"
SNAPSERVER_PATTERN="snapserver_*.deb"
LOG_FILE="/var/log/thirdreality-music-assistant-install.log"

# Helper functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

copy_snapserver_to_cache() {
    local pkg_files=("$THIRDREALITY_ARCHIVES"/${SNAPSERVER_PATTERN})
    if [ ${#pkg_files[@]} -eq 0 ]; then
        log "ERROR: snapserver package not found in ${THIRDREALITY_ARCHIVES}"
        return 1
    fi

    mkdir -p "$DEFAULT_APT_CACHE"
    log "Cleaning old snapserver packages from apt cache"
    rm -f "$DEFAULT_APT_CACHE"/${SNAPSERVER_PATTERN} || true

    local pkg_file="${pkg_files[0]}"
    log "Copy snapserver package to apt cache: $(basename "$pkg_file")"
    cp -f "$pkg_file" "$DEFAULT_APT_CACHE/"
}

install_or_upgrade_snapserver() {
    local cache_pkgs=("$DEFAULT_APT_CACHE"/${SNAPSERVER_PATTERN})
    if [ ${#cache_pkgs[@]} -eq 0 ]; then
        log "ERROR: snapserver package not found in apt cache"
        return 1
    fi

    local pkg_file="${cache_pkgs[0]}"
    local new_ver
    new_ver=$(dpkg-deb -f "$pkg_file" Version)
    local cur_ver
    cur_ver=$(dpkg-query -W -f='${Version}' snapserver 2>/dev/null || true)

    if [ -z "$cur_ver" ]; then
        log "No installed snapserver detected; installing version $new_ver"
        if ! dpkg -i "$pkg_file" 2>&1 | tee -a "$LOG_FILE"; then
            log "dpkg install failed; trying apt-get -f and retrying"
            apt-get install -f -y 2>&1 | tee -a "$LOG_FILE"
            dpkg -i "$pkg_file" 2>&1 | tee -a "$LOG_FILE"
        fi
    elif dpkg --compare-versions "$cur_ver" lt "$new_ver"; then
        log "Installed snapserver $cur_ver is older than target $new_ver; upgrading"
        apt-get remove --purge -y snapserver 2>&1 | tee -a "$LOG_FILE" || true
        if ! dpkg -i "$pkg_file" 2>&1 | tee -a "$LOG_FILE"; then
            log "dpkg install failed; trying apt-get -f and retrying"
            apt-get install -f -y 2>&1 | tee -a "$LOG_FILE"
            dpkg -i "$pkg_file" 2>&1 | tee -a "$LOG_FILE"
        fi
    else
        log "System snapserver version $cur_ver is not older than $new_ver; skip install"
        return 0
    fi

    local installed_ver
    installed_ver=$(dpkg-query -W -f='${Version}' snapserver 2>/dev/null || echo "未知")
    log "snapserver install/upgrade complete, current version: $installed_ver"
}

# Main execution
if [ ! -d "$THIRDREALITY_ARCHIVES" ]; then
    log "ERROR: package directory not found: $THIRDREALITY_ARCHIVES"
    exit 1
fi

copy_snapserver_to_cache
install_or_upgrade_snapserver

exit 0