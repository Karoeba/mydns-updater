#!/bin/sh
# Disposable integration of the actual helper and updater; no real accounts.
set -eu
case "${1:-}" in
    --disposable-test) [ "$(id -u)" -eq 0 ] || { echo 'Run with sudo'; exit 1; } ;;
    "") [ "${GITHUB_ACTIONS:-}" = true ] || exit 1 ;;
    *) exit 1 ;;
esac
DOCKER_BIN="$(command -v docker)"
case "$DOCKER_BIN" in /*) ;; *) echo 'Docker unavailable'; exit 1 ;; esac
docker() { "$DOCKER_BIN" --host unix:///var/run/docker.sock "$@"; }
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TASK="$(mktemp -d)"; ID=""
IMAGE="mydns-recovery-image-test:$(basename "$TASK" | tr '[:upper:]' '[:lower:]')"
cleanup() {
    [ -z "$ID" ] || docker rm -f "$ID" >/dev/null 2>&1 || :
    docker image rm "$IMAGE" >/dev/null 2>&1 || :
    rm -rf "$TASK"
}
trap cleanup 0
trap 'exit 1' INT TERM
mkdir -p "$TASK/state" "$TASK/bin"
export MYDNS_DOCKER_BIN="$DOCKER_BIN" MYDNS_RECOVERY_DIR="$TASK/state" FIXTURE="$TASK"
docker build -t "$IMAGE" "$ROOT"
ID="$(docker create --network none --restart unless-stopped \
    --label mydns.test=docker-recovery-policy "$IMAGE")"
export MYDNS_RECOVERY_CONTAINER="$ID"
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
case "$pid" in ""|*[!0-9]*) exit 1 ;; esac
[ "$pid" -gt 1 ] || exit 1
[ "$(docker inspect --format '{{index .Config.Labels "mydns.test"}}' "$ID")" = docker-recovery-policy ] || exit 1
start="$(docker exec "$ID" awk '{sub(/^.*\) /,""); print $20}' /proc/1/stat)"
[ "$(awk '{sub(/^.*\) /,""); print $20}' "/proc/$pid/stat")" = "$start" ] || exit 1
if [ "$(id -u)" -eq 0 ]; then kill -STOP "$pid"; else sudo kill -STOP "$pid"; fi
# Change only this disposable container's progress deadline.
docker exec "$ID" sh -c 'awk '"'"'{$3=0; print}'"'"' /tmp/mydns-updater.health > /tmp/expired; mv /tmp/expired /tmp/mydns-updater.health'
# A request based on the earlier progress record must be rejected.
if docker exec "$ID" sh /app/update.sh --docker-recovery-request "${token#* }"; then exit 1; fi
run
sleep 30; run
[ "$(docker inspect --format '{{.RestartCount}}' "$ID")" = "$before" ]
sleep 30; run
n=0
until [ "$(docker inspect --format '{{.RestartCount}}' "$ID")" -gt "$before" ]; do
    [ "$n" -lt 20 ] || { cat "$TASK/state/status"; docker logs "$ID"; exit 1; }
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
run
[ "$(docker inspect --format '{{.State.Status}}' "$ID")" = exited ]
sh "$ROOT/docker-health-recover.sh" --reset
[ ! -e "$TASK/state/status" ]
[ "$(docker inspect --format '{{.State.Status}}' "$ID")" = exited ]
echo 'PASS: manual stop and history reset never start container'
echo 'ALL DOCKER RECOVERY INTEGRATION TESTS PASSED'
