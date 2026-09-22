#!/bin/sh
# Defaults, lifecycle, account cycle and main loop. Other modules provide the operations.
# Sourced by update.sh; not a standalone command.

updater_defaults() {
CONFIG_DIR="${MYDNS_CONFIG_DIR:-/config}"
CONFIG="$CONFIG_DIR/mydns.conf"
ACCOUNTS_CONFIG="$CONFIG_DIR/accounts.conf"
DEBUG=0
STATE_DIR="${MYDNS_STATE_DIR:-/state}"
STATE_FILE="$STATE_DIR/state.conf"
DEFAULT_TZ="Asia/Tokyo"
TZ="$DEFAULT_TZ"
export TZ
umask 077

HEALTH_FILE="${MYDNS_HEALTH_FILE:-/tmp/mydns-updater.health}"
HEALTH_ENABLED=0
}
cleanup() {
    if [ -n "$SLEEP_PID" ]; then
        kill "$SLEEP_PID" 2>/dev/null || :
        wait "$SLEEP_PID" 2>/dev/null || :
    fi
    [ "$HEALTH_ENABLED" -ne 1 ] || rm -f "$HEALTH_FILE"
    [ -z "$STATE_TMP" ] || rm -f "$STATE_TMP"
    rm -rf "$WORK_DIR"
}

