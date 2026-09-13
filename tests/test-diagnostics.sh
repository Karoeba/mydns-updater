#!/bin/sh
set -eu
# Run only inside the disposable test container, after the existing suite.
awk '/^STARTUP_LOGGED=0$/ {exit} {print}' /source/update.sh > /tmp/diagnostic-library.sh
. /tmp/diagnostic-library.sh
TEST_TIME=100
diagnostic_clock() { echo "$TEST_TIME"; }
COUNT=0
pass() { COUNT=$((COUNT + 1)); echo "PASS diagnostics $COUNT: $*"; }
fail() { echo "FAIL diagnostics: $*"; exit 1; }
has() { grep -Fq "$1" /tmp/diagnostic.log || { cat /tmp/diagnostic.log; fail "missing $1"; }; }
quiet() { [ ! -s /tmp/diagnostic.log ] || { cat /tmp/diagnostic.log; fail 'expected quiet log'; }; }
DEBUG=0
failure account.1 'ACCOUNT 1' TIMEOUT transient 'retry' > /tmp/diagnostic.log
has '[WARN] [ACCOUNT 1] TIMEOUT stage=FIRST failures=1 elapsed=0s'
TEST_TIME=400
failure account.1 'ACCOUNT 1' TIMEOUT transient 'retry' > /tmp/diagnostic.log
quiet
pass 'first failure visible, identical second failure quiet with DEBUG=0'
TEST_TIME=699
failure account.1 'ACCOUNT 1' TIMEOUT transient 'retry' > /tmp/diagnostic.log
quiet
TEST_TIME=700
failure account.1 'ACCOUNT 1' TIMEOUT transient 'retry' > /tmp/diagnostic.log
has '[ERROR] [ACCOUNT 1] TIMEOUT stage=PERSISTENT failures=4 elapsed=600s'
pass 'escalation requires both count and elapsed-time threshold'
TEST_TIME=3699
failure account.1 'ACCOUNT 1' TIMEOUT transient 'retry' > /tmp/diagnostic.log
quiet
TEST_TIME=3700
failure account.1 'ACCOUNT 1' TIMEOUT transient 'retry' > /tmp/diagnostic.log
has 'stage=PROLONGED'
pass 'one-hour escalation occurs once'
failure account.1 'ACCOUNT 1' DNS_FAILED transient 'retry' > /tmp/diagnostic.log
has 'DNS_FAILED stage=PROLONGED'
pass 'cause change remains visible and preserves outage duration'
DEBUG=1
failure account.1 'ACCOUNT 1' DNS_FAILED transient 'retry' > /tmp/diagnostic.log
has '[DEBUG] [ACCOUNT 1]'
DEBUG=0
pass 'DEBUG=1 includes repeated failure details'
failure account.2 'ACCOUNT 2' TIMEOUT transient 'retry' > /tmp/diagnostic.log
recovered account.1 'ACCOUNT 1' > /tmp/diagnostic.log
has '[INFO] [ACCOUNT 1] RECOVERED'
[ -f "$WORK_DIR/diagnostic.account.2" ] || fail 'other account history cleared'
recovered account.1 'ACCOUNT 1' > /tmp/diagnostic.log
quiet
pass 'recovery is one-shot and isolated per account'
TEST_TIME=4000
failure service.1 IP_CHECK_URL1 TIMEOUT fallback 'next service' > /tmp/diagnostic.log
TEST_TIME=7600
failure service.1 IP_CHECK_URL1 TIMEOUT fallback 'next service' > /tmp/diagnostic.log
has '[WARN] [IP_CHECK_URL1]'
has 'stage=PROLONGED'
pass 'fallback provider remains WARN even after prolonged failure'
failure config.structure CONFIG INVALID error 'correct configuration' > /tmp/diagnostic.log
has '[ERROR] [CONFIG]'
failure config.structure CONFIG INVALID error 'correct configuration' > /tmp/diagnostic.log
quiet
pass 'structural errors are immediately ERROR without repeated normal logs'
rm -f "$WORK_DIR"/diagnostic.*
TEST_TIME=100
failure short X TIMEOUT transient retry > /tmp/diagnostic.log
TEST_TIME=800
failure short X TIMEOUT transient retry > /tmp/diagnostic.log
quiet
TEST_TIME=801
failure short X TIMEOUT transient retry > /tmp/diagnostic.log
has 'stage=PERSISTENT'
TEST_TIME=790
failure short X TIMEOUT transient retry > /tmp/diagnostic.log
quiet
pass 'two attempts do not escalate at ten minutes; backward clock does not reduce stage'

