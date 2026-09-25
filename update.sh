#!/bin/sh

VERSION="1.10.1"
# MYDNS_DOCKER_RECOVERY_PROTOCOL=1
# Resolve modules beside this entry point, never from the caller's working directory.
case "$0" in
    */*) MYDNS_PROGRAM_PATH="$0" ;;
    *)
        if [ -f "./$0" ]; then MYDNS_PROGRAM_PATH="./$0"
        else MYDNS_PROGRAM_PATH="$(command -v "$0")" || exit 1; fi
        ;;
esac
MYDNS_PROGRAM_DIR="$(CDPATH= cd -P -- "$(dirname -- "$MYDNS_PROGRAM_PATH")" && pwd)" || exit 1
for MYDNS_MODULE in diagnostics health config network state runtime; do
    if [ ! -f "$MYDNS_PROGRAM_DIR/lib/$MYDNS_MODULE.sh" ] ||
       [ ! -r "$MYDNS_PROGRAM_DIR/lib/$MYDNS_MODULE.sh" ]; then
        printf '%s\n' "[FATAL] [PROGRAM] MODULE_UNAVAILABLE: lib/$MYDNS_MODULE.sh; install update.sh and lib together" >&2
        exit 1
    fi
done
for MYDNS_MODULE in diagnostics health config network state runtime; do
    . "$MYDNS_PROGRAM_DIR/lib/$MYDNS_MODULE.sh" || exit 1
done
updater_defaults
case "$HEALTH_FILE" in /*) ;; *) echo "UNHEALTHY: MYDNS_HEALTH_FILE must be absolute"; exit 1 ;; esac

case "${1:-}" in
    --healthcheck) health_probe; exit $? ;;
    --docker-recovery-status) recovery_status; exit $? ;;
    --docker-recovery-request)
        [ "$#" -eq 2 ] || exit 2
        R_STATUS="$(recovery_status)" || exit 1
        [ "$R_STATUS" = "OVERDUE $2" ] || exit 3
        # Only signal PID 1 here; never use the Docker start/restart/kill API.
        kill -TERM 1 && kill -CONT 1
        exit $? ;;
esac

initialize_runtime
run_forever
