#!/bin/sh
# Mock service/clock/probe; no system services or accounts are changed.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TASK="$(mktemp -d)"
trap 'rm -rf "$TASK"' 0
trap 'exit 1' INT TERM
mkdir -p "$TASK/bin" "$TASK/state"
export FIXTURE="$TASK" MYDNS_RECOVERY_DIR="$TASK/state"
export MYDNS_UPDATER="$TASK/probe" MYDNS_RECOVERY_SERVICE=fixture.service
export PATH="$TASK/bin:$PATH"
echo 10000 > "$TASK/now"
echo active > "$TASK/active"
echo 11111111111111111111111111111111 > "$TASK/gen"
echo ok > "$TASK/mode"
: > "$TASK/attempts"
cat > "$TASK/bin/date" <<'EOF'
#!/bin/sh
cat "$FIXTURE/now"
EOF
cat > "$TASK/bin/runuser" <<'EOF'
#!/bin/sh
[ "$1" = -u ] && [ "$2" = mydns-updater ] && [ "$3" = -- ] || exit 99
shift 3
exec "$@"
EOF
cat > "$TASK/bin/systemctl" <<'EOF'
#!/bin/sh
if [ "$1" = show ]; then
    case "$3" in
        --property=ActiveState) cat "$FIXTURE/active" ;;
        --property=InvocationID) cat "$FIXTURE/gen" ;;
        *) exit 99 ;;
    esac
else
    [ "$1" = --no-block ] && [ "$2" = --job-mode=fail ] &&
        [ "$3" = try-restart ] && [ "$4" = fixture.service ] || exit 99
    echo request >> "$FIXTURE/attempts"
    [ ! -f "$FIXTURE/request-fails" ] || exit 1
    echo 22222222222222222222222222222222 > "$FIXTURE/gen"
