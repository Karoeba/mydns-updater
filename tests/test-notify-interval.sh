#!/bin/sh
# Real config/state/cycle code with a clock and transport fixture; no network.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TASK="$(mktemp -d)"
export MYDNS_CONFIG_DIR="$TASK/config" MYDNS_STATE_DIR="$TASK/state"
mkdir -p "$MYDNS_CONFIG_DIR"
for module in diagnostics health config network state runtime; do . "$ROOT/lib/$module.sh"; done
updater_defaults
initialize_runtime
trap 'cleanup; rm -rf "$TASK"' 0
cat > "$MYDNS_CONFIG_DIR/accounts.conf" <<'EOF'
[1]
ID=dummy
PASSWORD=secret-fixture
DOMAIN=test.example
EOF
config() {
    printf 'CHECK_INTERVAL=%s\nFORCE_UPDATE_INTERVAL=%s\n' "$1" "$2" > "$CONFIG"
    load_config
}
config 86400 259200
[ "$FORCE_UPDATE_INTERVAL" -eq 259200 ]
config 86400 259201
[ "$FORCE_UPDATE_INTERVAL" -eq 86400 ]
config 86400 604800
[ "$FORCE_UPDATE_INTERVAL" -eq 86400 ]
grep -q '604800' "$CONFIG" # User's file was not rewritten.
config 86400 259200
FAKE_NOW=1000000
date() { if [ "${1:-}" = +%s ]; then echo "$FAKE_NOW"; else command date "$@"; fi; }
get_current_ipv4() { CURRENT_IPV4=203.0.113.9; }
CALLS=0; SUCCEED=1
notify_mydns() { CALLS=$((CALLS+1)); REQUEST_OK="$SUCCEED"; ERROR_MODE=transient; }
transport_failure() { :; }
run_cycle
[ "$CALLS" -eq 1 ]
FAKE_NOW=1259199; run_cycle; [ "$CALLS" -eq 1 ]
FAKE_NOW=1259200; run_cycle; [ "$CALLS" -eq 2 ]
# Long check period plus 90 seconds of work, one failure, then next-cycle retry.
FAKE_NOW=$((1259200+259200-1)); run_cycle; [ "$CALLS" -eq 2 ]
FAKE_NOW=$((FAKE_NOW+86400+90)); SUCCEED=0
cp "$STATE_FILE" "$TASK/before"
run_cycle; [ "$CALLS" -eq 3 ]; cmp "$STATE_FILE" "$TASK/before"
FAKE_NOW=$((FAKE_NOW+86400+90)); SUCCEED=1
run_cycle; [ "$CALLS" -eq 4 ]
[ $((FAKE_NOW-1259200)) -lt 604800 ]
[ "$(get_value "$STATE_FILE" 1 LAST_UPDATE)" -eq "$FAKE_NOW" ]
echo 'ALL NOTIFY INTERVAL TESTS PASSED'
