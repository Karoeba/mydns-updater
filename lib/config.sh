#!/bin/sh
# Configuration is data, never shell code. Uses diagnostic reporting and runtime paths.
# Sourced by update.sh; not a standalone command.

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
