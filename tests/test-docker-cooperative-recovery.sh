#!/bin/sh
# Behavior experiments only; no production container or account is accessed.
set -eu
[ "${GITHUB_ACTIONS:-}" = true ] || { echo 'CI only'; exit 1; }
IDS=""
cleanup() { for cid in $IDS; do docker rm -f "$cid" >/dev/null 2>&1 || :; done; }
trap cleanup 0
trap 'exit 1' INT TERM
docker version
docker pull alpine:3.23 >/dev/null
new_container() {
    ID="$(docker create --network none --restart unless-stopped \
        --label mydns.test=cooperative-recovery alpine:3.23 sh -c \
        'trap "exit 0" TERM INT; echo ready; while :; do sleep 2; done')"
    IDS="$IDS $ID"
    docker start "$ID" >/dev/null
    n=0
    until docker logs "$ID" 2>&1 | grep -qx ready; do
        [ "$n" -lt 15 ] || exit 1
        sleep 1; n=$((n+1))
    done
    sleep 11
}
generation() {
    docker exec "$ID" sh -c 'awk '"'"'{sub(/^.*\) /,"");print $20}'"'"' /proc/1/stat'
}
request_exit() {
    # A stale request must not terminate a different process generation.
    docker exec "$ID" sh -c '
        current=$(awk '"'"'{sub(/^.*\) /,"");print $20}'"'"' /proc/1/stat)
        [ "$current" = "$1" ] || exit 3
        kill -TERM 1
        kill -CONT 1
    ' sh "$EXPECTED"
}
wait_restart() {
    n=0
    while [ "$(docker inspect --format '{{.RestartCount}}' "$ID")" -le "$BEFORE" ]; do
        [ "$n" -lt 20 ] || { echo 'FAIL: restart not observed'; docker logs "$ID"; exit 1; }
        sleep 1; n=$((n+1))
    done
    n=0
    until docker exec "$ID" true >/dev/null 2>&1; do
        [ "$n" -lt 20 ] || exit 1
        sleep 1; n=$((n+1))
    done
}
assert_stopped() {
    sleep 3
    [ "$(docker inspect --format '{{.State.Status}}' "$ID")" = exited ]
}
new_container
EXPECTED="$(generation)"
BEFORE="$(docker inspect --format '{{.RestartCount}}' "$ID")"
request_exit || :
wait_restart
echo 'PASS 1: in-container TERM permits Docker policy restart'

# Saved request from the preceding generation cannot stop the new process.
NEW="$(generation)"
[ "$NEW" != "$EXPECTED" ]
if request_exit; then echo 'FAIL: stale generation accepted'; exit 1; fi
sleep 3
[ "$(generation)" = "$NEW" ]
echo 'PASS 2: old generation request is rejected'

# Stop wins when it completes before an exit request.
docker stop -t 5 "$ID" >/dev/null
EXPECTED="$NEW"
if request_exit; then echo 'FAIL: exec on stopped container succeeded'; exit 1; fi
assert_stopped
echo 'PASS 3: exit request cannot start a manually stopped container'

# Exec already exists when user stops; its remaining commands die with PID 1.
new_container
docker exec -d "$ID" sh -c 'touch /tmp/request-ready; sleep 5; kill -TERM 1; kill -CONT 1'
n=0
until docker exec "$ID" test -f /tmp/request-ready; do
    [ "$n" -lt 10 ] || exit 1
    sleep 1; n=$((n+1))
done
docker stop -t 5 "$ID" >/dev/null
sleep 6
assert_stopped
echo 'PASS 4: pending exec request does not undo manual stop'

# SIGSTOP sent via Docker changes daemon state. Do not use it to model a
# spontaneous process hang; test that limitation explicitly.
new_container
EXPECTED="$(generation)"
docker kill --signal STOP "$ID" >/dev/null
request_exit || :
n=0
while [ "$(docker inspect --format '{{.State.Running}}' "$ID")" = true ]; do
    [ "$n" -lt 20 ] || { echo 'FAIL: stopped PID 1 did not exit'; exit 1; }
    sleep 1; n=$((n+1))
done
assert_stopped
echo 'PASS 5: Docker STOP suppresses subsequent policy restart (test limitation)'

# For a true hang simulation send STOP from the daemon host PID namespace.
# On a host runner this needs sudo; inside the disposable DinD container root
# and the host-side container PID are already available.
new_container
EXPECTED="$(generation)"
BEFORE="$(docker inspect --format '{{.RestartCount}}' "$ID")"
PID="$(docker inspect --format '{{.State.Pid}}' "$ID")"
if [ "$(id -u)" -eq 0 ]; then kill -STOP "$PID"; else sudo kill -STOP "$PID"; fi
request_exit || :
wait_restart
echo 'PASS 6: stopped PID 1 resumes and exits, then Docker restarts it'
# Verify the real updater too, with no configuration and no network.
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
[ -f "$ROOT/update.sh" ] || ROOT=/opt
ID="$(docker create --network none --restart unless-stopped --label mydns.test=cooperative-recovery alpine:3.23 sh /opt/update.sh)"
IDS="$IDS $ID"
docker cp "$ROOT/update.sh" "$ID":/opt/update.sh
docker start "$ID" >/dev/null
n=0
until docker exec "$ID" sh /opt/update.sh --healthcheck; do
    [ "$n" -lt 15 ] || exit 1
    sleep 1; n=$((n+1))
done
sleep 11
EXPECTED="$(generation)"
BEFORE="$(docker inspect --format '{{.RestartCount}}' "$ID")"
request_exit || :
wait_restart
echo 'PASS 7: real updater exits and restarts within the bounded wait'
echo 'ALL COOPERATIVE RECOVERY EXPERIMENTS PASSED (7 checks)'
