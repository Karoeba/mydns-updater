#!/bin/sh
# CI only: real systemd scheduling with isolated names and a fake probe.
set -eu
[ "${GITHUB_ACTIONS:-}" = true ] && [ "$(id -u)" -eq 0 ] || {
    echo 'Run only with sudo in a disposable GitHub Actions runner'; exit 1;
}
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TASK="$(mktemp -d)"
NAME="mydns-ci-monitor-$$"
TARGET="$NAME-target.service"
CHECK="$NAME-check.service"
TIMER="$NAME.timer"
cleanup() {
    systemctl stop "$TIMER" "$CHECK" "$TARGET" 2>/dev/null || :
    systemctl disable "$TIMER" 2>/dev/null || :
    rm -f "/etc/systemd/system/$TIMER" "/etc/systemd/system/$CHECK" "/etc/systemd/system/$TARGET"
    systemctl daemon-reload
    rm -rf "$TASK" "/run/$NAME"
}
trap cleanup 0
trap 'exit 1' INT TERM
cat > "$TASK/probe" <<EOF
#!/bin/sh
if [ -f "$TASK/bad" ]; then
    echo 'UNHEALTHY: updater progress overdue'; exit 1
fi
echo 'HEALTHY: updater progressing or waiting'
EOF
cat > "/etc/systemd/system/$TARGET" <<EOF
[Service]
ExecStart=/bin/sleep infinity
EOF
sed -e "s/mydns-updater.service/$TARGET/g" \
    -e 's/User=mydns-updater/User=root/' -e 's/Group=mydns-updater/Group=root/' \
    -e "s@RuntimeDirectory=mydns-updater-monitor@RuntimeDirectory=$NAME@" \
    -e "s@/run/mydns-updater-monitor@/run/$NAME@g" \
    -e "s@/usr/local/lib/mydns-updater/update.sh@$TASK/probe@" \
    -e "s@/usr/local/lib/mydns-updater/health-monitor.sh@$ROOT/health-monitor.sh@" \
    "$ROOT/deploy/linux/mydns-updater-healthcheck.service" > "/etc/systemd/system/$CHECK"
sed -e "s/mydns-updater.service/$TARGET/g" \
    -e "s/mydns-updater-healthcheck.service/$CHECK/g" \
    -e 's/=30s/=1s/g' -e 's/AccuracySec=1s/AccuracySec=1ms/' \
    "$ROOT/deploy/linux/mydns-updater-healthcheck.timer" > "/etc/systemd/system/$TIMER"
systemctl daemon-reload
systemctl enable "$TIMER"
systemctl start "$TARGET"
wait_log() {
    attempt=0
    while [ "$attempt" -lt 30 ]; do
        journalctl -u "$CHECK" --no-pager -o cat > "$TASK/log"
        grep -Fq "$1" "$TASK/log" && return 0
        sleep 1; attempt=$((attempt+1))
    done
    cat "$TASK/log"; systemctl status "$TIMER" "$CHECK" --no-pager || :
    exit 1
}
touch "$TASK/bad"
wait_log 'UNHEALTHY; consecutive_failures=3'
echo 'PASS systemd: timer records sustained failure'
sleep 3
[ "$(journalctl -u "$CHECK" --no-pager -o cat | grep -c 'UNHEALTHY;')" -eq 1 ]
echo 'PASS systemd: repeated failure does not repeat application log'
rm "$TASK/bad"
wait_log 'RECOVERED'
echo 'PASS systemd: timer records recovery'
systemctl stop "$TARGET"
sleep 2
if systemctl is-active --quiet "$TIMER"; then echo 'FAIL: timer stayed active'; exit 1; fi
if systemctl is-active --quiet "$TARGET"; then echo 'FAIL: stopped target restarted'; exit 1; fi
echo 'PASS systemd: manual stop stops timer and never restarts target'
systemctl start "$TARGET"
systemctl is-active --quiet "$TIMER"
echo 'PASS systemd: starting target restarts enabled timer'
echo 'ALL SYSTEMD MONITOR TESTS PASSED (5 checks)'
