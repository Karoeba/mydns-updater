#!/bin/sh
set -eu
awk '/^STARTUP_LOGGED=0$/ {exit} {print}' /source/update.sh > /tmp/health-library.sh
. /tmp/health-library.sh
COUNT=0
pass() { COUNT=$((COUNT + 1)); echo "PASS health $COUNT: $*"; }
fail() { cat /tmp/health.log; echo "FAIL health: $*"; exit 1; }
probe_bad() {
    if sh /source/update.sh --healthcheck > /tmp/health.log; then fail 'unexpected healthy'; fi
    grep -Fq "$1" /tmp/health.log || fail 'wrong failure reason'
}
probe_ok() {
    sh /source/update.sh --healthcheck > /tmp/health.log || fail 'unexpected unhealthy'
}
rm -f "$HEALTH_FILE"
probe_bad 'unavailable'
pass 'missing progress record is unhealthy'
printf 'private-invalid-data\n' > "$HEALTH_FILE"
probe_bad 'invalid progress record'
grep -q private /tmp/health.log && fail 'record contents leaked'
pass 'malformed record is rejected without exposing contents'
HEALTH_BOOT="$(cat /proc/sys/kernel/random/boot_id)"
HEALTH_ENABLED=1
HEALTH_START="$(health_process_start "$$")"
health_progress 0
probe_ok
pass 'live process and current progress are healthy'
cp "$HEALTH_FILE" /tmp/health-before
cp /state/state.conf /tmp/health-state-before
cp /config/accounts.conf /tmp/health-account-before
: > /tmp/mock/updates
: > /tmp/mock/checks
probe_ok
cmp "$HEALTH_FILE" /tmp/health-before
cmp /state/state.conf /tmp/health-state-before
cmp /config/accounts.conf /tmp/health-account-before
[ ! -s /tmp/mock/updates ] && [ ! -s /tmp/mock/checks ] || fail 'probe contacted network'
pass 'probe does not refresh progress, update DNS or modify state/config'
printf '%s %s %s %s\n' "$$" "$HEALTH_START" "$(($(health_clock)-1))" "$HEALTH_BOOT" > "$HEALTH_FILE"
probe_bad 'progress overdue'
pass 'stalled progress is unhealthy even with a live process'
printf '%s 0 %s %s\n' "$$" "$(($(health_clock)+120))" "$HEALTH_BOOT" > "$HEALTH_FILE"
probe_bad 'process unavailable'
pass 'stale record with reused process id is rejected'
printf '2147483647 1 999999999 %s\n' "$HEALTH_BOOT" > "$HEALTH_FILE"
probe_bad 'process unavailable'
pass 'dead process is unhealthy'
health_progress 86400
probe_ok
read -r pid start deadline boot < "$HEALTH_FILE"
[ "$deadline" -ge "$(($(health_clock)+86400))" ] || fail 'long wait omitted'
pass 'maximum configured wait is accounted for'
health_progress 30
read -r pid start deadline boot < "$HEALTH_FILE"
[ "$deadline" -ge "$(($(health_clock)+149))" ] || fail 'request timeout budget omitted'
pass 'request time budget includes scheduling margin'
health_progress 0
TZ=UTC probe_ok
TZ=America/New_York probe_ok
pass 'probe is independent of log timezone'
# Run the actual cycle with unavailable external services, retaining liveness.
printf 'DEBUG=0\n' > "$CONFIG"
printf '[1]\nID=one\nPASSWORD=dummy\nDOMAIN=one.example\n' > "$ACCOUNTS_CONFIG"
PATH="/tmp/test-bin:$PATH"
export PATH
touch /tmp/mock/fail-service-1 /tmp/mock/fail-service-2 /tmp/mock/fail-service-3
load_config
run_cycle > /tmp/health.log
health_progress 300
probe_ok
rm /tmp/mock/fail-service-1 /tmp/mock/fail-service-2 /tmp/mock/fail-service-3
pass 'external service failure does not mean the loop is stalled'
echo "ALL HEALTHCHECK TESTS PASSED ($COUNT checks)"
