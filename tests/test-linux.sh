#!/bin/sh
# Safe to run as an ordinary user: all fixtures live under one temporary directory.
set -eu
UPDATER="${1:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)/update.sh}"
TASK_DIR="$(mktemp -d)"
trap 'rm -rf "$TASK_DIR"' 0
trap 'exit 1' INT TERM
umask 077
CONFIG_TEST="$TASK_DIR/settings with spaces"
STATE_TEST="$TASK_DIR/state with spaces"
mkdir -p "$CONFIG_TEST" "$STATE_TEST" "$TASK_DIR/bin"
cat > "$TASK_DIR/bin/curl" <<'EOF'
#!/bin/sh
output=''
url=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output) output="$2"; shift ;;
        --write-out|-u|--connect-timeout|--max-time) shift ;;
        https://*) url="$1" ;;
    esac
    shift
done
echo request >> "$TEST_CALLS"
case "$url" in
    https://ipv4.mydns.jp/login.html) printf 'Login and IP address notify OK.\n' > "$output" ;;
    *) printf '203.0.113.90\n' > "$output" ;;
esac
printf '200'
EOF
cat > "$TASK_DIR/bin/sleep" <<'EOF'
#!/bin/sh
kill -TERM "$PPID"
EOF
chmod +x "$TASK_DIR/bin/"*
export TEST_CALLS="$TASK_DIR/calls"
COUNT=0
pass() { COUNT=$((COUNT+1)); printf 'PASS linux %s: %s\n' "$COUNT" "$*"; }
fail() { cat "$TASK_DIR/log"; echo "FAIL linux: $*"; exit 1; }
cycle() {
    : > "$TEST_CALLS"
    MYDNS_CONFIG_DIR="$CONFIG_TEST" MYDNS_STATE_DIR="$STATE_TEST" \
        PATH="$TASK_DIR/bin:$PATH" sh "$UPDATER" > "$TASK_DIR/log" 2>&1
}
printf 'DEBUG=0\nCHECK_INTERVAL=300\nFORCE_UPDATE_INTERVAL=3600\n' > "$CONFIG_TEST/mydns.conf"
printf '[1]\nID=dummy\nPASSWORD=dummy\nDOMAIN=test.example\n' > "$CONFIG_TEST/accounts.conf"
cycle || fail 'initial cycle'
grep -Fq 'MyDNS update: OK' "$TASK_DIR/log" || fail 'missing success'
[ -s "$STATE_TEST/state.conf" ] || fail 'state outside configured directory'
pass 'custom absolute paths with spaces initialize and save state'
cp "$STATE_TEST/state.conf" "$TASK_DIR/before"
cycle || fail 'restart'
cmp "$TASK_DIR/before" "$STATE_TEST/state.conf" || fail 'state changed'
grep -Fq 'MyDNS update: OK' "$TASK_DIR/log" && fail 'repeated notification'
pass 'fresh process retains saved success'
printf 'DEBUG=1\nTZ=UTC\n' > "$CONFIG_TEST/next"
mv "$CONFIG_TEST/next" "$CONFIG_TEST/mydns.conf"
cycle || fail 'replaced settings'
grep -Fq '[DEBUG] [CHECK]' "$TASK_DIR/log" || fail 'debug not loaded'
grep -Fq ' UTC ' "$TASK_DIR/log" || fail 'timezone not loaded'
pass 'replacement common file is read from custom directory'
printf '[1]\nID=dummy\nPASSWORD=dummy\nDOMAIN=test.example\n[2]\nID=second\nPASSWORD=dummy\nDOMAIN=second.example\n' > "$CONFIG_TEST/next"
mv "$CONFIG_TEST/next" "$CONFIG_TEST/accounts.conf"
cycle || fail 'replaced accounts'
[ "$(grep -c 'MyDNS update: OK' "$TASK_DIR/log")" -eq 1 ] || fail 'wrong update count'
grep -Fq '[ACCOUNT 2: second.example] MyDNS update: OK' "$TASK_DIR/log" || fail 'new account not read'
pass 'replacement account file initializes only added account'
cp "$STATE_TEST/state.conf" "$TASK_DIR/before"
mv "$CONFIG_TEST/accounts.conf" "$CONFIG_TEST/hidden"
cycle || fail 'missing accounts should retry'
[ ! -s "$TEST_CALLS" ] || fail 'missing accounts communicated'
cmp "$TASK_DIR/before" "$STATE_TEST/state.conf" || fail 'missing accounts changed state'
mv "$CONFIG_TEST/hidden" "$CONFIG_TEST/accounts.conf"
pass 'missing account file skips communication and preserves state'
printf 'UNKNOWN=private-value\n' >> "$CONFIG_TEST/accounts.conf"
cycle || fail 'invalid config should retry'
[ ! -s "$TEST_CALLS" ] || fail 'invalid config communicated'
grep -q 'private-value' "$TASK_DIR/log" && fail 'invalid value leaked'
pass 'structure validation works at custom path without exposing values'
if MYDNS_CONFIG_DIR=relative MYDNS_STATE_DIR="$STATE_TEST" sh "$UPDATER" > "$TASK_DIR/log" 2>&1; then fail 'relative config path accepted'; fi
grep -Fq 'PATH_INVALID' "$TASK_DIR/log" || fail 'missing path error'
pass 'relative configuration path is rejected'
if MYDNS_CONFIG_DIR="$CONFIG_TEST" MYDNS_STATE_DIR=relative sh "$UPDATER" > "$TASK_DIR/log" 2>&1; then fail 'relative state path accepted'; fi
grep -Fq 'PATH_INVALID' "$TASK_DIR/log" || fail 'missing state path error'
pass 'relative state path is rejected'
echo "ALL LINUX TESTS PASSED ($COUNT checks)"
