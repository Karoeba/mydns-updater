"""Check prompt shutdown during the real 300-second retry wait; no network."""
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    env = dict(os.environ, MYDNS_CONFIG_DIR=str(tmp / "missing"),
               MYDNS_STATE_DIR=str(tmp / "state"),
               MYDNS_HEALTH_FILE=str(tmp / "health"))
    with (tmp / "log").open("w") as log:
        proc = subprocess.Popen(["sh", str(root / "update.sh")], env=env,
                                stdout=log, stderr=log, start_new_session=True)
        child = None
        try:
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                children = Path(f"/proc/{proc.pid}/task/{proc.pid}/children")
                if children.exists():
                    for pid in children.read_text().split():
                        try:
                            args = Path(f"/proc/{pid}/cmdline").read_bytes()
                        except FileNotFoundError:
                            continue
                        if args.split(b"\0")[:2] == [b"sleep", b"300"]:
                            child = int(pid)
                            break
                if child is not None:
                    break
                if proc.poll() is not None:
                    raise AssertionError("updater exited before wait")
                time.sleep(0.1)
            assert child is not None, "300-second waiting child was not found"
            proc.send_signal(signal.SIGTERM)
            assert proc.wait(timeout=5) == 0
            assert not Path(f"/proc/{child}").exists(), "sleep child left behind"
            assert not (tmp / "health").exists(), "health record left behind"
            print("PASS: TERM interrupts real wait, reaps child and removes health record")
        finally:
            if proc.poll() is None:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait(timeout=5)
