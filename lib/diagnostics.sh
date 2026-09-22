#!/bin/sh
# Process-local diagnostic history and logging. Uses private runtime storage.
# Sourced by update.sh; not a standalone command.

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
