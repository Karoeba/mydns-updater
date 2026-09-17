#!/bin/sh
# CI only: real timer + privilege drop + try-restart, with an isolated dummy service.
set -eu
[ "${GITHUB_ACTIONS:-}" = true ] && [ "$(id -u)" -eq 0 ] || {
    echo 'Run only with sudo in a disposable GitHub Actions runner'; exit 1;
}
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TASK="$(mktemp -d)"
chmod 755 "$TASK"
NAME="mydns-ci-recovery-$$"
TARGET="$NAME-target.service"
CHECK="$NAME.service"
TIMER="$NAME.timer"
cleanup() {
    systemctl stop "$TIMER" "$CHECK" "$TARGET" 2>/dev/null || :
    systemctl disable "$TIMER" 2>/dev/null || :
    rm -f "/etc/systemd/system/$TIMER" "/etc/systemd/system/$CHECK" "/etc/systemd/system/$TARGET"
    systemctl daemon-reload
    rm -rf "$TASK" "/var/lib/$NAME"
}
trap cleanup 0
trap 'exit 1' INT TERM
cat > "$TASK/probe" <<EOF
#!/bin/sh
[ "\$(id -u)" -ne 0 ] || exit 99
pid="\$(systemctl show "$TARGET" --property=MainPID --value)"
if grep -q '^State:.*T' "/proc/\$pid/status"; then
    echo 'UNHEALTHY: updater progress overdue'; exit 1
fi
echo 'HEALTHY: updater progressing or waiting'
EOF
chmod 644 "$TASK/probe"
cat > "/etc/systemd/system/$TARGET" <<EOF
[Unit]
StartLimitIntervalSec=3600
StartLimitBurst=4
[Service]
ExecStart=/bin/sleep infinity
TimeoutStopSec=2
Restart=on-failure
RestartSec=600
EOF
sed -e "s/mydns-updater.service/$TARGET/g" \
    -e 's/MYDNS_RECOVERY_USER=mydns-updater/MYDNS_RECOVERY_USER=nobody/' \
    -e "s/StateDirectory=mydns-updater-recovery/StateDirectory=$NAME/" \
    -e "s@/var/lib/mydns-updater-recovery@/var/lib/$NAME@g" \
    -e "s@/usr/local/lib/mydns-updater/update.sh@$TASK/probe@" \
    -e "s@/usr/local/lib/mydns-updater/health-recover.sh@$ROOT/health-recover.sh@" \
    "$ROOT/deploy/linux/mydns-updater-recovery.service" > "/etc/systemd/system/$CHECK"
sed -e "s/mydns-updater.service/$TARGET/g" \
    -e "s/mydns-updater-recovery.service/$CHECK/g" \
    -e 's/=30s/=1s/g' -e 's/AccuracySec=1s/AccuracySec=1ms/' \
    "$ROOT/deploy/linux/mydns-updater-recovery.timer" > "/etc/systemd/system/$TIMER"
systemctl daemon-reload
systemctl start "$TARGET"
sleep 2
if systemctl is-active --quiet "$TIMER"; then echo 'FAIL: recovery enabled by default'; exit 1; fi
echo 'PASS recovery systemd: opt-in timer stays inactive'
BEFORE="$(systemctl show "$TARGET" --property=InvocationID --value)"
systemctl enable --now "$TIMER"
systemctl kill --kill-whom=main --signal=STOP "$TARGET"
wait_log() {
    attempt=0
    while [ "$attempt" -lt 40 ]; do
        journalctl -u "$CHECK" --no-pager -o cat > "$TASK/log"
        grep -Fq "$1" "$TASK/log" && return 0
        sleep 1; attempt=$((attempt+1))
    done
    cat "$TASK/log"; systemctl status "$TARGET" "$CHECK" "$TIMER" --no-pager || :
    exit 1
}
wait_log RECOVERED
AFTER="$(systemctl show "$TARGET" --property=InvocationID --value)"
[ "$BEFORE" != "$AFTER" ]
[ "$(journalctl -u "$CHECK" --no-pager -o cat | grep -c 'RESTART_ATTEMPT;')" -eq 1 ]
echo 'PASS recovery systemd: stalled main process restarts and confirms healthy with unprivileged probe'
systemctl is-active --quiet "$TIMER"
echo 'PASS recovery systemd: timer resumes after recovery restart'
systemctl kill --kill-whom=main --signal=STOP "$TARGET"
sleep 5
[ "$(journalctl -u "$CHECK" --no-pager -o cat | grep -c 'RESTART_ATTEMPT;')" -eq 1 ]
systemctl kill --kill-whom=main --signal=CONT "$TARGET"
echo 'PASS recovery systemd: repeated stall respects cooldown'
systemctl stop "$TARGET"
sleep 3
if systemctl is-active --quiet "$TARGET"; then echo 'FAIL: intentional stop undone'; exit 1; fi
if systemctl is-active --quiet "$TIMER"; then echo 'FAIL: timer remained active'; exit 1; fi
echo 'PASS recovery systemd: manual stop remains stopped'
echo 'ALL SYSTEMD RECOVERY TESTS PASSED (5 checks)'
