"""Real curl and local HTTP only, including unknown-length/chunked bodies."""
import http.server
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import shutil

ROOT = Path(__file__).resolve().parents[1]
HITS = []
SECRET = b"private-response-fixture"


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass

    def do_GET(self):
        HITS.append(self.path)
        if self.path == "/redirect":
            self.send_response(302)
            self.send_header("Location", "/ip")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path == "/ip":
            body = b"203.0.113.9\n"
        elif self.path == "/html":
            body = b"<html>" + b" " * 8192 + b"Login and IP address notify OK.</html>"
        elif self.path == "/ip-long":
            body = b" " * 257 + b"203.0.113.9"
        else:
            body = b"Login and IP address notify OK." + SECRET + b"x" * (8 * 1024 * 1024)
        self.send_response(200)
        if self.path == "/chunked":
            self.send_header("Transfer-Encoding", "chunked")
        elif self.path != "/unknown":
            self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        try:
            if self.path == "/chunked":
                for pos in range(0, len(body), 4096):
                    chunk = body[pos:pos + 4096]
                    self.wfile.write(f"{len(chunk):x}\r\n".encode() + chunk + b"\r\n")
                self.wfile.write(b"0\r\n\r\n")
            else:
                self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
base = f"http://127.0.0.1:{server.server_port}"
try:
    with tempfile.TemporaryDirectory() as temp:
        task = Path(temp)
        (task / ".curlrc").write_text("location\n")
        env = dict(os.environ, CURL_HOME=temp, MYDNS_TEST_URL=base,
                   TEST_ROOT=str(ROOT), TEST_WORK=temp, NO_PROXY="127.0.0.1", no_proxy="127.0.0.1")
        preamble = '''
set -eu
for module in diagnostics health config network state runtime; do . "$TEST_ROOT/lib/$module.sh"; done
updater_defaults
WORK_DIR="$TEST_WORK"
mkdir -p "$WORK_DIR/state"
STATE_DIR="$WORK_DIR/state"; STATE_FILE="$STATE_DIR/state.conf"
'''

        def run(script):
            result = subprocess.run(["sh", "-c", preamble + script], env=env, capture_output=True, text=True, timeout=40)
            assert SECRET.decode() not in result.stdout + result.stderr, "response body leaked"
            assert result.returncode == 0, result.stdout + result.stderr

        for endpoint in ("known", "unknown", "chunked"):
            run(f'''
request 5 "$MYDNS_TEST_URL/{endpoint}"
if classify_response; then exit 1; fi
[ "$ERROR_CODE" = RESPONSE_TOO_LARGE ]
[ "$(wc -c < "$WORK_DIR/response")" -le 131072 ]
''')
        run('''
request 5 "$MYDNS_TEST_URL/html"
classify_response
grep -Fq 'Login and IP address notify OK.' "$WORK_DIR/response"
request 5 "$MYDNS_TEST_URL/redirect"
if classify_response; then exit 1; fi
[ "$ERROR_CODE" = HTTP_REDIRECT ]
''')
        assert "/redirect" in HITS and "/ip" not in HITS, "curlrc enabled redirect"
        run('''
IP_CHECK_URL1="$MYDNS_TEST_URL/chunked"
IP_CHECK_URL2="$MYDNS_TEST_URL/ip-long"
IP_CHECK_URL3="$MYDNS_TEST_URL/ip"
get_current_ipv4
[ "$CURRENT_IPV4" = 203.0.113.9 ]
# All invalid means no notification or success state is written by the cycle.
IP_CHECK_URL3="$MYDNS_TEST_URL/unknown"
notify_mydns() { echo unexpected-notification; exit 99; }
run_cycle
[ ! -f "$STATE_FILE" ]
# Next eligible cycle recovers using the same runtime diagnostics.
IP_CHECK_URL1="$MYDNS_TEST_URL/ip"
get_current_ipv4
[ "$CURRENT_IPV4" = 203.0.113.9 ]
''')
        # Exercise the actual notification success decision without contacting MyDNS.
        real_curl = shutil.which("curl")
        (task / "bin").mkdir()
        wrapper = task / "bin/curl"
        wrapper.write_text('''#!/usr/bin/env python3
import os, sys
args = [os.environ["MYDNS_TEST_URL"] + "/" + os.environ["TEST_ENDPOINT"]
        if arg == "https://ipv4.mydns.jp/login.html" else arg for arg in sys.argv[1:]]
os.execv(os.environ["REAL_CURL"], [os.environ["REAL_CURL"], *args])
''')
        wrapper.chmod(0o755)
        env.update(REAL_CURL=real_curl, PATH=str(task / "bin") + os.pathsep + env["PATH"])
        run('''
ID=dummy; PASSWORD=dummy
export TEST_ENDPOINT=chunked
notify_mydns
[ "$REQUEST_OK" -eq 0 ]; [ "$ERROR_CODE" = RESPONSE_TOO_LARGE ]
TEST_ENDPOINT=html
notify_mydns
[ "$REQUEST_OK" -eq 1 ]
printf '1\n' > "$WORK_DIR/sections"
printf '[1]\nID=dummy\nPASSWORD=dummy\nDOMAIN=test.example\n' > "$WORK_DIR/accounts"
FORCE_UPDATE_INTERVAL=86400
get_current_ipv4() { CURRENT_IPV4=203.0.113.9; }
TEST_ENDPOINT=chunked
run_cycle
[ "$(get_value "$STATE_FILE" 1 LAST_UPDATE)" -eq 0 ]
TEST_ENDPOINT=html
run_cycle
[ "$(get_value "$STATE_FILE" 1 LAST_UPDATE)" -gt 0 ]
''')
    print("ALL REAL CURL LIMIT AND CURLRC TESTS PASSED")
finally:
    server.shutdown()
