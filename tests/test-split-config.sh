#!/bin/sh
set -eu
# Disposable container only. Real loader/cycle, with network mock from the suite.
awk '/^STARTUP_LOGGED=0$/ {exit} {print}' /source/update.sh > /tmp/split-library.sh
. /tmp/split-library.sh
PATH="/tmp/test-bin:$PATH"
export PATH
COUNT=0
pass() { COUNT=$((COUNT + 1)); echo "PASS split $COUNT: $*"; }
fail() { cat /tmp/split.log; echo "FAIL split: $*"; exit 1; }
baseline() {
    printf 'DEBUG=0\nCHECK_INTERVAL=300\nFORCE_UPDATE_INTERVAL=3600\n' > "$CONFIG"
    printf '[1]\nID=one\nPASSWORD=dummy\nDOMAIN=one.example\n' > "$ACCOUNTS_CONFIG"
    # Observe a valid reload between independent error scenarios.
    load_config > /tmp/split.log
    finish_config_diagnostics >> /tmp/split.log
}
cycle() {
    : > /tmp/mock/updates
    : > /tmp/mock/checks
    if load_config; then finish_config_diagnostics; run_cycle; fi
}
rejected() {
    cp /state/state.conf /tmp/split-state
    cycle > /tmp/split.log 2>&1
    [ ! -s /tmp/mock/checks ] && [ ! -s /tmp/mock/updates ] || fail 'invalid config communicated'
    cmp -s /state/state.conf /tmp/split-state || fail 'invalid config changed state'
    grep -Fq '[CONFIG]' /tmp/split.log || fail 'missing config error'
    if grep -Eq 'dummy|private-value' /tmp/split.log; then fail 'value leaked'; fi
}
baseline
rm -f /tmp/mock/fail-* /tmp/mock/reject-* /tmp/mock/invalid-* /state/state.conf
echo 203.0.113.80 > /tmp/mock/ip
cycle > /tmp/split.log
grep -Fq 'MyDNS update: OK' /tmp/split.log || fail 'split config did not update'
pass 'split files initialize account'
cp "$ACCOUNTS_CONFIG" /tmp/split-accounts
rm "$ACCOUNTS_CONFIG"
rejected
grep -Fq 'config/accounts.conf' /tmp/split.log || fail 'missing filename'
cp /tmp/split-accounts "$ACCOUNTS_CONFIG"
cycle > /tmp/split.log
grep -Fq 'RECOVERED' /tmp/split.log || fail 'missing recovery'
[ ! -s /tmp/mock/updates ] || fail 'restored config lost state'
pass 'missing accounts file blocks cycle and recovers with saved state'
cp "$CONFIG" /tmp/split-common
rm "$CONFIG"
rejected
grep -Fq 'config/mydns.conf' /tmp/split.log || fail 'missing common filename'
cp /tmp/split-common "$CONFIG"
pass 'missing common file blocks cycle'
cat "$ACCOUNTS_CONFIG" >> "$CONFIG"
rejected
baseline
pass 'legacy mixed configuration is rejected without using credentials'
printf 'DEBUG=1\n' >> "$ACCOUNTS_CONFIG"
rejected
baseline
pass 'common settings in accounts file are rejected'
printf 'UNKNOWN=private-value\n' >> "$CONFIG"
rejected
baseline
printf 'UNKNOWN=private-value\n' >> "$ACCOUNTS_CONFIG"
rejected
baseline
pass 'unknown keys report location without exposing values'
for count in 2 3; do
    baseline
    i=1
    while [ "$i" -lt "$count" ]; do cat /tmp/split-accounts >> "$ACCOUNTS_CONFIG"; i=$((i + 1)); done
    rejected
done
baseline
pass 'duplicate section repeated twice or three times is rejected'
for file in "$CONFIG" "$ACCOUNTS_CONFIG"; do
    awk '{printf "%s\r\n", $0}' "$file" > /tmp/split-next
    mv /tmp/split-next "$file"
done
cycle > /tmp/split.log
[ ! -s /tmp/mock/updates ] || fail 'CRLF lost saved state'
grep -Fq 'skipping this cycle' /tmp/split.log && fail 'CRLF rejected'
pass 'both files accept CRLF and retain account state'
baseline
printf 'DEBUG=1\n' > /tmp/split-next
mv /tmp/split-next "$CONFIG"
cycle > /tmp/split.log
grep -Fq '[DEBUG] [CHECK]' /tmp/split.log || fail 'common replacement not loaded'
cat /tmp/split-accounts > /tmp/split-next
printf '[2]\nID=two\nPASSWORD=dummy\nDOMAIN=two.example\n' >> /tmp/split-next
mv /tmp/split-next "$ACCOUNTS_CONFIG"
cycle > /tmp/split.log
[ "$(cat /tmp/mock/updates)" = two ] || fail 'account replacement did not update only added account'
pass 'independent replacements reload in same process'
baseline
: > "$ACCOUNTS_CONFIG"
rejected
pass 'empty account file blocks cycle without discarding state'
echo "ALL SPLIT CONFIG TESTS PASSED ($COUNT checks)"