for mapping in '6 DNS_FAILED' '7 CONNECT_FAILED' '28 TIMEOUT' '35 TLS_FAILED' \
    '60 CERTIFICATE_ERROR' '3 URL_OR_PROTOCOL_ERROR' '23 LOCAL_RESOURCE_ERROR' \
    '56 TRANSFER_FAILED' '99 CURL_ERROR'; do
    set -- $mapping
    CURL_CODE="$1"; HTTP_CODE=000
    if classify_response; then fail 'transport failure classified as success'; fi
    [ "$ERROR_CODE" = "$2" ] || fail 'incorrect curl classification'
done
pass 'curl classifications preserve known and unknown transport errors'
for mapping in '401 HTTP_UNAUTHORIZED' '403 HTTP_FORBIDDEN' '404 HTTP_CLIENT_ERROR' \
    '408 HTTP_TIMEOUT' '429 RATE_LIMITED' '503 HTTP_SERVER_ERROR' '302 HTTP_REDIRECT'; do
    set -- $mapping
    CURL_CODE=22; HTTP_CODE="$1"
    if classify_response; then fail 'HTTP error classified as success'; fi
    [ "$ERROR_CODE" = "$2" ] || fail 'incorrect HTTP classification'
done
CURL_CODE=28; HTTP_CODE=200
classify_response && fail 'partial HTTP 200 overrides timeout'
[ "$ERROR_CODE" = TIMEOUT ] || fail 'transport failure precedence'
pass 'HTTP errors are distinct; transfer failure wins over HTTP status'

mkdir -p /tmp/error-bin
cat > /tmp/error-bin/curl <<'EOF'
#!/bin/sh
output=''
auth=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output) output="$2"; shift ;;
        --write-out) shift ;;
        -u) auth="$2"; shift ;;
        https://*) url="$1" ;;
    esac
    shift
done
code="$MOCK_CODE"; http="$MOCK_HTTP"; body="$MOCK_BODY"
if [ "$MOCK_ROUTING" != 0 ]; then
    case "$url" in
        https://ipv4.mydns.jp/login.html)
            body='Login and IP address notify OK.'
            [ "$MOCK_ROUTING" != 2 ] || body="$MOCK_BODY"
            if [ "$auth" = two:dummy ] && [ "$MOCK_FAIL_TWO" = 1 ]; then
                body='private rejection content'; http=503; code=22
            fi
            ;;
        *) body=203.0.113.70 ;;
    esac
fi
printf '%s' "$body" > "$output"
printf '%s' "$http"
echo 'secret stderr never logged' >&2
exit "$code"
EOF
chmod +x /tmp/error-bin/curl
PATH="/tmp/error-bin:$PATH"
export PATH
MOCK_CODE=0; MOCK_HTTP=200; MOCK_BODY='203.0.113.70'; MOCK_ROUTING=0; MOCK_FAIL_TWO=0
export MOCK_CODE MOCK_HTTP MOCK_BODY MOCK_ROUTING MOCK_FAIL_TWO
request 20 https://test.invalid/
classify_response || fail 'HTTP 200 rejected'
[ "$(cat "$WORK_DIR/response")" = 203.0.113.70 ] || fail 'body/status mixed'
pass 'request captures body and status separately'
IP_CHECK_URL1=https://secret-user:secret-password@test.invalid/one
IP_CHECK_URL2=https://test.invalid/two
IP_CHECK_URL3=https://test.invalid/three
MOCK_BODY='private invalid response'; MOCK_CODE=0
get_current_ipv4 > /tmp/diagnostic.log && fail 'invalid address accepted'
has 'INVALID_IPV4'
has '[IP_CHECK] ALL_SERVICES_FAILED'
if grep -Eq 'secret-|private invalid' /tmp/diagnostic.log; then fail 'secret leaked'; fi
MOCK_BODY=''
get_current_ipv4 > /tmp/diagnostic.log && fail 'empty address accepted'
has 'EMPTY_RESPONSE'
MOCK_BODY=203.0.113.70
get_current_ipv4 > /tmp/diagnostic.log || fail 'valid address rejected'
has '[IP_CHECK_URL1] RECOVERED'
has '[IP_CHECK] RECOVERED'
[ -f "$WORK_DIR/diagnostic.service.2" ] || fail 'untried provider falsely recovered'
pass 'invalid/empty IPv4, total failure, recovery and secret redaction'

