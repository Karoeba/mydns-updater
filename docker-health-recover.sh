#!/bin/sh
# Optional Docker host adapter. A timer/task calls --once.
set -u
umask 077
TARGET="${MYDNS_RECOVERY_CONTAINER:-mydns-updater}"
DIR="${MYDNS_RECOVERY_DIR:-/var/lib/mydns-updater-docker-recovery}"
DOCKER="${MYDNS_DOCKER_BIN:-$(command -v docker 2>/dev/null)}"
log() { printf '%s [%s] [DOCKER_RECOVERY] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$1" "$2"; }
fatal() { log ERROR "$1"; exit 1; }
case "${1:-}" in --once|--status|--reset) ;; *) fatal 'use --once, --status or --reset' ;; esac
case "$DIR" in /*) ;; *) fatal 'state directory must be absolute' ;; esac
case "$DOCKER" in /*) ;; *) fatal 'Docker command must be absolute' ;; esac
case "$TARGET" in ""|*[!a-zA-Z0-9_.-]*) fatal 'invalid container name' ;; esac
[ -d "$DIR" ] || fatal 'state directory unavailable'
for tool in flock timeout awk date mktemp; do
    command -v "$tool" >/dev/null 2>&1 || fatal 'required command unavailable'
done
[ -x "$DOCKER" ] || fatal 'Docker command unavailable'
exec 9>"$DIR/lock" || fatal 'cannot open lock'
flock -n 9 || exit 0
STATE="$DIR/status"; TEMP=""
trap '[ -z "$TEMP" ] || rm -f "$TEMP"' 0
trap 'exit 1' INT TERM
if [ "$1" = --reset ]; then
    rm -f "$STATE" || fatal 'cannot reset state'
    log INFO 'RESET; recovery history cleared; container was not started'
    exit 0
fi
NOW="$(date +%s)" || fatal 'clock unavailable'
case "$NOW" in ""|*[!0-9]*) fatal 'invalid clock' ;; esac
BOOT="$(cat /proc/sys/kernel/random/boot_id)" || fatal 'boot identity unavailable'
SAVED_BOOT="$BOOT"; GEN=none; COUNT=0; PENDING=0; BLOCKED=0; LAST="$NOW"
T1=0; T2=0; T3=0; SAMPLE=0
if [ -e "$STATE" ]; then
    if ! awk '
        NR!=1 || NF!=10 {exit 1}
        $1 !~ /^[a-zA-Z0-9-]+$/ || length($1)>64 {exit 1}
        $2!="none" && ($2 !~ /^[a-zA-Z0-9_-]+$/ || length($2)>160) {exit 1}
        $3 !~ /^[0-3]$/ || $4 !~ /^[01]$/ || $5 !~ /^[01]$/ {exit 1}
        {for(i=6;i<=10;i++) if($i !~ /^(0|[1-9][0-9]*)$/ || length($i)>10) exit 1}
        $6<$7 || $7<$8 || $8<$9 || $10>$6 {exit 1}
        END {if(NR!=1) exit 1}' "$STATE"; then
        fatal 'invalid recovery state; inspect logs and reset manually'
    fi
    read -r SAVED_BOOT GEN COUNT PENDING BLOCKED LAST T1 T2 T3 SAMPLE < "$STATE"
fi
if [ "$1" = --status ]; then
    log INFO "STATUS; container=$TARGET consecutive=$COUNT pending=$PENDING blocked=$BLOCKED last_attempt=$T1"
    exit 0
fi
save() {
    TEMP="$(mktemp "$DIR/status.XXXXXX")" || fatal 'cannot create state'
    printf '%s %s %s %s %s %s %s %s %s %s\n' \
        "$BOOT" "$GEN" "$COUNT" "$PENDING" "$BLOCKED" "$NOW" "$T1" "$T2" "$T3" "$SAMPLE" > "$TEMP" &&
        mv -f "$TEMP" "$STATE" || fatal 'cannot save state'
    TEMP=""
}
if [ "$NOW" -lt "$LAST" ]; then
    if [ $((LAST-NOW)) -gt 60 ] && [ "$BLOCKED" -eq 0 ]; then
        BLOCKED=1
        log ERROR 'BLOCKED; reason=CLOCK_MOVED_BACKWARD; inspect clock and reset manually'
    fi
    NOW="$LAST"
fi
[ "$SAVED_BOOT" = "$BOOT" ] || { GEN=none; COUNT=0; SAMPLE=0; }
docker_cmd() { timeout -k 1 5 "$DOCKER" --host unix:///var/run/docker.sock "$@"; }
snapshot() {
    SNAP="$(docker_cmd inspect --format '{{.Id}} {{.State.Status}} {{.State.Paused}} {{.HostConfig.RestartPolicy.Name}} {{.State.StartedAt}}' "$1" 2>/dev/null)" || return 1
    printf '%s\n' "$SNAP" | awk '
        NR!=1 || NF!=5 {exit 1}
        $1 !~ /^[0-9a-f]+$/ || length($1)!=64 {exit 1}
        $5 !~ /^[0-9TZ:.-]+$/ {exit 1}
        END {if(NR!=1) exit 1}' || return 1
    read -r CID RUNNING PAUSED POLICY STARTED <<EOF
$SNAP
EOF
    [ "$RUNNING" = running ] && [ "$PAUSED" = false ] || return 2
    [ "$POLICY" = unless-stopped ] || return 3
}
snapshot "$TARGET"; status=$?
if [ "$status" -ne 0 ]; then
    COUNT=0; SAMPLE=0; save
    [ "$status" -ne 1 ] || fatal 'cannot inspect container; check Docker and container name'
    [ "$status" -ne 3 ] || fatal 'restart policy must be unless-stopped'
    exit 0
fi
BEFORE="$SNAP"; ID="$CID"
if ! docker_cmd exec "$ID" grep -Fqx '# MYDNS_DOCKER_RECOVERY_PROTOCOL=1' /app/update.sh >/dev/null 2>&1; then
    COUNT=0; SAMPLE=0; save; fatal 'updater recovery protocol unavailable; install v1.9.0 or later'
fi
OUTPUT="$(docker_cmd exec "$ID" sh /app/update.sh --docker-recovery-status 2>/dev/null)" || {
    COUNT=0; SAMPLE=0; save; fatal 'probe failed or timed out; no recovery requested'
}
snapshot "$ID"; status=$?
if [ "$status" -ne 0 ] || [ "$SNAP" != "$BEFORE" ]; then COUNT=0; SAMPLE=0; save; exit 0; fi
if ! printf '%s\n' "$OUTPUT" | awk '
    NR!=1 {exit 1}
    $0=="OTHER" {next}
    NF!=2 || ($1!="HEALTHY" && $1!="OVERDUE") {exit 1}
    {if(split($2,a,"_")!=3 || a[1]!~/^[0-9a-f-]+$/ || length(a[1])!=36 ||
        a[2]!~/^(0|[1-9][0-9]*)$/ || length(a[2])>12 || a[3]!~/^(0|[1-9][0-9]*)$/ || length(a[3])>12) exit 1}
    END {if(NR!=1) exit 1}'; then
    COUNT=0; SAMPLE=0; save; fatal 'unrecognized probe result; no recovery requested'
fi
if [ "$OUTPUT" = OTHER ]; then COUNT=0; SAMPLE=0; save; exit 0; fi
read -r HEALTH TOKEN <<EOF
$OUTPUT
EOF
CURRENT_GEN="${ID}_${TOKEN}"
if [ "$GEN" != "$CURRENT_GEN" ]; then GEN="$CURRENT_GEN"; COUNT=0; SAMPLE=0; fi
if [ "$HEALTH" = HEALTHY ]; then
    COUNT=0; SAMPLE=0
    if [ "$PENDING" -eq 1 ]; then
        PENDING=0; save
        log INFO "RECOVERED; container=$TARGET; healthy probe confirmed after attempt"
    else save; fi
    exit 0
fi
# Fresh probes only; do not recount Docker's cached health history.
if [ "$SAMPLE" -gt 0 ] && [ $((NOW-SAMPLE)) -lt 30 ]; then save; exit 0; fi
if [ "$SAMPLE" -gt 0 ] && [ $((NOW-SAMPLE)) -gt 180 ]; then COUNT=0; fi
SAMPLE="$NOW"
[ "$COUNT" -ge 3 ] || COUNT=$((COUNT+1))
save
[ "$COUNT" -eq 3 ] && [ "$BLOCKED" -eq 0 ] || exit 0
USED=0
for stamp in "$T1" "$T2" "$T3"; do
    if [ "$stamp" -gt 0 ] && [ $((NOW-stamp)) -lt 3600 ]; then USED=$((USED+1)); fi
done
if [ "$USED" -ge 3 ]; then
    BLOCKED=1; save
    log ERROR "BLOCKED; container=$TARGET; reason=RESTART_LIMIT; three attempts in one hour; inspect logs and reset manually"
    exit 0
fi
[ "$T1" -eq 0 ] || [ $((NOW-T1)) -ge 600 ] || exit 0
snapshot "$ID"; status=$?
[ "$status" -eq 0 ] && [ "$SNAP" = "$BEFORE" ] || exit 0
T3="$T2"; T2="$T1"; T1="$NOW"; PENDING=1; COUNT=0
save
log WARN "RESTART_ATTEMPT; container=$TARGET; reason=PROGRESS_OVERDUE; attempts_in_hour=$((USED+1))/3"
# Recheck generation and progress inside the same container before signalling.
if docker_cmd exec "$ID" sh /app/update.sh --docker-recovery-request "$TOKEN" >/dev/null 2>&1; then
    log INFO 'RESTART_REQUESTED; waiting for healthy probe'
else
    log WARN 'RESTART_REQUEST_UNCONFIRMED; attempt counted; next probe checks recovery'
fi