fi
EOF
cat > "$TASK/probe" <<'EOF'
#!/bin/sh
case "$(cat "$FIXTURE/mode")" in
ok) echo 'HEALTHY: updater progressing or waiting'; exit 0 ;;
bad) echo 'UNHEALTHY: updater progress overdue'; exit 1 ;;
missing) echo 'UNHEALTHY: progress record unavailable'; exit 1 ;;
invalid) echo 'UNHEALTHY: invalid progress record'; exit 1 ;;
dead) echo 'UNHEALTHY: updater process unavailable'; exit 1 ;;
secret) echo 'private-password-body'; exit 1 ;;
failed) echo 'private-password-body'; exit 126 ;;
timeout) sleep 10; exit 1 ;;
stop) echo inactive > "$FIXTURE/active"; echo 'UNHEALTHY: updater progress overdue'; exit 1 ;;
restart) echo 33333333333333333333333333333333 > "$FIXTURE/gen"; echo 'UNHEALTHY: updater progress overdue'; exit 1 ;;
esac
EOF
chmod +x "$TASK/bin/"*
N=0
pass() { N=$((N+1)); echo "PASS recovery $N: $*"; }
fail() { cat "$TASK/log"; echo "FAIL: $*"; exit 1; }
run() { sh "$ROOT/health-recover.sh" "$@" > "$TASK/log" 2>&1 || fail 'unexpected exit'; }
attempts() { [ "$(wc -l < "$TASK/attempts")" -eq "$1" ] || fail 'wrong request count'; }
run; [ ! -s "$TASK/log" ]; attempts 0
pass 'healthy is quiet and never restarted'
echo bad > "$TASK/mode"
run; run; attempts 0
run; attempts 1
grep -q 'RESTART_REQUESTED' "$TASK/log"
pass 'exactly three consecutive overdue probes request restart'
echo ok > "$TASK/mode"
run; grep -q RECOVERED "$TASK/log"
run; [ ! -s "$TASK/log" ]
pass 'healthy confirmation after request logs recovery once'
rm -f "$TASK/state/diagnostic" # Upgrade from old nine-field status without diagnostics.
echo bad > "$TASK/mode"
echo 10599 > "$TASK/now"
run; run; run; attempts 1
echo 10600 > "$TASK/now"
run; attempts 2
pass '600 second minimum interval survives healthy and new invocation'
echo ok > "$TASK/mode"; run
echo bad > "$TASK/mode"; echo 11200 > "$TASK/now"
run; run; run; attempts 3
run; run; run; attempts 3
grep -q 'BLOCKED; reason=RESTART_LIMIT' "$TASK/log"
pass 'fourth attempt within one hour is blocked'
echo 20000 > "$TASK/now"; run; attempts 3
echo ok > "$TASK/mode"; run
echo bad > "$TASK/mode"; run; run; run; attempts 3
pass 'latch remains after time passes and healthy observation'
run --reset
attempts 3
pass 'manual reset clears history without starting target'
echo inactive > "$TASK/active"; run; attempts 3
echo active > "$TASK/active"; echo bad > "$TASK/mode"
run; run; echo stop > "$TASK/mode"; run; attempts 3
pass 'manual stop before/during observation never starts service'
echo active > "$TASK/active"; echo bad > "$TASK/mode"; run; run
echo restart > "$TASK/mode"; run; attempts 3
pass 'observation spanning a new invocation is discarded'
for pair in missing:RECORD_UNAVAILABLE invalid:RECORD_INVALID dead:PROCESS_UNAVAILABLE secret:PROBE_UNKNOWN timeout:PROBE_TIMEOUT failed:PROBE_FAILED; do
    run --reset
    mode=${pair%%:*}; code=${pair#*:}
    echo "$mode" > "$TASK/mode"
    run
    if [ "$mode" = missing ]; then
        [ ! -s "$TASK/log" ] || fail 'startup missing record warned too soon'
        echo 20120 > "$TASK/now"; run
    fi
    grep -q "PROBE_UNAVAILABLE; reason=$code" "$TASK/log" || fail 'missing diagnostic'
    if grep -q private-password "$TASK/log"; then fail 'secret leaked'; fi
    run; [ ! -s "$TASK/log" ] || fail 'duplicate warning'; attempts 3
    echo ok > "$TASK/mode"; run
    grep -q PROBE_RECOVERED "$TASK/log" || fail 'missing probe recovery'
    run; [ ! -s "$TASK/log" ] || fail 'duplicate recovery'
done
pass 'fixed diagnostics, duplicate suppression and recovery; no restart or secrets'
echo invalid > "$TASK/mode"; run
echo secret > "$TASK/mode"; run
grep -q 'reason=PROBE_UNKNOWN' "$TASK/log" || fail 'changed cause not reported'
attempts 3
pass 'changed diagnostic cause is reported without raw output'
run --reset
echo missing > "$TASK/mode"; echo 21000 > "$TASK/now"; run
echo 21119 > "$TASK/now"; run; [ ! -s "$TASK/log" ]
echo 21120 > "$TASK/now"; run
grep -q 'reason=RECORD_UNAVAILABLE' "$TASK/log"
echo bad > "$TASK/mode"; run
grep -q PROBE_RECOVERED "$TASK/log"; attempts 3
pass '120 second grace boundary and restored overdue assessment'
run --reset
echo bad > "$TASK/mode"; run; run
echo missing > "$TASK/mode"; run
echo bad > "$TASK/mode"; run; run; attempts 3
run; attempts 4
pass 'other failure breaks overdue streak'
# First attempt expires exactly at the rolling-window boundary.
run --reset
: > "$TASK/attempts"
echo 30000 > "$TASK/now"; run; run; run; attempts 1
echo ok > "$TASK/mode"; run
echo bad > "$TASK/mode"; echo 30600 > "$TASK/now"; run; run; run; attempts 2
echo ok > "$TASK/mode"; run
echo bad > "$TASK/mode"; echo 31200 > "$TASK/now"; run; run; run; attempts 3
echo ok > "$TASK/mode"; run
echo bad > "$TASK/mode"; echo 33600 > "$TASK/now"; run; run; run; attempts 4
pass 'rolling hour allows another attempt when oldest has expired'
# Persisted boot identity changes reset streak, not rate history.
awk '{$1="previous-boot"; $8=0; $9=0; print}' "$TASK/state/status" > "$TASK/new"
mv "$TASK/new" "$TASK/state/status"
run; run; run; attempts 4
pass 'OS boot change does not erase cooldown'
echo 33000 > "$TASK/now"; run
grep -q CLOCK_MOVED_BACKWARD "$TASK/log"; attempts 4
echo 40000 > "$TASK/now"; run; attempts 4
pass 'backward clock jump latches instead of granting more restarts'
run --reset
touch "$TASK/request-fails"
run; run; run; attempts 5
grep -q RESTART_REQUEST_FAILED "$TASK/log"
run; run; run; attempts 5
pass 'failed restart request is counted and throttled'
echo corrupt > "$TASK/state/status"
if sh "$ROOT/health-recover.sh" > "$TASK/log" 2>&1; then fail 'bad state accepted'; fi
attempts 5
pass 'corrupt history fails closed'
echo "ALL RECOVERY TESTS PASSED ($N checks)"