rm -f "$WORK_DIR"/diagnostic.* /state/state.conf
cat > /config/mydns.conf <<'EOF'
DEBUG=0
CHECK_INTERVAL=300
FORCE_UPDATE_INTERVAL=3600
[1]
ID=one
PASSWORD=dummy
DOMAIN=one.example
[2]
ID=two
PASSWORD=dummy
DOMAIN=two.example
EOF
MOCK_ROUTING=1; MOCK_FAIL_TWO=1; MOCK_HTTP=200; MOCK_CODE=0
load_config
run_cycle > /tmp/diagnostic.log
has '[ACCOUNT 1: one.example] MyDNS update: OK'
has '[ACCOUNT 2: two.example] HTTP_SERVER_ERROR'
cp /state/state.conf /tmp/error-state
TEST_TIME=$((TEST_TIME + 300))
load_config
run_cycle > /tmp/diagnostic.log
quiet
cmp /tmp/error-state /state/state.conf || fail 'repeat failure changed successful state'
MOCK_FAIL_TWO=0
load_config
run_cycle > /tmp/diagnostic.log
has '[ACCOUNT 2: two.example] RECOVERED'
has '[ACCOUNT 2: two.example] MyDNS update: OK'
failure account.1 'ACCOUNT 1' TIMEOUT transient retry > /tmp/diagnostic.log
run_cycle > /tmp/diagnostic.log
has 'NO_UPDATE_REQUIRED'
[ ! -f "$WORK_DIR/diagnostic.account.1" ] || fail 'obsolete failure retained'
pass 'real cycle isolates recovery and clears failures when notification is no longer required'
MOCK_ROUTING=2; MOCK_BODY='private unrecognized success'; MOCK_HTTP=200
rm /state/state.conf
run_cycle > /tmp/diagnostic.log
has 'SUCCESS_NOT_CONFIRMED'
if grep -q 'private unrecognized' /tmp/diagnostic.log; then fail 'raw MyDNS body leaked'; fi
pass 'HTTP 200 without success text is not labelled authentication failure'
track_target service.1 https://old.invalid IP_CHECK_URL1
failure service.1 IP_CHECK_URL1 TIMEOUT fallback retry > /tmp/diagnostic.log
track_target service.1 https://new.invalid IP_CHECK_URL1 > /tmp/diagnostic.log
has 'TARGET_CHANGED'
[ ! -f "$WORK_DIR/diagnostic.service.1" ] || fail 'old target failure retained'
pass 'changed endpoint resets history without claiming recovery'
sed 's/CHECK_INTERVAL=300/CHECK_INTERVAL=0/' /config/mydns.conf > /tmp/error-conf
cp /tmp/error-conf /config/mydns.conf
load_config > /tmp/diagnostic.log
has 'Invalid CHECK_INTERVAL'
load_config > /tmp/diagnostic.log
quiet
sed 's/CHECK_INTERVAL=0/CHECK_INTERVAL=300/' /config/mydns.conf > /tmp/error-conf
cp /tmp/error-conf /config/mydns.conf
load_config
finish_config_diagnostics > /tmp/diagnostic.log
has '[CONFIG] RECOVERED'
pass 'invalid setting is deduplicated and recovery is logged'
sed 's/DEBUG=0/DEBUG=yes/' /config/mydns.conf > /tmp/error-conf
cp /tmp/error-conf /config/mydns.conf
load_config > /tmp/diagnostic.log 2>&1
has 'Invalid DEBUG: using 0'
load_config > /tmp/diagnostic.log 2>&1
quiet
pass 'repeated invalid DEBUG stays quiet without numeric shell errors'
DEBUG=0
if (fatal '[STATE] SAVE_FAILED; check storage') > /tmp/diagnostic.log; then fail 'fatal returned success'; fi
has '[FATAL] [STATE] SAVE_FAILED'
pass 'fatal storage failure is visible with debug off and exits'
echo "ALL DIAGNOSTIC TESTS PASSED ($COUNT checks)"
