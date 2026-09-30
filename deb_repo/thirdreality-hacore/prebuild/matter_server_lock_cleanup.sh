#!/bin/sh
# Remove stale matter.js storage locks left behind by an unclean shutdown.
#
# matter.js writes matter.lock + matter.pid into every storage directory and only
# unlinks them on a clean exit, so a power cut / SIGKILL leaves them on disk. Its
# stale detection is just process.kill(pid, 0): after a reboot the recorded pid is
# usually reused by some other boot-time service, so the lock looks alive forever
# and the server dies with [storage-lock] on every start.
#
# We only drop a lock whose owner is provably not a matter-server process, so a
# genuinely running instance keeps its lock.
#
# Usage: matter_server_lock_cleanup.sh <storage-path>

set -u

STORAGE_PATH="${1:-}"
if [ -z "$STORAGE_PATH" ] || [ ! -d "$STORAGE_PATH" ]; then
    exit 0
fi

log() {
    echo "matter_server_lock_cleanup: $*"
}

pid_is_matter_server() {
    pid="$1"
    [ -r "/proc/$pid/cmdline" ] || return 1
    tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q 'MatterServer\.js'
}

find "$STORAGE_PATH" -type f -name 'matter.lock' 2>/dev/null | while IFS= read -r lock; do
    dir=$(dirname "$lock")
    pidfile="$dir/matter.pid"
    pid=""
    if [ -r "$pidfile" ]; then
        pid=$(awk 'NR==1 {print $1}' "$pidfile" 2>/dev/null)
    fi

    case "$pid" in
        ''|*[!0-9]*)
            log "removing lock in $dir (no usable pid file)"
            rm -f "$lock" "$pidfile"
            continue
            ;;
    esac

    if pid_is_matter_server "$pid"; then
        log "keeping lock in $dir (pid $pid is a live matter-server)"
        continue
    fi

    log "removing stale lock in $dir (pid $pid is not a matter-server process)"
    rm -f "$lock" "$pidfile"
done

exit 0
