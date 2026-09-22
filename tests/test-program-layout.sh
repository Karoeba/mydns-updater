#!/bin/sh
# Exercise a complete installed copy and incomplete copies without real accounts.
set -eu
ROOT="${1:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}"
SUITE="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
TASK="$(mktemp -d)"
trap 'rm -rf "$TASK"' 0
trap 'exit 1' INT TERM
APP="$TASK/installed program"
mkdir -p "$APP" "$TASK/bin" "$TASK/other"
cp "$ROOT/update.sh" "$APP/update.sh"
cp -R "$ROOT/lib" "$APP/lib"
# Also exercise an ordinary sh invocation without a slash in argv[0].
export MYDNS_CONFIG_DIR="$TASK/unused-config" MYDNS_STATE_DIR="$TASK/unused-state"
export MYDNS_HEALTH_FILE="$TASK/missing-health"
if (cd "$APP" && sh update.sh --healthcheck) > "$TASK/log" 2>&1; then exit 1; fi
grep -Fq 'UNHEALTHY: progress record unavailable' "$TASK/log"
if (cd "$TASK/other" && sh "$APP/update.sh" --healthcheck) > "$TASK/log" 2>&1; then exit 1; fi
grep -Fq 'UNHEALTHY: progress record unavailable' "$TASK/log"
[ ! -e "$MYDNS_CONFIG_DIR" ] && [ ! -e "$MYDNS_STATE_DIR" ]
echo 'PASS layout: probes locate sibling modules independently of working directory'

# Every required module must fail closed, before network or state writes.
cat > "$TASK/bin/curl" <<'EOF'
#!/bin/sh
echo unexpected >> "$TEST_CALLS"
exit 99
EOF
chmod +x "$TASK/bin/curl"
export TEST_CALLS="$TASK/network"
for module in diagnostics health config network state runtime; do
    mv "$APP/lib/$module.sh" "$TASK/hidden"
    for arg in "" --healthcheck --docker-recovery-status; do
        if PATH="$TASK/bin:$PATH" sh "$APP/update.sh" ${arg:+"$arg"} > "$TASK/log" 2>&1; then
            echo "FAIL layout: missing $module was accepted"; exit 1
        fi
        grep -Fq "MODULE_UNAVAILABLE: lib/$module.sh" "$TASK/log"
        [ ! -e "$MYDNS_STATE_DIR" ] && [ ! -e "$TEST_CALLS" ]
    done
    mv "$TASK/hidden" "$APP/lib/$module.sh"
done
echo 'PASS layout: incomplete installations never update or create persistent state'

# New/retained accounts, reload, state preservation and configuration rejection
# must behave identically after installation in a directory containing spaces.
(cd "$TASK/other" && sh "$SUITE/test-linux.sh" "$APP/update.sh")
sh "$SUITE/test-healthcheck-linux.sh" "$APP/update.sh"
echo 'ALL PROGRAM LAYOUT TESTS PASSED'
