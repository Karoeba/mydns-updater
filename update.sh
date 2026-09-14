#!/bin/sh

VERSION="1.4.0"
CONFIG="/config/mydns.conf"
ACCOUNTS_CONFIG="/config/accounts.conf"
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


# History is private to this process and resets on restart.
diagnostic_clock() { awk '{printf "%.0f", $1}' /proc/uptime; }
fatal() { log "[FATAL] $*"; exit 1; }

# key, target, cause, mode (transient/fallback/error/warning), explanation
failure() {
    D_KEY="$1"; D_TARGET="$2"; D_CAUSE="$3"; D_MODE="$4"; D_TEXT="$5"
    D_FILE="$WORK_DIR/diagnostic.$D_KEY"
    D_NOW="$(diagnostic_clock)"
    D_COUNT=0; D_ELAPSED=0; D_PREVIOUS="$D_NOW"; D_OLD_STAGE=""; D_OLD_CAUSE=""
    if [ -f "$D_FILE" ]; then
        { read -r D_COUNT; read -r D_ELAPSED; read -r D_PREVIOUS
          read -r D_OLD_STAGE; IFS= read -r D_OLD_CAUSE; } < "$D_FILE"
    fi
    D_DELTA=$((D_NOW - D_PREVIOUS))
    [ "$D_DELTA" -ge 0 ] || D_DELTA=0
    D_ELAPSED=$((D_ELAPSED + D_DELTA))
    D_COUNT=$((D_COUNT + 1))
    D_STAGE=FIRST; D_LEVEL=WARN
    if [ "$D_ELAPSED" -ge 3600 ]; then
        D_STAGE=PROLONGED; D_LEVEL=ERROR
    elif [ "$D_COUNT" -ge 3 ] && [ "$D_ELAPSED" -ge 600 ]; then
        D_STAGE=PERSISTENT; D_LEVEL=ERROR
    fi
    case "$D_MODE" in
        fallback|warning) D_LEVEL=WARN ;;
        error) D_LEVEL=ERROR ;;
    esac
    if [ "$D_COUNT" -eq 1 ] || [ "$D_STAGE" != "$D_OLD_STAGE" ] ||
       [ "$D_CAUSE $D_TEXT" != "$D_OLD_CAUSE" ]; then
        log "[$D_LEVEL] [$D_TARGET] $D_CAUSE stage=$D_STAGE failures=$D_COUNT elapsed=${D_ELAPSED}s; $D_TEXT"
    else
        debug "[$D_TARGET] $D_CAUSE stage=$D_STAGE failures=$D_COUNT elapsed=${D_ELAPSED}s; $D_TEXT"
    fi
    printf '%s\n' "$D_COUNT" "$D_ELAPSED" "$D_NOW" "$D_STAGE" "$D_CAUSE $D_TEXT" > "$D_FILE" ||
        fatal "[INTERNAL] DIAGNOSTIC_SAVE_FAILED; check temporary storage"
}
recovered() {
    R_FILE="$WORK_DIR/diagnostic.$1"
    [ -f "$R_FILE" ] || return 0
    { read -r R_COUNT; read -r R_ELAPSED; read -r R_PREVIOUS; } < "$R_FILE"
    R_NOW="$(diagnostic_clock)"
    R_DELTA=$((R_NOW - R_PREVIOUS))
    [ "$R_DELTA" -ge 0 ] || R_DELTA=0
    log "[INFO] [$2] RECOVERED failures=$R_COUNT elapsed=$((R_ELAPSED + R_DELTA))s"
    rm -f "$R_FILE"
}
config_failure() {
    touch "$WORK_DIR/seen.config.$1" || fatal "[INTERNAL] DIAGNOSTIC_SAVE_FAILED"
    failure "config.$1" CONFIG "$2" "$3" "$4"
}
prune_account_diagnostics() {
    for P_FILE in "$WORK_DIR"/target.account.*; do
        [ -f "$P_FILE" ] || continue
        P_SECTION="${P_FILE##*/target.account.}"
        if ! grep -Fxq "$P_SECTION" "$WORK_DIR/sections"; then
            log "[INFO] [ACCOUNT $P_SECTION] REMOVED; diagnostic history cleared"
            rm -f "$P_FILE" "$WORK_DIR/diagnostic.account.$P_SECTION" \
                "$WORK_DIR/diagnostic.account-config.$P_SECTION"
        fi
    done
}

