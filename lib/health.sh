#!/bin/sh
# Read-only probes and progress records. No settings, network or persistent state access.
# Sourced by update.sh; not a standalone command.

health_clock() { awk '{printf "%.0f", $1}' /proc/uptime; }
health_process_start() {
    awk '{sub(/^.*\) /, ""); print $20}' "/proc/$1/stat" 2>/dev/null
}
health_probe() {
    H_RECORD="$(cat "$HEALTH_FILE" 2>/dev/null)" || {
        echo 'UNHEALTHY: progress record unavailable'; return 1
    }
    if ! printf '%s\n' "$H_RECORD" | awk '
        NR != 1 || NF != 4 {exit 1}
        {for (i=1; i<=3; i++) if ($i !~ /^(0|[1-9][0-9]*)$/ || length($i)>12) exit 1}
        $4 !~ /^[0-9a-f-]+$/ || length($4)!=36 {exit 1}
        END {if (NR != 1) exit 1}
    '; then
        echo 'UNHEALTHY: invalid progress record'; return 1
    fi
    read -r H_PID H_START H_DEADLINE H_BOOT <<EOF
$H_RECORD
EOF
    if [ "$H_BOOT" != "$(cat /proc/sys/kernel/random/boot_id)" ] || [ "$H_PID" -eq 0 ] || ! kill -0 "$H_PID" 2>/dev/null ||
       [ "$(health_process_start "$H_PID")" != "$H_START" ]; then
        echo 'UNHEALTHY: updater process unavailable'; return 1
    fi
    H_NOW="$(health_clock)" || return 1
    if [ "$H_NOW" -gt "$H_DEADLINE" ]; then
        echo 'UNHEALTHY: updater progress overdue'; return 1
    fi
    echo 'HEALTHY: updater progressing or waiting'
}
# Budget for the next operation, plus a 120-second scheduling/storage margin.
health_progress() {
    [ "$HEALTH_ENABLED" -eq 1 ] || return 0
    H_UNTIL=$(($(health_clock) + $1 + 120))
    H_TMP="$(mktemp "${HEALTH_FILE}.XXXXXX")" ||
        fatal "[HEALTH] WRITE_FAILED; check temporary storage"
    if ! printf '%s %s %s %s\n' "$$" "$HEALTH_START" "$H_UNTIL" "$HEALTH_BOOT" > "$H_TMP" ||
       ! mv -f "$H_TMP" "$HEALTH_FILE"; then
        rm -f "$H_TMP"
        fatal "[HEALTH] WRITE_FAILED; check temporary storage"
    fi
}
recovery_status() {
    R_RECORD="$(cat "$HEALTH_FILE" 2>/dev/null)" || { echo OTHER; return; }
    R_RESULT=0
    R_OUTPUT="$(health_probe)" || R_RESULT=$?
    [ "$R_RECORD" = "$(cat "$HEALTH_FILE" 2>/dev/null)" ] || { echo OTHER; return; }
    R_TOKEN="$(printf '%s\n' "$R_RECORD" | awk 'NR==1 && NF==4 && $1==1 {print $4 "_" $2}')"
    R_CURRENT="$(cat /proc/sys/kernel/random/boot_id)_$(health_process_start 1)"
    [ "$R_TOKEN" = "$R_CURRENT" ] || { echo OTHER; return; }
    case "$R_RESULT:$R_OUTPUT" in
        "0:HEALTHY: updater progressing or waiting") echo "HEALTHY ${R_TOKEN}_$(printf '%s\n' "$R_RECORD" | awk '{print $3}')" ;;
        "1:UNHEALTHY: updater progress overdue") echo "OVERDUE ${R_TOKEN}_$(printf '%s\n' "$R_RECORD" | awk '{print $3}')" ;;
        *) echo OTHER ;;
    esac
}
