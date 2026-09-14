#!/bin/sh
set -eu
mkdir -p /app /config /state /tmp/mock /tmp/test-bin
# These paths exist only inside this dedicated disposable test container.
rm -f /state/state.conf /tmp/mock/* /tmp/test-bin/*
cp /source/update.sh /app/update.sh
cp /suite/mock-curl.sh /tmp/test-bin/curl
cat > /tmp/test-bin/sleep <<'EOF'
#!/bin/sh
# Finish one real main-loop iteration. Each scenario starts a fresh updater.
echo "$1" > /tmp/mock/sleep
kill -TERM "$PPID"
exit 0
EOF
cat > /tmp/test-bin/date <<'EOF'
#!/bin/sh
if [ "$#" -eq 1 ] && [ "$1" = +%s ]; then
    cat /tmp/mock/now
elif [ -f /tmp/mock/display-epoch ]; then
    exec /bin/date -d "@$(cat /tmp/mock/display-epoch)" "$@"
else
    exec /bin/date "$@"
fi
EOF
cat > /tmp/test-bin/mv <<'EOF'
#!/bin/sh
[ ! -f /tmp/mock/fail-save ] || exit 1
exec /bin/mv "$@"
EOF
chmod +x /tmp/test-bin/*
PATH="/tmp/test-bin:$PATH"
export PATH
echo 1800000000 > /tmp/mock/now
echo 203.0.113.10 > /tmp/mock/ip
COUNT=0
pass() { COUNT=$((COUNT + 1)); echo "PASS $COUNT: $*"; }
fail() { echo "FAIL: $*"; exit 1; }
eq() { [ "$1" = "$2" ] || fail "expected [$2], got [$1]"; }
value() {
    awk -v wanted="$1" -v key="$2" '
        /^\[/ {section=substr($0,2,length($0)-2); next}
        section==wanted && index($0,key "=")==1 {print substr($0,length(key)+2)}
    ' /state/state.conf
}
config() {
    cat > /config/mydns.conf <<'EOF'
CHECK_INTERVAL=300
FORCE_UPDATE_INTERVAL=86400
EOF
    cat > /config/accounts.conf <<'EOF'
[1]
ID=one
PASSWORD=dummy
DOMAIN=one.example
[2]
ID=two
PASSWORD=dummy
DOMAIN=two.example
EOF
}
cycle() {
    : > /tmp/mock/updates
    : > /tmp/mock/checks
    sh /app/update.sh > /tmp/cycle.log 2>&1 || {
        cat /tmp/cycle.log
        fail 'updater exited with an error'
    }
    cat /tmp/cycle.log
}
updates() { tr '\n' ',' < /tmp/mock/updates; }
checks() { tr '\n' ',' < /tmp/mock/checks; }
sh -n /app/update.sh
pass 'shell syntax'
config
touch /tmp/mock/check-immediate
cycle
eq "$(updates)" 'one,two,'
eq "$(value '' LAST_IPV4)" 203.0.113.10
eq "$(value 1 LAST_UPDATE)" 1800000000
[ ! -f /tmp/mock/immediate-failed ] || fail 'success was not saved immediately'
pass 'initial update and immediate state-file replacement before next account'
cycle
eq "$(updates)" ''
pass 'fresh process reloads saved state and skips unchanged IP'
echo 203.0.113.20 > /tmp/mock/ip
touch /tmp/mock/fail-two
echo 1800000300 > /tmp/mock/now
cycle
eq "$(updates)" 'one,two,'
eq "$(value 1 LAST_IPV4)" 203.0.113.20
eq "$(value 2 LAST_IPV4)" 203.0.113.10
eq "$(value 2 LAST_UPDATE)" 1800000000
eq "$(value '' LAST_IPV4)" 203.0.113.10
cp /state/state.conf /reports/partial-failure.state.conf
pass 'partial failure preserves failed account and global state'
cycle
eq "$(updates)" 'two,'
pass 'restart retries only failed account'
echo 203.0.113.10 > /tmp/mock/ip
cycle
eq "$(updates)" 'one,'
eq "$(value 1 LAST_IPV4)" 203.0.113.10
pass 'A to B to A updates only account still recorded at B'
rm /tmp/mock/fail-two
echo 203.0.113.20 > /tmp/mock/ip
cycle
eq "$(updates)" 'one,two,'
eq "$(value '' LAST_IPV4)" 203.0.113.20
pass 'all-account convergence updates global IP'
# Make only account 2 due; account 1 remains recent.
awk '/^\[/{s=$0} s=="[2]" && /^LAST_UPDATE=/{ $0="LAST_UPDATE=1799900000" } {print}' \
    /state/state.conf > /tmp/edited-state
/bin/mv /tmp/edited-state /state/state.conf
cycle
eq "$(updates)" 'two,'
pass 'force update is evaluated per account'
touch /tmp/mock/fail-service-1 /tmp/mock/invalid-service-2
cycle
eq "$(checks)" '1,2,3,'
eq "$(updates)" ''
pass 'network failure and malformed IPv4 fall back to third service'
cp /state/state.conf /tmp/before-state
touch /tmp/mock/fail-service-3
cycle
eq "$(updates)" ''
cmp /state/state.conf /tmp/before-state || fail 'state changed after all IP checks failed'
pass 'all IP services fail without updates or state changes'
rm /tmp/mock/fail-service-1 /tmp/mock/invalid-service-2 /tmp/mock/fail-service-3
config
sed 's/CHECK_INTERVAL=300/CHECK_INTERVAL=-1/;s/FORCE_UPDATE_INTERVAL=86400/FORCE_UPDATE_INTERVAL=0/' \
    /config/mydns.conf > /tmp/config
cp /tmp/config /config/mydns.conf
cycle
eq "$(cat /tmp/mock/sleep)" 300
grep -q 'Invalid FORCE_UPDATE_INTERVAL' /tmp/cycle.log || fail 'missing force interval warning'
pass 'invalid interval values revert to defaults'
config
sed 's/CHECK_INTERVAL=300/CHECK_INTERVAL=86400/;s/FORCE_UPDATE_INTERVAL=86400/FORCE_UPDATE_INTERVAL=3600/' \
    /config/mydns.conf > /tmp/config
cp /tmp/config /config/mydns.conf
cycle
eq "$(cat /tmp/mock/sleep)" 86400
grep -q 'FORCE_UPDATE_INTERVAL < CHECK_INTERVAL' /tmp/cycle.log || fail 'missing interval order warning'
pass 'force interval shorter than check interval is corrected'
config
awk '{printf "%s\r\n", $0}' /config/mydns.conf > /tmp/config
cp /tmp/config /config/mydns.conf
cycle
eq "$(updates)" ''
pass 'CRLF configuration'
config
{ printf 'IP_CHECK_URL1=https://test.invalid/one\nIP_CHECK_URL2=https://test.invalid/two\nIP_CHECK_URL3=https://test.invalid/three\n'; cat /config/mydns.conf; } > /tmp/config
cp /tmp/config /config/mydns.conf
touch /tmp/mock/fail-service-1 /tmp/mock/fail-service-2
cycle
eq "$(checks)" '1,2,3,'
pass 'custom IP check services'
rm /tmp/mock/fail-service-1 /tmp/mock/fail-service-2
config
echo 'broken state' > /state/state.conf
cycle
eq "$(updates)" 'one,two,'
pass 'malformed state causes initialization'
awk '/^\[2\]/{exit} {print}' /state/state.conf > /tmp/edited-state
/bin/mv /tmp/edited-state /state/state.conf
cycle
eq "$(updates)" 'two,'
pass 'missing account state initializes only that account'
echo 203.0.113.30 > /tmp/mock/ip
touch /tmp/mock/reject-two
cycle
eq "$(value 2 LAST_IPV4)" 203.0.113.20
eq "$(value '' LAST_IPV4)" 203.0.113.20
pass 'HTTP success without MyDNS success text is rejected'
rm /tmp/mock/reject-two
cycle
eq "$(updates)" 'two,'
grep -Eq '[0-9]{2}:[0-9]{2}:[0-9]{2} JST' /tmp/cycle.log || fail 'JST log missing'
pass 'retry succeeds and logs include JST'
cp /state/state.conf /tmp/before-state
echo 203.0.113.40 > /tmp/mock/ip
touch /tmp/mock/fail-save
: > /tmp/mock/updates
if sh /app/update.sh > /tmp/cycle.log 2>&1; then
    fail 'save failure did not stop updater'
fi
cat /tmp/cycle.log
eq "$(updates)" 'one,'
cmp /state/state.conf /tmp/before-state || fail 'failed save damaged previous state'
pass 'save failure stops before next account and preserves previous file'
rm /tmp/mock/fail-save
cp /state/state.conf /reports/final.state.conf

# Freeze displayed dates independently of the scheduling clock.
echo 203.0.113.30 > /tmp/mock/ip
echo 1705320000 > /tmp/mock/display-epoch
timezone_config() {
    config
    { printf 'TZ=%s\n' "$1"; cat /config/mydns.conf; } > /tmp/config
    cp /tmp/config /config/mydns.conf
}
expect_log() { grep -Fq "$1" /tmp/cycle.log || fail "missing log: $1"; }

config
cycle
expect_log '2024-01-15 21:00:00 JST [STARTUP]'
expect_log 'TZ=Asia/Tokyo'
if grep -q 'Invalid TZ' /tmp/cycle.log; then fail 'omission warned'; fi
pass 'omitted timezone defaults to Tokyo'
timezone_config Asia/Tokyo
cycle
expect_log '2024-01-15 21:00:00 JST [STARTUP]'
pass 'explicit Tokyo timezone'
cp /state/state.conf /tmp/timezone-before
timezone_config UTC
cycle
expect_log '2024-01-15 12:00:00 UTC [STARTUP]'
eq "$(updates)" ''
cmp /state/state.conf /tmp/timezone-before || fail 'timezone changed saved state'
pass 'UTC display changes without changing saved timestamps or update decision'
timezone_config America/New_York
cycle
expect_log '2024-01-15 07:00:00 EST [STARTUP]'
echo 1721044800 > /tmp/mock/display-epoch
cycle
expect_log '2024-07-15 08:00:00 EDT [STARTUP]'
eq "$(updates)" ''
pass 'New York winter and summer offsets and labels'
echo 1705320000 > /tmp/mock/display-epoch
for zone in '' Mars/Olympus ../etc/passwd /etc/passwd zone.tab Asia 'JST-9' 'UTC;exit'; do
    timezone_config "$zone"
    cycle
    expect_log '2024-01-15 21:00:00 JST [WARN] [CONFIG] INVALID_TZ stage=FIRST failures=1 elapsed=0s; Invalid TZ: using Asia/Tokyo'
    expect_log 'TZ=Asia/Tokyo'
done
pass 'empty unknown and invalid timezone values fall back safely'
timezone_config UTC
awk '{printf "%s\r\n", $0}' /config/mydns.conf > /tmp/config
cp /tmp/config /config/mydns.conf
cycle
expect_log '2024-01-15 12:00:00 UTC [STARTUP]'
pass 'CRLF timezone configuration'
# The epoch-based force interval remains active with another display timezone.
awk '/^\[/{s=$0} s=="[2]" && /^LAST_UPDATE=/{ $0="LAST_UPDATE=1799900000" } {print}' \
    /state/state.conf > /tmp/edited-state
/bin/mv /tmp/edited-state /state/state.conf
cycle
eq "$(updates)" 'two,'
eq "$(value 2 LAST_UPDATE)" "$(cat /tmp/mock/now)"
pass 'force update keeps using UNIX seconds under UTC'


rm /tmp/mock/display-epoch

# Check debug output without exposing credentials.
debug_config() {
    config
    { printf 'DEBUG=%s\n' "$1"; cat /config/mydns.conf; } > /tmp/config
    cp /tmp/config /config/mydns.conf
}
echo 203.0.113.30 > /tmp/mock/ip
debug_config 1
cycle
grep -Fq '[DEBUG] [CHECK] IPv4 check started' /tmp/cycle.log || fail 'missing check-start log'
grep -Fq '[DEBUG] [CHECK] IPv4 acquired: 203.0.113.30' /tmp/cycle.log || fail 'missing acquired log'
grep -Fq '[1] [SKIP]' /tmp/cycle.log || fail 'missing account skip log'
eq "$(updates)" ''
if grep -Eq 'dummy|one:|two:|Login and IP' /tmp/cycle.log; then fail 'credential or response leaked'; fi
pass 'debug check and skip logs without credentials'
debug_config 0
cycle
if grep -Fq '[DEBUG]' /tmp/cycle.log; then fail 'disabled debug logged'; fi
config
cycle
if grep -Fq '[DEBUG]' /tmp/cycle.log; then fail 'omitted debug logged'; fi
pass 'debug off and omitted preserve quiet logs'
for setting in '' 2 yes -1; do
    debug_config "$setting"
    cycle
    grep -Fq 'Invalid DEBUG: using 0' /tmp/cycle.log || fail 'missing invalid DEBUG warning'
    if grep -Fq '[DEBUG]' /tmp/cycle.log; then fail 'invalid debug enabled'; fi
done
pass 'invalid debug values warn and disable'
debug_config 1
rm /state/state.conf
cycle
grep -Fq '[UPDATE] account state missing' /tmp/cycle.log || fail 'missing initial reason'
echo 203.0.113.50 > /tmp/mock/ip
cycle
grep -Fq '[UPDATE] IPv4 changed' /tmp/cycle.log || fail 'missing IP change reason'
echo 1800090000 > /tmp/mock/now
cycle
grep -Fq '[UPDATE] force update interval reached' /tmp/cycle.log || fail 'missing force reason'
pass 'debug identifies initial IP-change and force-update reasons'


# Malformed account activation must not replace another account's identity.
config
echo 203.0.113.60 > /tmp/mock/ip
before_two_time="$(value 2 LAST_UPDATE)"
sed '/^DOMAIN=two.example$/s/^/#/' /config/accounts.conf > /tmp/config
cp /tmp/config /config/accounts.conf
cycle
eq "$(updates)" 'one,'
grep -Fq '[2] MyDNS update: CONFIG ERROR' /tmp/cycle.log || fail 'missing account configuration error'
eq "$(value 2 LAST_UPDATE)" "$before_two_time"
eq "$(value 2 LAST_IPV4)" 203.0.113.50
pass 'missing domain skips only incomplete account and preserves its success record'
cp /state/state.conf /tmp/activation-before
expect_rejected_config() {
    cycle
    eq "$(updates)" ''
    eq "$(checks)" ''
    grep -Fq '[CONFIG]' /tmp/cycle.log || fail 'missing configuration warning'
    grep -Fq 'skipping this cycle' /tmp/cycle.log || fail 'invalid configuration did not skip cycle'
    cmp /state/state.conf /tmp/activation-before || fail 'invalid configuration changed state'
    if grep -Eq 'dummy|one.example|two.example' /tmp/cycle.log; then fail 'configuration contents leaked'; fi
}
config
sed '/^\[2\]$/s/^/#/' /config/accounts.conf > /tmp/config
cp /tmp/config /config/accounts.conf
expect_rejected_config
pass 'commented section with three active fields is rejected before any communication'
config
sed '/^\[2\]$/s/^/#/;/^ID=two$/s/^/#/;/^PASSWORD=dummy$/s/^/#/' /config/accounts.conf > /tmp/config
cp /tmp/config /config/accounts.conf
expect_rejected_config
pass 'commented section with only active domain is rejected'
for field in ID PASSWORD DOMAIN; do
    config
    printf '%s=duplicate-value\n' "$field" >> /config/accounts.conf
    expect_rejected_config
    grep -Fq "duplicate $field" /tmp/cycle.log || fail 'missing duplicate key reason'
done
pass 'duplicate account keys without a commented header are rejected'
config
{ echo 'ID=orphan'; cat /config/accounts.conf; } > /tmp/config
cp /tmp/config /config/accounts.conf
expect_rejected_config
pass 'account fields before first section are rejected'
# Fully disabled blocks are valid; a following active header resets the boundary.
config
cat >> /config/accounts.conf <<'EOF'
#[3]
#ID=three
#PASSWORD=dummy
#DOMAIN=three.example
[4]
ID=four
PASSWORD=dummy
DOMAIN=four.example
EOF
cycle
eq "$(updates)" 'two,four,'
eq "$(value 4 LAST_IPV4)" 203.0.113.60
pass 'fully commented account is ignored and following account remains valid'
config
cycle
eq "$(updates)" ''
if grep -Fq '[CONFIG]' /tmp/cycle.log; then fail 'corrected configuration still rejected'; fi
pass 'corrected configuration resumes normally with existing state'

echo "ALL TESTS PASSED ($COUNT checks)"
