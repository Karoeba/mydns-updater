#!/bin/sh

VERSION="1.2.0"
CONFIG="/config/mydns.conf"
DEBUG=0
STATE_DIR="/state"
STATE_FILE="$STATE_DIR/state.conf"
DEFAULT_TZ="Asia/Tokyo"
TZ="$DEFAULT_TZ"
export TZ
umask 077

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$*"
}

debug() {
    [ "$DEBUG" -eq 1 ] || return 0
    log "[DEBUG] $*"
}

WORK_DIR="$(mktemp -d)" || exit 1
STATE_TMP=""
cleanup() {
    [ -z "$STATE_TMP" ] || rm -f "$STATE_TMP"
    rm -rf "$WORK_DIR"
}
trap cleanup 0
trap 'exit 0' INT TERM

mkdir -p "$STATE_DIR" || exit 1

# Read values as data, never as shell code. The last matching key wins.
get_value() {
    awk -v wanted="$2" -v key="$3" '
        { sub(/\r$/, "") }
        /^\[/ { section = substr($0, 2, length($0) - 2); next }
        section == wanted && index($0, key "=") == 1 {
            value = substr($0, length(key) + 2)
        }
        END { print value }
    ' "$1"
}

valid_ipv4() {
    printf '%s\n' "$1" | awk '
        {
            if (NR != 1 || split($0, octet, ".") != 4) exit 1
            for (i = 1; i <= 4; i++) {
                if (octet[i] !~ /^[0-9]+$/ || length(octet[i]) > 3 ||
                    octet[i] + 0 > 255 ||
                    (length(octet[i]) > 1 && substr(octet[i], 1, 1) == "0"))
                    exit 1
            }
        }
        END { if (NR == 0) exit 1 }
    '
}

read_interval() {
    VALUE="$(get_value "$WORK_DIR/config" '' "$1")"
    if ! awk -v key="$1" '
        /^\[/ { exit }
        index($0, key "=") == 1 { found = 1 }
        END { exit !found }
    ' "$WORK_DIR/config"; then
        VALUE="$4"
    fi
    if ! awk -v n="$VALUE" -v lo="$2" -v hi="$3" '
        BEGIN { exit !(n ~ /^[0-9]+$/ && length(n) <= 6 && n+0 >= lo && n+0 <= hi) }
    '; then
        log "[CONFIG] Invalid $1: using ${4}s"
        VALUE="$4"
    fi
    VALUE="$(awk -v n="$VALUE" 'BEGIN { print n+0 }')"
}

# Accept installed zoneinfo names, not arbitrary paths or POSIX expressions.
valid_timezone() {
    case "$1" in
        ''|/*|*..*|*[!A-Za-z0-9_+/-]*) return 1 ;;
    esac
    [ -f "/usr/share/zoneinfo/$1" ] &&
        [ "$(dd if="/usr/share/zoneinfo/$1" bs=4 count=1 2>/dev/null)" = TZif ]
}

load_timezone() {
    REQUESTED_TZ="$(get_value "$WORK_DIR/config" '' TZ)"
    # Omission uses the default silently; an explicit empty value is invalid.
    if ! awk '
        /^\[/ { exit }
        /^TZ=/ { found=1 }
        END { exit !found }
    ' "$WORK_DIR/config"; then
        REQUESTED_TZ="$DEFAULT_TZ"
    fi
    if valid_timezone "$REQUESTED_TZ"; then
        TZ="$REQUESTED_TZ"
        export TZ
    else
        TZ="$DEFAULT_TZ"
        export TZ
        log "[CONFIG] Invalid TZ: using $DEFAULT_TZ"
    fi
}

load_config() {
    cp "$CONFIG" "$WORK_DIR/config" || {
        log "[CONFIG] Cannot read configuration"
        return 1
    }
    load_timezone
    DEBUG="$(get_value "$WORK_DIR/config" '' DEBUG)"
    case "$DEBUG" in
        0|1) ;;
        '')
            if awk '/^\[/ { exit } /^DEBUG=/ { found=1 } END { exit !found }' "$WORK_DIR/config"; then
                log "[CONFIG] Invalid DEBUG: using 0"
            fi
            DEBUG=0
            ;;
        *)
            log "[CONFIG] Invalid DEBUG: using 0"
            DEBUG=0
            ;;
    esac
    # Restrict section names to unique numeric keys suitable for state storage.
    if ! awk '
        { sub(/\r$/, "") }
        /^\[/ {
            if ($0 !~ /^\[[0-9]+\]$/ || length($0) > 11 || seen[$0]++) exit 1
            print substr($0, 2, length($0)-2)
            count++
        }
        END { if (!count) exit 1 }
    ' "$WORK_DIR/config" > "$WORK_DIR/sections"; then
        log "[CONFIG] Missing, invalid or duplicate account sections"
        return 1
    fi
    # Prevent active fields below a commented header from leaking into
    # the previous account, even if that account was missing the same key.
    if ! awk '
        { sub(/\r$/, "") }
        /^\[/ { section=$0; disabled=0; next }
        /^[[:space:]]*[#;][[:space:]]*\[[^]]+\][[:space:]]*$/ {
            disabled=1; next
        }
        /^[[:space:]]*[#;]/ { next }
        /^(ID|PASSWORD|DOMAIN)=/ {
            key=substr($0, 1, index($0, "=")-1)
            if (disabled) {
                printf "line %d: active account field below commented section\n", NR
                exit 1
            }
            if (section == "") {
                printf "line %d: account field outside a section\n", NR
                exit 1
            }
            if (fields[section SUBSEP key]++) {
                printf "line %d: duplicate %s in %s\n", NR, key, section
                exit 1
            }
        }
    ' "$WORK_DIR/config" > "$WORK_DIR/config-error"; then
        log "[CONFIG] $(cat "$WORK_DIR/config-error"); skipping this cycle"
        return 1
    fi
    read_interval CHECK_INTERVAL 60 86400 300
    CHECK_INTERVAL="$VALUE"
    read_interval FORCE_UPDATE_INTERVAL 3600 604800 86400
    FORCE_UPDATE_INTERVAL="$VALUE"
    if [ "$FORCE_UPDATE_INTERVAL" -lt "$CHECK_INTERVAL" ]; then
        log "[CONFIG] FORCE_UPDATE_INTERVAL < CHECK_INTERVAL: using 86400s"
        FORCE_UPDATE_INTERVAL=86400
    fi
    if grep -q '^INTERVAL=' "$WORK_DIR/config"; then
        log "[CONFIG] INTERVAL is obsolete; use CHECK_INTERVAL"
    fi
    IP_CHECK_URL1="$(get_value "$WORK_DIR/config" '' IP_CHECK_URL1)"
    IP_CHECK_URL2="$(get_value "$WORK_DIR/config" '' IP_CHECK_URL2)"
    IP_CHECK_URL3="$(get_value "$WORK_DIR/config" '' IP_CHECK_URL3)"
    IP_CHECK_URL1="${IP_CHECK_URL1:-https://api.ipify.org}"
    IP_CHECK_URL2="${IP_CHECK_URL2:-https://checkip.amazonaws.com/}"
    IP_CHECK_URL3="${IP_CHECK_URL3:-https://ipv4.ifconfig.me/ip}"
}

get_current_ipv4() {
    for URL in "$IP_CHECK_URL1" "$IP_CHECK_URL2" "$IP_CHECK_URL3"; do
        if CANDIDATE="$(curl -4 -fsS --connect-timeout 10 --max-time 20 \
            "$URL" 2>/dev/null)"; then
            CANDIDATE="$(printf '%s\n' "$CANDIDATE" |
                sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            if valid_ipv4 "$CANDIDATE"; then
                CURRENT_IPV4="$CANDIDATE"
                return 0
            fi
        fi
        log "[IPv4] Service failed or returned an invalid IPv4"
    done
    log "[IPv4] All checks failed: skipping this cycle"
    return 1
}

load_state() {
    : > "$WORK_DIR/state" || exit 1
    if [ -e "$STATE_FILE" ]; then
        if ! cp "$STATE_FILE" "$WORK_DIR/state"; then
            log "[STATE] Cannot read state"
            exit 1
        fi
        if ! awk '
            { sub(/\r$/, "") }
            /^$/ || /^[#;]/ { next }
            /^\[[0-9]+\]$/ {
                if (sections[$0]++) exit 1
                section=$0; next
            }
            /^LAST_IPV4=/ {
                if (ip[section]++) exit 1
                next
            }
            /^LAST_UPDATE=[0-9]+$/ {
                if (section == "" || stamp[section]++ || length(substr($0,13)) > 10)
                    exit 1
                next
            }
            { exit 1 }
        ' "$WORK_DIR/state"; then
            log "[STATE] Malformed state: treating all accounts as first run"
            : > "$WORK_DIR/state" || exit 1
        fi
    fi
    LAST_IPV4="$(get_value "$WORK_DIR/state" '' LAST_IPV4)"
    valid_ipv4 "$LAST_IPV4" || LAST_IPV4=""
    NOW="$(date +%s)"
    while IFS= read -r ACCOUNT; do
        ACCOUNT_IP="$(get_value "$WORK_DIR/state" "$ACCOUNT" LAST_IPV4)"
        ACCOUNT_TIME="$(get_value "$WORK_DIR/state" "$ACCOUNT" LAST_UPDATE)"
        if ! valid_ipv4 "$ACCOUNT_IP" || ! awk -v n="$ACCOUNT_TIME" -v now="$NOW" '
            BEGIN { exit !(n ~ /^[0-9]+$/ && length(n) <= 10 && n+0 > 0 && n+0 <= now) }
        '; then
            ACCOUNT_IP=""
            ACCOUNT_TIME=0
        fi
        ACCOUNT_TIME="$(awk -v n="$ACCOUNT_TIME" 'BEGIN { printf "%.0f", n+0 }')"
        printf '%s\n' "$ACCOUNT_IP" > "$WORK_DIR/ip.$ACCOUNT" || exit 1
        printf '%s\n' "$ACCOUNT_TIME" > "$WORK_DIR/time.$ACCOUNT" || exit 1
    done < "$WORK_DIR/sections"
}

write_state_content() {
    printf 'LAST_IPV4=%s\n' "$LAST_IPV4" || return 1
    while IFS= read -r SAVED_ACCOUNT; do
        SAVED_IP="$(cat "$WORK_DIR/ip.$SAVED_ACCOUNT")" || return 1
        SAVED_TIME="$(cat "$WORK_DIR/time.$SAVED_ACCOUNT")" || return 1
        printf '\n[%s]\nLAST_IPV4=%s\nLAST_UPDATE=%s\n' \
            "$SAVED_ACCOUNT" "$SAVED_IP" "$SAVED_TIME" || return 1
    done < "$WORK_DIR/sections"
}

save_state() {
    STATE_TMP="$(mktemp "$STATE_DIR/.state.conf.XXXXXX")" || return 1
    if write_state_content > "$STATE_TMP" && mv -f "$STATE_TMP" "$STATE_FILE"; then
        STATE_TMP=""
        return 0
    fi
    rm -f "$STATE_TMP"
    STATE_TMP=""
    return 1
}

persist_or_exit() {
    if ! save_state; then
        log "[STATE] Save failed: stopping to avoid proceeding without saved state"
        exit 1
    fi
}

run_cycle() {
    debug "[CHECK] IPv4 check started"
    get_current_ipv4 || return 0
    debug "[CHECK] IPv4 acquired: $CURRENT_IPV4"
    load_state
    ALL_MATCH=1
    while IFS= read -r SECTION; do
        ID="$(get_value "$WORK_DIR/config" "$SECTION" ID)"
        PASSWORD="$(get_value "$WORK_DIR/config" "$SECTION" PASSWORD)"
        DOMAIN="$(get_value "$WORK_DIR/config" "$SECTION" DOMAIN)"
        ACCOUNT_IP="$(cat "$WORK_DIR/ip.$SECTION")"
        LAST_UPDATE="$(cat "$WORK_DIR/time.$SECTION")"
        NOW="$(date +%s)"

        if [ -z "$ID" ] || [ -z "$PASSWORD" ] || [ -z "$DOMAIN" ]; then
            log "[$SECTION] MyDNS update: CONFIG ERROR"
            ALL_MATCH=0
            continue
        fi

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
            if RESPONSE="$(curl -4 -fsS --connect-timeout 10 --max-time 30 \
                -u "$ID:$PASSWORD" https://ipv4.mydns.jp/login.html 2>/dev/null)" &&
               printf '%s\n' "$RESPONSE" | grep -Fq 'Login and IP address notify OK.'; then
                ACCOUNT_IP="$CURRENT_IPV4"
                LAST_UPDATE="$(date +%s)"
                printf '%s\n' "$ACCOUNT_IP" > "$WORK_DIR/ip.$SECTION" || exit 1
                printf '%s\n' "$LAST_UPDATE" > "$WORK_DIR/time.$SECTION" || exit 1
                # Persist each success before moving on to the next account.
                persist_or_exit
                log "[$DOMAIN] MyDNS update: OK (IPv4=$ACCOUNT_IP)"
            else
                log "[$DOMAIN] MyDNS update: FAILED"
                ALL_MATCH=0
            fi
        else
            debug "[$SECTION] [SKIP] IPv4 unchanged; force update not due"
        fi
        [ "$ACCOUNT_IP" = "$CURRENT_IPV4" ] || ALL_MATCH=0
    done < "$WORK_DIR/sections"

    if [ "$ALL_MATCH" -eq 1 ] && [ "$LAST_IPV4" != "$CURRENT_IPV4" ]; then
        LAST_IPV4="$CURRENT_IPV4"
        log "[IPv4] All accounts synchronized: $LAST_IPV4"
    fi
    persist_or_exit
}

STARTUP_LOGGED=0
while true; do
    CHECK_INTERVAL=300
    if load_config; then
        if [ "$STARTUP_LOGGED" -eq 0 ]; then
            log "[STARTUP] MyDNS updater v${VERSION} started: TZ=${TZ}, DEBUG=${DEBUG}, CHECK_INTERVAL=${CHECK_INTERVAL}s, FORCE_UPDATE_INTERVAL=${FORCE_UPDATE_INTERVAL}s"
            STARTUP_LOGGED=1
        fi
        run_cycle
    fi
    sleep "$CHECK_INTERVAL"
done