finish_config_diagnostics() {
    for C_FILE in "$WORK_DIR"/diagnostic.config.*; do
        [ -f "$C_FILE" ] || continue
        C_KEY="${C_FILE##*/diagnostic.}"
        [ -f "$WORK_DIR/seen.$C_KEY" ] || recovered "$C_KEY" CONFIG
    done
}
# A changed endpoint/account is not a recovered old target.
track_target() {
    T_KEY="$1"
    printf '%s\n' "$2" > "$WORK_DIR/target.next" || fatal "[INTERNAL] TARGET_SAVE_FAILED"
    if [ -f "$WORK_DIR/target.$T_KEY" ] &&
       ! cmp -s "$WORK_DIR/target.next" "$WORK_DIR/target.$T_KEY"; then
        if [ -f "$WORK_DIR/diagnostic.$T_KEY" ]; then
            log "[INFO] [$3] TARGET_CHANGED; previous failure history cleared"
        fi
        rm -f "$WORK_DIR/diagnostic.$T_KEY"
    fi
    cp "$WORK_DIR/target.next" "$WORK_DIR/target.$T_KEY" || fatal "[INTERNAL] TARGET_SAVE_FAILED"
}
# Separate curl exit status, HTTP status and body. Never log stderr/body/URL.
request() {
    REQUEST_TIMEOUT="$1"
    shift
    HTTP_CODE=""
    CURL_CODE=0
    : > "$WORK_DIR/response" || fatal "[INTERNAL] RESPONSE_FILE_FAILED"
    HTTP_CODE="$(curl -4 -fsS --connect-timeout 10 --max-time "$REQUEST_TIMEOUT" \
        --output "$WORK_DIR/response" --write-out '%{http_code}' "$@" 2>/dev/null)" || CURL_CODE=$?
}
classify_response() {
    ERROR_MODE=transient
    ERROR_HINT="retry; if persistent check network and service"
    ERROR_CODE=""
    case "$CURL_CODE" in
        0|22) ;;
        1|3|4) ERROR_CODE=URL_OR_PROTOCOL_ERROR; ERROR_MODE=error; ERROR_HINT="check endpoint configuration" ;;
        5|6) ERROR_CODE=DNS_FAILED ;;
        7) ERROR_CODE=CONNECT_FAILED ;;
        28) ERROR_CODE=TIMEOUT ;;
        35) ERROR_CODE=TLS_FAILED; ERROR_HINT="check clock, TLS and endpoint" ;;
        51|58|60|77) ERROR_CODE=CERTIFICATE_ERROR; ERROR_MODE=error; ERROR_HINT="check clock, certificates and endpoint" ;;
        23|26|27) ERROR_CODE=LOCAL_RESOURCE_ERROR; ERROR_MODE=error; ERROR_HINT="check temporary storage and memory" ;;
        52) ERROR_CODE=EMPTY_RESPONSE ;;
        55|56|18) ERROR_CODE=TRANSFER_FAILED ;;
        *) ERROR_CODE=CURL_ERROR ;;
    esac
    if [ -z "$ERROR_CODE" ]; then
        case "$HTTP_CODE" in
            2[0-9][0-9]) [ "$CURL_CODE" -eq 0 ] && return 0; ERROR_CODE=HTTP_ERROR ;;
            401) ERROR_CODE=HTTP_UNAUTHORIZED; ERROR_MODE=error; ERROR_HINT="check credentials and service access" ;;
            403) ERROR_CODE=HTTP_FORBIDDEN; ERROR_MODE=error; ERROR_HINT="check access restrictions; credentials may not be the cause" ;;
            408) ERROR_CODE=HTTP_TIMEOUT ;;
            429) ERROR_CODE=RATE_LIMITED; ERROR_HINT="do not increase request frequency; check service guidance" ;;
            5[0-9][0-9]) ERROR_CODE=HTTP_SERVER_ERROR ;;
            3[0-9][0-9]) ERROR_CODE=HTTP_REDIRECT; ERROR_MODE=error; ERROR_HINT="check endpoint; redirect not followed" ;;
            4[0-9][0-9]) ERROR_CODE=HTTP_CLIENT_ERROR; ERROR_MODE=error; ERROR_HINT="check endpoint and service requirements" ;;
            *) ERROR_CODE=HTTP_STATUS_UNKNOWN ;;
        esac
    fi
    return 1
}
transport_failure() {
    case "$HTTP_CODE" in
        [0-9][0-9][0-9]) SAFE_HTTP="$HTTP_CODE" ;;
        *) SAFE_HTTP=unknown ;;
    esac
    failure "$1" "$2" "$ERROR_CODE" "$3" \
        "curl=$CURL_CODE http=$SAFE_HTTP; $ERROR_HINT; $4"
}

