#!/bin/sh
# Persistent account success state. Uses config readers, IPv4 validation and diagnostics.
# Sourced by update.sh; not a standalone command.

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
