#!/usr/bin/env python3
"""run_with_deadline.py <deadline-epoch> <logfile> -- cmd...

Runs cmd in its own process group, mirrors output to stdout and logfile. When the
deadline passes it stops the build like Ctrl+C (UnrealBuildTool cancels cleanly and
clang never leaves half-written objects), then escalates. Exit code 124 = deadline.
"""
import os, signal, subprocess, sys, threading, time

deadline, log = float(sys.argv[1]), sys.argv[2]
cmd = sys.argv[sys.argv.index("--") + 1:]
if time.time() >= deadline:
    print("No time left in this stage for:", " ".join(cmd))
    sys.exit(124)
print(f"Running (stops at {time.strftime('%H:%M:%S', time.gmtime(deadline))} UTC):", " ".join(cmd), flush=True)
proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
timed_out = False

def watchdog():
    global timed_out
    while proc.poll() is None:
        if time.time() >= deadline:
            timed_out = True
            print("\n==== Stage time is up: stopping the build, it continues in the next stage ====", flush=True)
            for sig, wait in ((signal.SIGINT, 240), (signal.SIGTERM, 60), (signal.SIGKILL, 0)):
                try:
                    os.killpg(proc.pid, sig)
                except ProcessLookupError:
                    return
                end = time.time() + wait
                while proc.poll() is None and time.time() < end:
                    time.sleep(2)
                if proc.poll() is not None:
                    return
        time.sleep(5)

threading.Thread(target=watchdog, daemon=True).start()
with open(log, "ab") as f:
    for line in proc.stdout:
        sys.stdout.buffer.write(line); sys.stdout.flush()
        f.write(line)
code = proc.wait()
sys.exit(124 if timed_out else code)
