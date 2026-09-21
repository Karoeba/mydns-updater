"""Exercise the real host adapter with a fake clock and Docker CLI."""
import json, os, subprocess, tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory() as tmp:
    p = Path(tmp); (p/"state").mkdir(); (p/"bin").mkdir()
    f = p/"fixture.json"
    state = dict(now=10000, cid="a"*64, running="running", paused="false",
                 policy="unless-stopped", started="2026-01-01T00:00:00Z",
                 mode="HEALTHY", gen=10, deadline=20, requests=0, protocol=True)
    def write(): f.write_text(json.dumps(state))
    def read(): state.update(json.loads(f.read_text()))
    mock = p/"bin/docker"
    mock.write_text("""#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
f=Path(os.environ["FIXTURE"]); s=json.loads(f.read_text()); a=sys.argv[1:]
assert a[:2]==["--host","unix:///var/run/docker.sock"]
a=a[2:]
def save(): f.write_text(json.dumps(s))
if a[0]=="inspect":
    if s.get("inspect_fail") or (a[-1] not in ("mydns-updater",s["cid"])): sys.exit(1)
    print(s["cid"],s["running"],s["paused"],s["policy"],s["started"])
elif a[0]=="exec":
    if s["running"]!="running" or a[1]!=s["cid"]: sys.exit(1)
    if a[2]=="grep": sys.exit(0 if s["protocol"] else 1)
    if a[4]=="--docker-recovery-status":
        mode=s["mode"]
        if mode=="TIMEOUT": time.sleep(10); sys.exit(1)
        if mode=="SECRET": print("private-password"); sys.exit(0)
        if mode=="ERROR": sys.exit(1)
        if mode=="STOP": s["running"]="exited"; mode="OVERDUE"; save()
        if mode=="RECREATE": s["cid"]="b"*64; mode="OVERDUE"; save()
        if mode=="NEWSTART": s["started"]="2026-01-02T00:00:00Z"; mode="OVERDUE"; save()
        if mode=="OTHER": print("OTHER")
        else: print(mode, "11111111-1111-1111-1111-111111111111_"+str(s["gen"])+"_"+str(s["deadline"]))
    elif a[4]=="--docker-recovery-request":
        s["requests"]+=1
        if not s.get("request_fail"): s["gen"]+=1
        save()
        sys.exit(1 if s.get("request_fail") else 0)
    else: raise AssertionError(a)
else: raise AssertionError("Forbidden Docker operation: "+str(a))
""")
    date=p/"bin/date"
    date.write_text("""#!/usr/bin/env python3
import json, os
print(json.load(open(os.environ["FIXTURE"]))["now"])
""")
    mock.chmod(0o755); date.chmod(0o755)
    env=dict(os.environ, FIXTURE=str(f), MYDNS_DOCKER_BIN=str(mock),
             MYDNS_RECOVERY_DIR=str(p/"state"), PATH=str(p/"bin")+":"+os.environ["PATH"])
    def run(arg="--once", ok=True):
        write()
        r=subprocess.run(["sh",str(ROOT/"docker-health-recover.sh"),arg],env=env,
                         text=True,capture_output=True,timeout=12)
        read()
        assert (r.returncode==0)==ok, (r.returncode,r.stdout,r.stderr)
        assert "private-password" not in r.stdout+r.stderr
        return r.stdout
    def advance(n=30): state["now"]+=n
    def reset():
        run("--reset"); state.update(mode="OVERDUE",running="running",paused="false",
                                    policy="unless-stopped",protocol=True,request_fail=False)
    def triple():
        for _ in range(3): advance(); run()
    def count(n): assert state["requests"]==n, state
    run(); count(0)
    state["mode"]="OVERDUE"
    run(); run(); run(); count(0)
    advance(); run(); count(0)
    advance(); assert "RESTART_ATTEMPT" in run(); count(1)
    print("PASS: three fresh, spaced observations; duplicate invocations ignored")
    state["mode"]="HEALTHY"; assert "RECOVERED" in run()
    assert "RECOVERED" not in run()
    state["mode"]="OVERDUE"; triple(); count(1)
    state["now"]=10659; triple(); count(2)
    print("PASS: recovery logged once; 600-second cooldown persists across new process")
    state["mode"]="HEALTHY"; run()
    state["mode"]="OVERDUE"; state["now"]=11350; triple(); count(3)
    triple(); count(3)
    assert "blocked=1" in run("--status")
    state["now"]=20000; state["mode"]="HEALTHY"; run()
    state["mode"]="OVERDUE"; triple(); count(3)
    print("PASS: fourth request blocked; latch survives healthy state and elapsed hour")
    reset(); count(3)
    state["running"]="exited"; triple(); count(3)
    state["running"]="running"; state["paused"]="true"; triple(); count(3)
    print("PASS: reset does not start container; stopped and paused containers untouched")
    for mode in ["STOP","RECREATE","NEWSTART"]:
        reset(); advance();run();advance();run()
        state["mode"]=mode; advance();run();count(3)
    print("PASS: stop, recreation and restart during observation discard evidence")
    for mode in ["OTHER","SECRET","ERROR","TIMEOUT"]:
        reset(); state["mode"]=mode
        advance();run(ok=mode=="OTHER");count(3)
    print("PASS: missing/invalid progress, unexpected output and timeout never restart")
    reset(); state["protocol"]=False
    run(ok=False);count(3)
    state["protocol"]=True; state["policy"]="always"
    run(ok=False);count(3)
    print("PASS: old script and unsupported policy are rejected before probing")
    reset();state["request_fail"]=True;triple();count(4)
    triple();count(4)
    print("PASS: failed/uncertain request consumes allowance")
    reset(); state["now"]=30000;triple();count(5)
    state["now"]=30690;triple();count(6)
    state["now"]=31380;triple();count(7)
    # Do not attempt a fourth until the first has left the rolling hour.
    state["now"]=33700;triple();count(8)
    print("PASS: rolling hour permits next request once oldest attempt expires")
    saved=(p/"state/status").read_text().split();saved[0]="previous-boot"
    (p/"state/status").write_text(" ".join(saved)+"\n")
    triple();count(8)
    state["now"]-=1000;run()
    assert "blocked=1" in run("--status")
    print("PASS: boot change preserves history; clock rollback latches")
    reset();advance();run();advance();run()
    state["mode"]="OTHER";advance();run()
    state["mode"]="OVERDUE";advance();run();advance();run();count(8)
    advance();run();count(9)
    print("PASS: other result breaks overdue streak")
    reset();advance();run();advance();run();advance(181);run();count(9)
    print("PASS: long monitoring gap restarts consecutive count")
    (p/"state/status").write_text("broken\n")
    run(ok=False);count(9)
    print("PASS: corrupted history fails closed")
    print("ALL DOCKER RECOVERY POLICY TESTS PASSED")
