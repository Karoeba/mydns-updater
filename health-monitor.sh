#!/bin/sh
# One observation per invocation. Scheduling and recovery belong to the caller.
set -u
umask 077
UPDATER="${MYDNS_UPDATER:-/usr/local/lib/mydns-updater/update.sh}"
MONITOR_DIR="${MYDNS_MONITOR_DIR:-/run/mydns-updater-monitor}"
TARGET="${MYDNS_MONITOR_SERVICE:-mydns-updater.service}"
MODE="${1:-}"
fatal() { echo "[ERROR] [HEALTH_MONITOR] $*"; exit 1; }
case "$MODE" in ""|--systemd) ;; *) fatal 'invalid arguments' ;; esac
case "$MONITOR_DIR" in /*) ;; *) fatal 'monitor directory must be absolute' ;; esac
case "$UPDATER" in /*) ;; *) fatal 'updater path must be absolute' ;; esac
[ -d "$MONITOR_DIR" ] || fatal 'monitor directory unavailable'
command -v flock >/dev/null 2>&1 || fatal 'flock unavailable'
command -v timeout >/dev/null 2>&1 || fatal 'timeout unavailable'
exec 9>"$MONITOR_DIR/lock" || fatal 'monitor lock unavailable'
flock -n 9 || exit 0
active_generation() {
    ACTIVE="$(systemctl show "$TARGET" --property=ActiveState --value)" || return 1
    [ "$ACTIVE" = active ] || return 2
    GENERATION="$(systemctl show "$TARGET" --property=InvocationID --value)" || return 1
    case "$GENERATION" in ""|*[!0-9a-f]*) return 1 ;; esac
    [ "${#GENERATION}" -eq 32 ] || return 1
}
if [ "$MODE" = --systemd ]; then
    active_generation
    status=$?
    [ "$status" -ne 2 ] || exit 0
    [ "$status" -eq 0 ] || fatal 'cannot read target service state'
else
    GENERATION="${MYDNS_MONITOR_GENERATION:-manual}"
    case "$GENERATION" in ""|*[!a-zA-Z0-9_-]*) fatal 'invalid generation' ;; esac
    [ "${#GENERATION}" -le 64 ] || fatal 'invalid generation'
fi
BOOT="$(cat /proc/sys/kernel/random/boot_id)" || fatal 'boot identity unavailable'
IDENTITY="$BOOT:$GENERATION"
BEFORE="$IDENTITY"
COUNT=0
PREVIOUS=healthy
STATE="$MONITOR_DIR/status"
if [ -e "$STATE" ]; then
    [ -r "$STATE" ] || fatal 'monitor state unreadable'
    if awk 'NR!=1 || NF!=3 {exit 1}
        $1 !~ /^[a-zA-Z0-9:_-]+$/ || length($1)>101 {exit 1}
        $2 !~ /^[0-3]$/ {exit 1}
        $3!="healthy" && $3!="unhealthy" {exit 1}
        ($2==3 && $3!="unhealthy") || ($2<3 && $3!="healthy") {exit 1}
        END {if(NR!=1) exit 1}' "$STATE"; then
        read -r SAVED COUNT PREVIOUS < "$STATE"
        if [ "$SAVED" != "$IDENTITY" ]; then COUNT=0; PREVIOUS=healthy; fi
    else
        fatal 'invalid monitor state; stop timer and remove status file'
    fi
fi
RESULT=0
OUTPUT="$(timeout -k 1 5 sh "$UPDATER" --healthcheck 2>/dev/null)" || RESULT=$?
# Never count a probe spanning an intentional stop or a new service invocation.
if [ "$MODE" = --systemd ]; then
    active_generation
    status=$?
    [ "$status" -ne 2 ] || exit 0
    [ "$status" -eq 0 ] || fatal 'cannot read target service state'
    [ "$BOOT:$GENERATION" = "$BEFORE" ] || exit 0
fi
REASON=PROBE_FAILED
if [ "$RESULT" -eq 0 ] && [ "$OUTPUT" = 'HEALTHY: updater progressing or waiting' ]; then
    COUNT=0
    CURRENT=healthy
else
    [ "$COUNT" -ge 3 ] || COUNT=$((COUNT+1))
    CURRENT=healthy
    [ "$COUNT" -lt 3 ] || CURRENT=unhealthy
    case "$OUTPUT" in
        'UNHEALTHY: progress record unavailable') REASON=RECORD_UNAVAILABLE ;;
        'UNHEALTHY: invalid progress record') REASON=RECORD_INVALID ;;
        'UNHEALTHY: updater process unavailable') REASON=PROCESS_UNAVAILABLE ;;
        'UNHEALTHY: updater progress overdue') REASON=PROGRESS_OVERDUE ;;
    esac
    [ "$RESULT" -ne 124 ] || REASON=PROBE_TIMEOUT
fi
TEMP="$(mktemp "$MONITOR_DIR/status.XXXXXX")" || fatal 'cannot create monitor state'
trap 'rm -f "$TEMP"' 0
trap 'exit 1' INT TERM
printf '%s %s %s\n' "$IDENTITY" "$COUNT" "$CURRENT" > "$TEMP" &&
    mv -f "$TEMP" "$STATE" || fatal 'cannot save monitor state'
if [ "$CURRENT" = unhealthy ] && [ "$PREVIOUS" != unhealthy ]; then
    echo "[ERROR] [HEALTH_MONITOR] UNHEALTHY; consecutive_failures=3; reason=$REASON; inspect updater logs"
elif [ "$CURRENT" = healthy ] && [ "$PREVIOUS" = unhealthy ]; then
    echo '[INFO] [HEALTH_MONITOR] RECOVERED; updater progressing or waiting'
fi
# A failed probe is a recorded observation, not a failed systemd job.
exit 0
