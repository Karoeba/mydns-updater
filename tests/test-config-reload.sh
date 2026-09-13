#!/bin/sh
# Run on a Linux Docker host; no real MyDNS traffic or credentials.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
FIXTURE="$(mktemp -d)"
CONTAINER=""
cleanup() {
    [ -z "$CONTAINER" ] || docker rm -f "$CONTAINER" >/dev/null 2>&1 || :
    rm -rf "$FIXTURE"
}
trap cleanup 0
trap 'exit 1' INT TERM
mkdir -p "$FIXTURE/config" "$FIXTURE/state" "$FIXTURE/bin"
cat > "$FIXTURE/bin/curl" <<'EOF'
#!/bin/sh
for argument do url="$argument"; done
case "$url" in
    https://ipv4.mydns.jp/login.html) echo 'Login and IP address notify OK.' ;;
    *) echo 203.0.113.10 ;;
esac
EOF
cat > "$FIXTURE/bin/sleep" <<'EOF'
#!/bin/sh
# Shorten only the wait; leave validation and timestamps unchanged.
exec /bin/sleep 1
EOF
chmod +x "$FIXTURE/bin/"*
write_config() {
    cat > "$FIXTURE/config/next.conf" <<EOF
DEBUG=$1
CHECK_INTERVAL=300
FORCE_UPDATE_INTERVAL=$2
[1]
ID=dummy-account
PASSWORD=dummy-password
DOMAIN=test.example
EOF
    # Host-side rename replaces the inode, as upload tools may do.
    mv -f "$FIXTURE/config/next.conf" "$FIXTURE/config/mydns.conf"
}
logs() { docker logs "$CONTAINER" > "$FIXTURE/log" 2>&1; }
wait_for() {
    attempts=0
    while [ "$attempts" -lt 30 ]; do
        logs
        if grep -Fq "$1" "$FIXTURE/log"; then return 0; fi
        attempts=$((attempts + 1))
        sleep 1
    done
    cat "$FIXTURE/log"
    echo "FAIL: timed out waiting for $1"
    exit 1
}
write_config 0 86400
CONTAINER="$(docker run -d --network none --user "$(id -u):$(id -g)" \
    -v "$ROOT/update.sh:/app/update.sh:ro" \
    -v "$FIXTURE/config:/config:ro" \
    -v "$FIXTURE/state:/state" \
    -v "$FIXTURE/bin:/mock-bin:ro" \
    -e PATH=/mock-bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    alpine:latest sh /app/update.sh)"
STARTED="$(docker inspect -f '{{.State.StartedAt}}' "$CONTAINER")"
wait_for 'MyDNS update: OK'
sleep 2
logs
if grep -Fq '[DEBUG]' "$FIXTURE/log"; then echo 'FAIL: debug initially enabled'; exit 1; fi
write_config 1 600
wait_for '[CONFIG] Invalid FORCE_UPDATE_INTERVAL: using 86400s'
wait_for '[1] [SKIP] IPv4 unchanged; force update not due'
grep -q '^FORCE_UPDATE_INTERVAL=600$' "$FIXTURE/config/mydns.conf"
echo 'PASS: host atomic replacement enables debug and loads invalid interval without restart'
write_config 0 3600
# Allow a cycle already in progress and then check output remains quiet.
sleep 3
logs
before="$(grep -c '\[DEBUG\]' "$FIXTURE/log")"
sleep 3
logs
after="$(grep -c '\[DEBUG\]' "$FIXTURE/log")"
[ "$before" = "$after" ] || { echo 'FAIL: debug did not turn off'; exit 1; }
echo 'PASS: host atomic replacement disables debug without restart'
# Prove the valid new interval was loaded, using the real scheduling clock.
old="$(($(date +%s) - 4000))"
printf 'LAST_IPV4=203.0.113.10\n\n[1]\nLAST_IPV4=203.0.113.10\nLAST_UPDATE=%s\n' "$old" > "$FIXTURE/state/next.conf"
mv -f "$FIXTURE/state/next.conf" "$FIXTURE/state/state.conf"
attempts=0
while [ "$attempts" -lt 30 ]; do
    logs
    count="$(grep -c 'MyDNS update: OK' "$FIXTURE/log")"
    [ "$count" -ge 2 ] && break
    attempts=$((attempts + 1))
    sleep 1
done
[ "$count" -ge 2 ] || { cat "$FIXTURE/log"; echo 'FAIL: new force interval not applied'; exit 1; }
[ "$(docker inspect -f '{{.State.StartedAt}}' "$CONTAINER")" = "$STARTED" ]
[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER")" = true ]
[ "$(docker inspect -f '{{.RestartCount}}' "$CONTAINER")" = 0 ]
echo 'PASS: changed force interval triggers update in the same running container'
echo 'ALL CONFIG RELOAD TESTS PASSED (3 checks)'