initialize_runtime() {
# Paths are launch-time options, not values read from the configuration files.
case "$CONFIG_DIR" in /*) ;; *) fatal "[CONFIG] PATH_INVALID; MYDNS_CONFIG_DIR must be absolute" ;; esac
case "$STATE_DIR" in /*) ;; *) fatal "[STATE] PATH_INVALID; MYDNS_STATE_DIR must be absolute" ;; esac

WORK_DIR="$(mktemp -d)" || fatal "[INTERNAL] TEMP_CREATE_FAILED; check temporary storage"
STATE_TMP=""
SLEEP_PID=""
trap cleanup 0
trap 'exit 0' INT TERM

mkdir -p "$STATE_DIR" || fatal "[STATE] DIRECTORY_CREATE_FAILED; check permissions and storage"
}
run_cycle() {
    debug "[CHECK] IPv4 check started"
    get_current_ipv4 || return 0
    debug "[CHECK] IPv4 acquired: $CURRENT_IPV4"
    load_state
    ALL_MATCH=1
    while IFS= read -r SECTION; do
        health_progress 0
        ID="$(get_value "$WORK_DIR/accounts" "$SECTION" ID)"
        PASSWORD="$(get_value "$WORK_DIR/accounts" "$SECTION" PASSWORD)"
        DOMAIN="$(get_value "$WORK_DIR/accounts" "$SECTION" DOMAIN)"
        ACCOUNT_IP="$(cat "$WORK_DIR/ip.$SECTION")"
        LAST_UPDATE="$(cat "$WORK_DIR/time.$SECTION")"
        NOW="$(date +%s)"

        ACCOUNT_TARGET="ACCOUNT $SECTION"
        # Keep credentials private; only sanitized DOMAIN is a display label.
        DISPLAY_DOMAIN="$(printf '%s' "$DOMAIN" | tr -cd 'A-Za-z0-9._-')"
        [ -z "$DISPLAY_DOMAIN" ] || ACCOUNT_TARGET="$ACCOUNT_TARGET: $DISPLAY_DOMAIN"
        track_target "account.$SECTION" "$(printf '%s\n' "$ID" "$PASSWORD" "$DOMAIN")" "$ACCOUNT_TARGET"

        if [ -z "$ID" ] || [ -z "$PASSWORD" ] || [ -z "$DOMAIN" ]; then
            failure "account-config.$SECTION" "$ACCOUNT_TARGET" MISSING_FIELDS error "[$SECTION] MyDNS update: CONFIG ERROR; ID, PASSWORD and DOMAIN are required"
            ALL_MATCH=0
            continue
        fi

        recovered "account-config.$SECTION" "$ACCOUNT_TARGET"
        UPDATE_REASON=""
        if [ "$LAST_UPDATE" -eq 0 ] || [ -z "$ACCOUNT_IP" ]; then
            UPDATE_REASON="account state missing"
        elif [ "$ACCOUNT_IP" != "$CURRENT_IPV4" ]; then
            UPDATE_REASON="IPv4 changed"
        elif [ "$LAST_UPDATE" -gt "$NOW" ]; then
            UPDATE_REASON="future success timestamp"
        elif [ $((NOW - LAST_UPDATE)) -ge "$FORCE_UPDATE_INTERVAL" ]; then
            UPDATE_REASON="force update interval reached"
        fi

        if [ -n "$UPDATE_REASON" ]; then
            debug "[$SECTION] [UPDATE] $UPDATE_REASON"
            notify_mydns
            if [ "$REQUEST_OK" -eq 1 ]; then
                ACCOUNT_IP="$CURRENT_IPV4"
                LAST_UPDATE="$(date +%s)"
                printf '%s\n' "$ACCOUNT_IP" > "$WORK_DIR/ip.$SECTION" || fatal "[INTERNAL] FILE_OPERATION_FAILED; check temporary storage"
                printf '%s\n' "$LAST_UPDATE" > "$WORK_DIR/time.$SECTION" || fatal "[INTERNAL] FILE_OPERATION_FAILED; check temporary storage"
                # Persist each success before moving on to the next account.
                persist_or_exit
                recovered "account.$SECTION" "$ACCOUNT_TARGET"
                log "[INFO] [$ACCOUNT_TARGET] MyDNS update: OK (IPv4=$ACCOUNT_IP)"
            else
                transport_failure "account.$SECTION" "$ACCOUNT_TARGET" "$ERROR_MODE" "MyDNS update: FAILED; next eligible cycle will retry; last_success_epoch=$LAST_UPDATE"
                ALL_MATCH=0
            fi
        else
            if [ -f "$WORK_DIR/diagnostic.account.$SECTION" ]; then
                log "[INFO] [$ACCOUNT_TARGET] NO_UPDATE_REQUIRED; previous failure history cleared without a new notification"
                rm -f "$WORK_DIR/diagnostic.account.$SECTION"
            fi
            debug "[$SECTION] [SKIP] IPv4 unchanged; force update not due"
        fi
        [ "$ACCOUNT_IP" = "$CURRENT_IPV4" ] || ALL_MATCH=0
    done < "$WORK_DIR/sections"

    if [ "$ALL_MATCH" -eq 1 ] && [ "$LAST_IPV4" != "$CURRENT_IPV4" ]; then
        LAST_IPV4="$CURRENT_IPV4"
        log "[IPv4] All accounts synchronized: $LAST_IPV4"
    fi
    persist_or_exit
    recovered state STATE
}

run_forever() {
STARTUP_LOGGED=0
HEALTH_START="$(health_process_start "$$")"
HEALTH_BOOT="$(cat /proc/sys/kernel/random/boot_id)"
HEALTH_ENABLED=1
while true; do
    health_progress 0
    CHECK_INTERVAL=300
    if load_config; then
        finish_config_diagnostics
        if [ "$STARTUP_LOGGED" -eq 0 ]; then
            log "[STARTUP] MyDNS updater v${VERSION} started: TZ=${TZ}, DEBUG=${DEBUG}, CHECK_INTERVAL=${CHECK_INTERVAL}s, FORCE_UPDATE_INTERVAL=${FORCE_UPDATE_INTERVAL}s"
            STARTUP_LOGGED=1
        fi
        run_cycle
    fi
    health_progress "$CHECK_INTERVAL"
    # Waiting on a background child lets TERM interrupt the interval promptly.
    sleep "$CHECK_INTERVAL" &
    SLEEP_PID=$!
    wait "$SLEEP_PID"
    SLEEP_PID=""
done
}
