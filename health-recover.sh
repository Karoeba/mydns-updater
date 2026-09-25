#!/bin/sh
# Optional systemd adapter. Install as root, not writable by the updater.
set -u
umask 077
TARGET="${MYDNS_RECOVERY_SERVICE:-mydns-updater.service}"
UPDATER="${MYDNS_UPDATER:-/usr/local/lib/mydns-updater/update.sh}"
PROBE_USER="${MYDNS_RECOVERY_USER:-mydns-updater}"
HEALTH="${MYDNS_HEALTH_FILE:-/run/mydns-updater/health}"
DIR="${MYDNS_RECOVERY_DIR:-/var/lib/mydns-updater-recovery}"
log() { echo "[$1] [HEALTH_RECOVERY] $2"; }
fatal() { log ERROR "$1"; exit 1; }
case "${1:-}" in ""|--reset) ;; *) fatal 'invalid arguments' ;; esac
case "$DIR" in /*) ;; *) fatal 'state directory must be absolute' ;; esac
case "$UPDATER" in /*) ;; *) fatal 'updater path must be absolute' ;; esac
case "$HEALTH" in /*) ;; *) fatal 'health path must be absolute' ;; esac
case "$TARGET" in ""|*[!a-zA-Z0-9_.@-]*) fatal 'invalid service name' ;; esac
[ -d "$DIR" ] || fatal 'state directory unavailable'
for tool in flock timeout runuser systemctl; do
    command -v "$tool" >/dev/null 2>&1 || fatal 'required command unavailable'
done
exec 9>"$DIR/lock" || fatal 'cannot open lock'
flock -n 9 || exit 0
STATE="$DIR/status"
DIAG="$DIR/diagnostic"
TEMP=""
trap '[ -z "$TEMP" ] || rm -f "$TEMP"' 0
trap 'exit 1' INT TERM
if [ "${1:-}" = --reset ]; then
    rm -f "$STATE" "$DIAG" || fatal 'cannot reset state'
    log INFO 'RESET; recovery history cleared; service was not started'
    exit 0
fi
NOW="$(date +%s)" || fatal 'clock unavailable'
case "$NOW" in ""|*[!0-9]*) fatal 'invalid clock' ;; esac
BOOT="$(cat /proc/sys/kernel/random/boot_id)" || fatal 'boot identity unavailable'
SAVED_BOOT="$BOOT"; GEN=none; COUNT=0; PENDING=0; BLOCKED=0; LAST="$NOW"
T1=0; T2=0; T3=0
if [ -e "$STATE" ]; then
    if ! awk '
        NR!=1 || NF!=9 {exit 1}
        $1 !~ /^[a-zA-Z0-9-]+$/ || length($1)>64 {exit 1}
        $2!="none" && ($2 !~ /^[0-9a-f]+$/ || length($2)!=32) {exit 1}
        $3 !~ /^[0-3]$/ || $4 !~ /^[01]$/ || $5 !~ /^[01]$/ {exit 1}
        {for(i=6;i<=9;i++) if($i !~ /^[0-9]+$/ || length($i)>10) exit 1}
        $6<$7 || $7<$8 || $8<$9 {exit 1}
        END {if(NR!=1) exit 1}' "$STATE"; then
        fatal 'invalid recovery state; inspect logs and reset manually'
    fi
    read -r SAVED_BOOT GEN COUNT PENDING BLOCKED LAST T1 T2 T3 < "$STATE"
fi
save() {
    TEMP="$(mktemp "$DIR/status.XXXXXX")" || fatal 'cannot create state'
    printf '%s %s %s %s %s %s %s %s %s\n' \
        "$BOOT" "$GEN" "$COUNT" "$PENDING" "$BLOCKED" "$NOW" "$T1" "$T2" "$T3" > "$TEMP" &&
        mv -f "$TEMP" "$STATE" || fatal 'cannot save state'
    TEMP=""
}
# Keep history across service/OS restarts. Clock rollback grants no allowance.
if [ "$NOW" -lt "$LAST" ]; then
    if [ $((LAST-NOW)) -gt 60 ] && [ "$BLOCKED" -eq 0 ]; then
        BLOCKED=1
        log ERROR 'BLOCKED; reason=CLOCK_MOVED_BACKWARD; inspect clock and reset manually'
    fi
    NOW="$LAST"
fi
[ "$SAVED_BOOT" = "$BOOT" ] || { GEN=none; COUNT=0; }
active_generation() {
    ACTIVE="$(timeout -k 1 3 systemctl show "$TARGET" --property=ActiveState --value)" || return 1
    [ "$ACTIVE" = active ] || return 2
    CURRENT_GEN="$(timeout -k 1 3 systemctl show "$TARGET" --property=InvocationID --value)" || return 1
    case "$CURRENT_GEN" in ""|*[!0-9a-f]*) return 1 ;; esac
    [ "${#CURRENT_GEN}" -eq 32 ] || return 1
}
active_generation
status=$?
if [ "$status" -eq 2 ]; then COUNT=0; save; exit 0; fi
[ "$status" -eq 0 ] || fatal 'cannot read target service state'
BEFORE="$CURRENT_GEN"
if [ "$GEN" != "$BEFORE" ]; then GEN="$BEFORE"; COUNT=0; fi
# Separate optional diagnostic file keeps the existing nine-field history compatible.
# Fixed codes only: never persist or log probe output.
D_BOOT="$BOOT"; D_GEN="$BEFORE"; D_SINCE="$NOW"; D_CODE=NONE
if [ -f "$DIAG" ]; then
    if ! awk '
        NR!=1 || NF!=4 {exit 1}
        $1 !~ /^[a-zA-Z0-9-]+$/ || length($1)>64 {exit 1}
        $2 !~ /^[0-9a-f]+$/ || length($2)!=32 {exit 1}
        $3 !~ /^[0-9]+$/ || length($3)>10 {exit 1}
        $4 !~ /^(NONE|RECORD_UNAVAILABLE|RECORD_INVALID|PROCESS_UNAVAILABLE|PROBE_TIMEOUT|PROBE_FAILED|PROBE_UNKNOWN)$/ {exit 1}
        END {if(NR!=1) exit 1}' "$DIAG"; then
        fatal 'invalid diagnostic state; inspect logs and reset manually'
    fi
    read -r D_BOOT D_GEN D_SINCE D_CODE < "$DIAG"
    if [ "$D_BOOT" != "$BOOT" ] || [ "$D_GEN" != "$BEFORE" ]; then
        D_SINCE="$NOW"
    fi
fi
diagnostic_save() {
    TEMP="$(mktemp "$DIR/diagnostic.XXXXXX")" || fatal 'cannot create diagnostic state'
    printf '%s %s %s %s\n' "$BOOT" "$BEFORE" "$D_SINCE" "$D_CODE" > "$TEMP" &&
        mv -f "$TEMP" "$DIAG" || fatal 'cannot save diagnostic state'
    TEMP=""
}
diagnostic_clear() {
    if [ "$D_CODE" != NONE ]; then
        log INFO 'PROBE_RECOVERED; health assessment available again'
    fi
    # Retain generation age so later missing records are not mistaken for startup.
    D_CODE=NONE
    diagnostic_save
}
RESULT=0
# Only service control needs privilege; execute the probe as the updater user.
OUTPUT="$(timeout -k 1 5 runuser -u "$PROBE_USER" -- env MYDNS_HEALTH_FILE="$HEALTH" \
    sh "$UPDATER" --healthcheck 2>/dev/null)" || RESULT=$?
active_generation
status=$?
if [ "$status" -eq 2 ]; then COUNT=0; save; exit 0; fi
[ "$status" -eq 0 ] || fatal 'cannot read target service state'
if [ "$CURRENT_GEN" != "$BEFORE" ]; then GEN="$CURRENT_GEN"; COUNT=0; save; exit 0; fi
if [ "$RESULT" -eq 0 ] && [ "$OUTPUT" = 'HEALTHY: updater progressing or waiting' ]; then
    diagnostic_clear
    COUNT=0
    if [ "$PENDING" -eq 1 ]; then
        PENDING=0; save
        log INFO 'RECOVERED; healthy probe confirmed after recovery attempt'
    else save; fi
    exit 0
fi
if [ "$RESULT" -ne 1 ] || [ "$OUTPUT" != 'UNHEALTHY: updater progress overdue' ]; then
    case "$RESULT:$OUTPUT" in
        '1:UNHEALTHY: progress record unavailable') CODE=RECORD_UNAVAILABLE ;;
        '1:UNHEALTHY: invalid progress record') CODE=RECORD_INVALID ;;
        '1:UNHEALTHY: updater process unavailable') CODE=PROCESS_UNAVAILABLE ;;
        124:*|137:*) CODE=PROBE_TIMEOUT ;;
        0:*|1:*) CODE=PROBE_UNKNOWN ;;
        *) CODE=PROBE_FAILED ;;
    esac
    # Only a missing record gets a startup grace; never grant a restart allowance.
    if [ "$CODE" != RECORD_UNAVAILABLE ] || [ $((NOW-D_SINCE)) -ge 120 ]; then
        if [ "$D_CODE" != "$CODE" ]; then
            log WARN "PROBE_UNAVAILABLE; reason=$CODE; no restart requested"
            D_CODE="$CODE"
        fi
    fi
    diagnostic_save
    COUNT=0; save; exit 0
fi
diagnostic_clear
[ "$COUNT" -ge 3 ] || COUNT=$((COUNT+1))
save
[ "$COUNT" -eq 3 ] && [ "$BLOCKED" -eq 0 ] || exit 0
USED=0
for stamp in "$T1" "$T2" "$T3"; do
    if [ "$stamp" -gt 0 ] && [ $((NOW-stamp)) -lt 3600 ]; then USED=$((USED+1)); fi
done
if [ "$USED" -ge 3 ]; then
    BLOCKED=1; save
    log ERROR 'BLOCKED; reason=RESTART_LIMIT; three attempts in one hour; inspect logs and reset manually'
    exit 0
fi
[ "$T1" -eq 0 ] || [ $((NOW-T1)) -ge 600 ] || exit 0
# Avoid replacing a manual stop/start job; never start an inactive target.
active_generation
status=$?
[ "$status" -eq 0 ] && [ "$CURRENT_GEN" = "$BEFORE" ] || exit 0
T3="$T2"; T2="$T1"; T1="$NOW"; PENDING=1; COUNT=0
# Reserve allowance before dispatch, including failed or uncertain requests.
save
log WARN "RESTART_ATTEMPT; reason=PROGRESS_OVERDUE; attempts_in_hour=$((USED+1))/3"
if timeout -k 1 5 systemctl --no-block --job-mode=fail try-restart "$TARGET" >/dev/null 2>&1; then
    log INFO 'RESTART_REQUESTED; waiting for healthy probe'
else
    log ERROR 'RESTART_REQUEST_FAILED; inspect service logs; attempt counted'
fi