WORK_DIR="$(mktemp -d)" || fatal "[INTERNAL] TEMP_CREATE_FAILED; check temporary storage"
STATE_TMP=""
cleanup() {
    [ -z "$STATE_TMP" ] || rm -f "$STATE_TMP"
    rm -rf "$WORK_DIR"
}
trap cleanup 0
trap 'exit 0' INT TERM

mkdir -p "$STATE_DIR" || fatal "[STATE] DIRECTORY_CREATE_FAILED; check permissions and storage"

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
        config_failure "$1" INVALID_INTERVAL warning "Invalid $1: using ${4}s"
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
        config_failure TZ INVALID_TZ warning "Invalid TZ: using $DEFAULT_TZ"
    fi
}

load_config() {
    rm -f "$WORK_DIR"/seen.config.*
    cp "$CONFIG" "$WORK_DIR/config" 2>/dev/null || {
        config_failure read-common READ_FAILED error "Cannot read config/mydns.conf; check file, mount and permissions"
        return 1
    }
    cp "$ACCOUNTS_CONFIG" "$WORK_DIR/accounts" 2>/dev/null || {
        config_failure read-accounts READ_FAILED error "Cannot read config/accounts.conf; check file, mount and permissions"
        return 1
    }
    # Validate file roles before applying settings. Never print input values.
    if ! awk '
        { sub(/\r$/, "") }
        /^[[:space:]]*$/ || /^[[:space:]]*[#;]/ { next }
        /^(CHECK_INTERVAL|FORCE_UPDATE_INTERVAL|TZ|DEBUG|IP_CHECK_URL[123]|INTERVAL)=/ { next }
        { printf "config/mydns.conf line %d: unexpected setting or account section; move accounts to accounts.conf\n", NR; exit 1 }
    ' "$WORK_DIR/config" > "$WORK_DIR/config-error"; then
        config_failure common-structure COMMON_STRUCTURE_INVALID error "$(cat "$WORK_DIR/config-error"); skipping this cycle"
        return 1
    fi
    load_timezone
    DEBUG="$(get_value "$WORK_DIR/config" '' DEBUG)"
    case "$DEBUG" in
        0|1) ;;
        '')
            if awk '/^\[/ { exit } /^DEBUG=/ { found=1 } END { exit !found }' "$WORK_DIR/config"; then
                DEBUG=0
                config_failure DEBUG INVALID_DEBUG warning "Invalid DEBUG: using 0"
            fi
            DEBUG=0
            ;;
        *)
            DEBUG=0
            config_failure DEBUG INVALID_DEBUG warning "Invalid DEBUG: using 0"
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
    ' "$WORK_DIR/accounts" > "$WORK_DIR/sections"; then
        config_failure structure SECTIONS_INVALID error "config/accounts.conf: Missing, invalid or duplicate account sections; skipping this cycle; check section numbers"
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
        /^[[:space:]]*$/ { next }
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
            next
        }
        { printf "line %d: unexpected account setting; common settings belong in mydns.conf\n", NR; exit 1 }
    ' "$WORK_DIR/accounts" > "$WORK_DIR/config-error"; then
        config_failure structure ACCOUNT_STRUCTURE_INVALID error "config/accounts.conf: $(cat "$WORK_DIR/config-error"); skipping this cycle; correct configuration"
        return 1
    fi
    read_interval CHECK_INTERVAL 60 86400 300
    CHECK_INTERVAL="$VALUE"
    read_interval FORCE_UPDATE_INTERVAL 3600 604800 86400
    FORCE_UPDATE_INTERVAL="$VALUE"
    if [ "$FORCE_UPDATE_INTERVAL" -lt "$CHECK_INTERVAL" ]; then
        config_failure order INTERVAL_ORDER warning "FORCE_UPDATE_INTERVAL < CHECK_INTERVAL: using 86400s"
        FORCE_UPDATE_INTERVAL=86400
    fi
    if grep -q '^INTERVAL=' "$WORK_DIR/config"; then
        config_failure obsolete OBSOLETE_INTERVAL warning "INTERVAL is obsolete; use CHECK_INTERVAL"
    fi
    IP_CHECK_URL1="$(get_value "$WORK_DIR/config" '' IP_CHECK_URL1)"
    IP_CHECK_URL2="$(get_value "$WORK_DIR/config" '' IP_CHECK_URL2)"
    IP_CHECK_URL3="$(get_value "$WORK_DIR/config" '' IP_CHECK_URL3)"
    IP_CHECK_URL1="${IP_CHECK_URL1:-https://api.ipify.org}"
    IP_CHECK_URL2="${IP_CHECK_URL2:-https://checkip.amazonaws.com/}"
    IP_CHECK_URL3="${IP_CHECK_URL3:-https://ipv4.ifconfig.me/ip}"
    prune_account_diagnostics
}

