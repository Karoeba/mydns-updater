#!/bin/sh
# No root, real accounts or external requests; private runtime for each test.
set -eu
UPDATER="${1:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)/update.sh}"
TEST_DIR="$(mktemp -d)"
PID=""
cleanup_test() {
    if [ -n "$PID" ]; then kill -TERM "$PID" 2>/dev/null || :; wait "$PID" 2>/dev/null || :; fi
    rm -rf "$TEST_DIR"
}
trap cleanup_test 0
trap 'exit 1' INT TERM
export MYDNS_HEALTH_FILE="$TEST_DIR/runtime with spaces/health"
mkdir -p "$(dirname "$MYDNS_HEALTH_FILE")" "$TEST_DIR/bin" "$TEST_DIR/config" "$TEST_DIR/state"
HEALTH_FILE="$MYDNS_HEALTH_FILE"
HEALTH_ENABLED=0
. "$(dirname "$UPDATER")/lib/health.sh"
fatal() { echo "$*"; exit 1; }
COUNT=0
pass() { COUNT=$((COUNT+1)); echo "PASS linux health $COUNT: $*"; }
fail() { cat "$TEST_DIR/log"; echo "FAIL linux health: $*"; exit 1; }
ok() { sh "$UPDATER" --healthcheck > "$TEST_DIR/log" || fail 'unexpected unhealthy'; }
bad() {
    if sh "$UPDATER" --healthcheck > "$TEST_DIR/log"; then fail 'unexpected healthy'; fi
    grep -Fq "$1" "$TEST_DIR/log" || fail 'wrong reason'
}
HEALTH_ENABLED=1
HEALTH_START="$(health_process_start "$$")"
HEALTH_BOOT="$(cat /proc/sys/kernel/random/boot_id)"
health_progress 0
ok
pass 'custom runtime path including spaces works without root'
cp "$HEALTH_FILE" "$TEST_DIR/before"
ok
cmp "$HEALTH_FILE" "$TEST_DIR/before"
pass 'probe does not extend its own deadline'
printf '%s %s 0 %s\n' "$$" "$HEALTH_START" "$HEALTH_BOOT" > "$HEALTH_FILE"
bad 'overdue'
pass 'stalled live process fails'
printf '%s %s 999999999999 00000000-0000-0000-0000-000000000000\n' "$$" "$HEALTH_START" > "$HEALTH_FILE"
bad 'process unavailable'
pass 'record from another boot fails'
if MYDNS_HEALTH_FILE=relative sh "$UPDATER" --healthcheck > "$TEST_DIR/log"; then fail 'relative runtime accepted'; fi
pass 'relative runtime path fails'
rm "$HEALTH_FILE"
# An invalid configuration skips network access but the loop must keep progressing.
printf 'UNKNOWN=invalid\n' > "$TEST_DIR/config/mydns.conf"
printf '[1]\nID=dummy\nPASSWORD=dummy\nDOMAIN=test.example\n' > "$TEST_DIR/config/accounts.conf"
cat > "$TEST_DIR/bin/sleep" <<'EOF'
#!/bin/sh
exec /bin/sleep 1
EOF
cat > "$TEST_DIR/bin/curl" <<'EOF'
#!/bin/sh
echo called >> "$TEST_NETWORK"
exit 99
EOF
chmod +x "$TEST_DIR/bin/"*
export TEST_NETWORK="$TEST_DIR/network"
MYDNS_CONFIG_DIR="$TEST_DIR/config" MYDNS_STATE_DIR="$TEST_DIR/state" PATH="$TEST_DIR/bin:$PATH" sh "$UPDATER" > "$TEST_DIR/updater.log" 2>&1 &
PID=$!
attempt=0
while [ ! -s "$HEALTH_FILE" ] && [ "$attempt" -lt 50 ]; do /bin/sleep 0.1; attempt=$((attempt+1)); done
ok
[ ! -e "$TEST_NETWORK" ] || fail 'configuration error contacted network'
pass 'real loop remains healthy on configuration error without network'
kill -TERM "$PID"
wait "$PID" || :
PID=""
bad 'unavailable'
pass 'stopping the real updater removes its progress record'
echo "ALL LINUX HEALTHCHECK TESTS PASSED ($COUNT checks)"
