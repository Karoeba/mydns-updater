#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
MONITOR="$ROOT/health-monitor.sh"
TASK="$(mktemp -d)"
trap 'rm -rf "$TASK"' 0
trap 'exit 1' INT TERM
mkdir -p "$TASK/state with spaces" "$TASK/bin"
export MYDNS_MONITOR_DIR="$TASK/state with spaces"
export MYDNS_UPDATER="$TASK/probe"
export FIXTURE="$TASK"
export PATH="$TASK/bin:$PATH"
printf 'ok\n' > "$TASK/mode"
printf 'active\n' > "$TASK/active"
printf '11111111111111111111111111111111\n' > "$TASK/generation"
cat > "$TASK/probe" <<'EOF'
#!/bin/sh
echo check >> "$FIXTURE/calls"
case "$(cat "$FIXTURE/mode")" in
ok) echo 'HEALTHY: updater progressing or waiting'; exit 0 ;;
bad) echo 'UNHEALTHY: updater progress overdue'; exit 1 ;;
secret) echo 'private-credential-value'; exit 1 ;;
timeout) sleep 10 ;;
restart) echo 22222222222222222222222222222222 > "$FIXTURE/generation"; exit 1 ;;
stop) echo inactive > "$FIXTURE/active"; exit 1 ;;
esac
EOF
cat > "$TASK/bin/systemctl" <<'EOF'
#!/bin/sh
[ "$1" = show ] || exit 99
case "$3" in
--property=ActiveState) cat "$FIXTURE/active" ;;
--property=InvocationID) cat "$FIXTURE/generation" ;;
*) exit 99 ;;
esac
EOF
chmod +x "$TASK/bin/systemctl"
COUNT=0
pass() { COUNT=$((COUNT+1)); echo "PASS monitor $COUNT: $*"; }
fail() { cat "$TASK/log"; echo "FAIL monitor: $*"; exit 1; }
run() { sh "$MONITOR" "$@" > "$TASK/log" 2>&1 || fail 'monitor failed'; }
quiet() { [ ! -s "$TASK/log" ] || fail 'unexpected log'; }
run; quiet
pass 'healthy startup is quiet'
echo bad > "$TASK/mode"
run; quiet
run; quiet
pass 'first two failures are quiet'
run
grep -Fq 'UNHEALTHY; consecutive_failures=3; reason=PROGRESS_OVERDUE' "$TASK/log" || fail 'missing transition'
pass 'third failure logs one unhealthy transition'
run; quiet
pass 'continued failure is quiet'
echo ok > "$TASK/mode"
run
grep -Fq 'RECOVERED' "$TASK/log" || fail 'missing recovery'
run; quiet
pass 'recovery logs once'
echo bad > "$TASK/mode"
run; quiet
echo ok > "$TASK/mode"
run; quiet
echo bad > "$TASK/mode"
run; quiet
run; quiet
pass 'success clears consecutive failure count'
export MYDNS_MONITOR_GENERATION=next
run; quiet
pass 'new process generation resets failure history'
echo secret > "$TASK/mode"
run; run
grep -Fq 'PROBE_FAILED' "$TASK/log" || fail 'unexpected reason'
grep -q private "$TASK/log" && fail 'raw probe output leaked'
pass 'unrecognized probe output is not exposed'
echo ok > "$TASK/mode"
run
echo inactive > "$TASK/active"
cp "$MYDNS_MONITOR_DIR/status" "$TASK/before"
cp "$TASK/calls" "$TASK/calls-before"
run --systemd; quiet
cmp "$TASK/before" "$MYDNS_MONITOR_DIR/status"
cmp "$TASK/calls-before" "$TASK/calls"
pass 'intentional stop skips checks without starting service'
echo active > "$TASK/active"
echo restart > "$TASK/mode"
run --systemd; quiet
cmp "$TASK/before" "$MYDNS_MONITOR_DIR/status"
pass 'probe across target restart is discarded'
echo stop > "$TASK/mode"
run --systemd; quiet
cmp "$TASK/before" "$MYDNS_MONITOR_DIR/status"
pass 'probe across intentional stop is discarded'
echo timeout > "$TASK/mode"
run; quiet
run; quiet
run
grep -Fq 'PROBE_TIMEOUT' "$TASK/log" || fail 'timeout not classified'
pass 'hanging probe is bounded and classified'
echo corrupt > "$MYDNS_MONITOR_DIR/status"
if sh "$MONITOR" > "$TASK/log" 2>&1; then fail 'corrupt state accepted'; fi
grep -Fq 'invalid monitor state' "$TASK/log" || fail 'missing state error'
pass 'corrupt monitor state is reported'
echo "ALL MONITOR TESTS PASSED ($COUNT checks)"