get_current_ipv4() {
    SERVICE=0
    for URL in "$IP_CHECK_URL1" "$IP_CHECK_URL2" "$IP_CHECK_URL3"; do
        SERVICE=$((SERVICE + 1))
        SERVICE_KEY="service.$SERVICE"
        SERVICE_TARGET="IP_CHECK_URL$SERVICE"
        track_target "$SERVICE_KEY" "$URL" "$SERVICE_TARGET"
        request 20 "$URL"
        if classify_response; then
            CANDIDATE="$(sed 's/^[[:space:]]*//;s/[[:space:]]*$//' "$WORK_DIR/response")"
            if valid_ipv4 "$CANDIDATE"; then
                CURRENT_IPV4="$CANDIDATE"
                recovered "$SERVICE_KEY" "$SERVICE_TARGET"
                recovered ip IP_CHECK
                return 0
            fi
            if [ -z "$CANDIDATE" ]; then ERROR_CODE=EMPTY_RESPONSE; else ERROR_CODE=INVALID_IPV4; fi
            failure "$SERVICE_KEY" "$SERVICE_TARGET" "$ERROR_CODE" fallback "trying next service; check configured service if persistent"
        else
            transport_failure "$SERVICE_KEY" "$SERVICE_TARGET" fallback "trying next service"
        fi
    done
    failure ip IP_CHECK ALL_SERVICES_FAILED transient "All checks failed: skipping this cycle; check network and services if persistent"
    return 1
}

load_state() {
    : > "$WORK_DIR/state" || fatal "[INTERNAL] FILE_OPERATION_FAILED; check temporary storage"
    if [ -e "$STATE_FILE" ]; then
        if ! cp "$STATE_FILE" "$WORK_DIR/state"; then
            fatal "[STATE] READ_FAILED; Cannot read state; check permissions and storage"
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
            failure state STATE MALFORMED_STATE warning "Malformed state: treating all accounts as first run; repeated corruption needs investigation"
            : > "$WORK_DIR/state" || fatal "[INTERNAL] FILE_OPERATION_FAILED; check temporary storage"
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
        printf '%s\n' "$ACCOUNT_IP" > "$WORK_DIR/ip.$ACCOUNT" || fatal "[INTERNAL] FILE_OPERATION_FAILED; check temporary storage"
        printf '%s\n' "$ACCOUNT_TIME" > "$WORK_DIR/time.$ACCOUNT" || fatal "[INTERNAL] FILE_OPERATION_FAILED; check temporary storage"
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
        fatal "[STATE] SAVE_FAILED; Save failed: stopping to avoid proceeding without saved state; check permissions and free space"
    fi
}

run_cycle() {
    debug "[CHECK] IPv4 check started"
    get_current_ipv4 || return 0
    debug "[CHECK] IPv4 acquired: $CURRENT_IPV4"
    load_state
    ALL_MATCH=1
    while IFS= read -r SECTION; do
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
            request 30 -u "$ID:$PASSWORD" https://ipv4.mydns.jp/login.html
            REQUEST_OK=0
            if classify_response; then
                if grep -Fq 'Login and IP address notify OK.' "$WORK_DIR/response"; then
                    REQUEST_OK=1
                else
                    ERROR_CODE=SUCCESS_NOT_CONFIRMED
                    ERROR_MODE=transient
                    ERROR_HINT="success response missing; check account and service if persistent"
                fi
            fi
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

STARTUP_LOGGED=0
while true; do
    CHECK_INTERVAL=300
    if load_config; then
        finish_config_diagnostics
        if [ "$STARTUP_LOGGED" -eq 0 ]; then
            log "[STARTUP] MyDNS updater v${VERSION} started: TZ=${TZ}, DEBUG=${DEBUG}, CHECK_INTERVAL=${CHECK_INTERVAL}s, FORCE_UPDATE_INTERVAL=${FORCE_UPDATE_INTERVAL}s"
            STARTUP_LOGGED=1
        fi
        run_cycle
    fi
    sleep "$CHECK_INTERVAL"
done
