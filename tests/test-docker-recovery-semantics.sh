#!/bin/sh
# CI-only behavior probes. Never address an existing user container.
set -eu
[ "${GITHUB_ACTIONS:-}" = true ] || { echo 'Use only in disposable GitHub Actions'; exit 1; }
IDS=""
cleanup() { for container_id in $IDS; do docker rm -f "$container_id" >/dev/null 2>&1 || :; done; }
trap cleanup 0
trap 'exit 1' INT TERM
docker version
docker compose version
docker pull alpine:3.23
new_container() {
    ID="$(docker create --network none --label mydns.test=docker-recovery-semantics "$@" alpine:3.23 sh -c 'sleep "${EXIT_DELAY:-600}"; exit 1')"
    IDS="$IDS $ID"
}
state() { docker inspect --format '{{.State.Status}}' "$ID"; }
wait_state() {
    wanted="$1"; n=0
    while [ "$n" -lt 20 ]; do
        [ "$(state)" = "$wanted" ] && return 0
        sleep 1; n=$((n+1))
    done
    docker inspect --format '{{json .State}}' "$ID"; exit 1
}
# Deterministic interleaving: observer saw running, user stopped, observer restarts.
new_container --restart no
docker start "$ID" >/dev/null
[ "$(state)" = running ]
docker stop --timeout 1 "$ID" >/dev/null
[ "$(state)" = exited ]
docker restart --timeout 1 "$ID" >/dev/null
[ "$(state)" = running ]
echo 'PASS 1: restart starts a stopped container; inspect-then-restart has a stop race'
docker stop --timeout 1 "$ID" >/dev/null

new_container --restart unless-stopped --env EXIT_DELAY=12
docker start "$ID" >/dev/null
n=0
while [ "$(docker inspect --format '{{.RestartCount}}' "$ID")" -lt 1 ]; do
    [ "$n" -lt 30 ] || { echo 'FAIL: natural failure did not restart'; exit 1; }
    sleep 1; n=$((n+1))
done
wait_state running
echo 'PASS 2: unless-stopped restarts natural process failure'
docker stop --timeout 1 "$ID" >/dev/null
before="$(docker inspect --format '{{.State.StartedAt}} {{.RestartCount}}' "$ID")"
sleep 3
[ "$(state)" = exited ]
[ "$before" = "$(docker inspect --format '{{.State.StartedAt}} {{.RestartCount}}' "$ID")" ]
echo 'PASS 3: explicit stop remains stopped under unless-stopped'
new_container --restart unless-stopped
docker start "$ID" >/dev/null
# Exceed Docker startup grace so lack of restart cannot be attributed to it.
sleep 11
[ "$(state)" = running ]
docker kill --signal=KILL "$ID" >/dev/null
wait_state exited
sleep 3
[ "$(state)" = exited ]
echo 'PASS 4: Docker kill does not substitute for a natural failure restart'
echo 'ALL DOCKER RECOVERY SEMANTICS TESTS PASSED (4 checks)'
