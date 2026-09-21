#!/bin/sh
# Disposable CI-only integration of the actual helper and updater.
set -eu
[ "${GITHUB_ACTIONS:-}" = true ] || exit 1
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TASK="$(mktemp -d)"; ID=""
cleanup() {
    [ -z "$ID" ] || docker rm -f "$ID" >/dev/null 2>&1 || :
    rm -rf "$TASK"
}
trap cleanup 0
trap 'exit 1' INT TERM
mkdir -p "$TASK/state" "$TASK/bin"
DOCKER_BIN="$(command -v docker)"
export MYDNS_DOCKER_BIN="$DOCKER_BIN" MYDNS_RECOVERY_DIR="$TASK/state" FIXTURE="$TASK"
cat > "$TASK/bin/date" <<'EOF'
#!/bin/sh
if [ "$1" = +%s ]; then cat "$FIXTURE/now"; else /bin/date "$@"; fi
EOF
chmod +x "$TASK/bin/date"
export PATH="$TASK/bin:$PATH"
echo 10000 > "$TASK/now"
ID="$(docker create --network none --restart unless-stopped \
    --label mydns.test=docker-recovery-policy alpine:3.23 sh /app/update.sh)"
export MYDNS_RECOVERY_CONTAINER="$ID"
mkdir -p "$TASK/app"
cp "$ROOT/update.sh" "$TASK/app/update.sh"
docker cp "$TASK/app" "$ID":/app
docker start "$ID" >/dev/null
n=0
until docker exec "$ID" sh /app/update.sh --healthcheck; do
    [ "$n" -lt 20 ] || exit 1
    sleep 1; n=$((n+1))
done
run() { sh "$ROOT/docker-health-recover.sh" --once; }
run
before="$(docker inspect --format '{{.RestartCount}}' "$ID")"
token="$(docker exec "$ID" sh /app/update.sh --docker-recovery-status)"
# A healthy process refuses recovery even if a caller submits its current token.
if docker exec "$ID" sh /app/update.sh --docker-recovery-request "${token#* }"; then exit 1; fi
[ "$(docker inspect --format '{{.RestartCount}}' "$ID")" = "$before" ]
sleep 11
pid="$(docker inspect --format '{{.State.Pid}}' "$ID")"
if [ "$(id -u)" -eq 0 ]; then kill -STOP "$pid"; else sudo kill -STOP "$pid"; fi
# Change only this disposable container's progress deadline.
docker exec "$ID" sh -c 'awk '"'"'{$3=0; print}'"'"' /tmp/mydns-updater.health > /tmp/expired; mv /tmp/expired /tmp/mydns-updater.health'
run
echo 10030 > "$TASK/now"; run
[ "$(docker inspect --format '{{.RestartCount}}' "$ID")" = "$before" ]
echo 10060 > "$TASK/now"; run
n=0
until [ "$(docker inspect --format '{{.RestartCount}}' "$ID")" -gt "$before" ]; do
    [ "$n" -lt 20 ] || exit 1
    sleep 1; n=$((n+1))
done
n=0
until docker exec "$ID" sh /app/update.sh --healthcheck; do
    [ "$n" -lt 20 ] || exit 1
    sleep 1; n=$((n+1))
done
run > "$TASK/log"
grep -q RECOVERED "$TASK/log"
echo 'PASS: actual host policy requests recovery after three probes and confirms healthy'
docker stop -t 5 "$ID" >/dev/null
echo 10120 > "$TASK/now"; run
[ "$(docker inspect --format '{{.State.Status}}' "$ID")" = exited ]
sh "$ROOT/docker-health-recover.sh" --reset
[ "$(docker inspect --format '{{.State.Status}}' "$ID")" = exited ]
echo 'PASS: manual stop and history reset never start container'
echo 'ALL DOCKER RECOVERY INTEGRATION TESTS PASSED'
