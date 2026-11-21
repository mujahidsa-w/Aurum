#!/usr/bin/env python3
"""Pick the installed Xcode that this Unreal Engine version accepts.

Reads the engine's Apple SDK json (MinVersion / MaxVersion) and selects the newest
installed Xcode inside that range. Falls back to the newest Xcode when the json is
missing or nothing matches. Prints the chosen Xcode.app path.
"""
import glob, json, os, plistlib, re, sys

ue = sys.argv[1]

def ver(s):
    return tuple(int(x) for x in re.findall(r"\d+", str(s))[:3]) or (0,)

def load(path):
    text = open(path, encoding="utf-8").read()
    text = re.sub(r"^\s*//.*$", "", text, flags=re.M)      # tolerate // comments
    text = re.sub(r",(\s*[}\]])", r"\1", text)              # and trailing commas
    return json.loads(text)

lo, hi = (0,), (999,)
for rel in ("Engine/Config/Apple/Apple_SDK.json", "Engine/Config/Mac/Mac_SDK.json", "Engine/Config/IOS/IOS_SDK.json"):
    path = os.path.join(ue, rel)
    if os.path.isfile(path):
        data = load(path)
        print(f"{rel}: { {k: v for k, v in data.items() if 'Version' in k and isinstance(v, str)} }", file=sys.stderr)
        lo = ver(data.get("MinVersion", "0"))
        hi = ver(data.get("MaxVersion", "999"))
        break
else:
    print("No Apple SDK json found; using the newest Xcode.", file=sys.stderr)

found = {}
for app in glob.glob("/Applications/Xcode*.app"):
    real = os.path.realpath(app)
    try:
        with open(os.path.join(real, "Contents/Info.plist"), "rb") as f:
            v = plistlib.load(f)["CFBundleShortVersionString"]
    except Exception:
        continue
    found[real] = ver(v)
for real, v in sorted(found.items(), key=lambda kv: kv[1]):
    print(f"installed: {real} {'.'.join(map(str, v))}", file=sys.stderr)
if not found:
    sys.exit("No Xcode installed")

def in_range(v):
    # MaxVersion like 16.9.0 means "any 16.x"; compare only as many parts as given.
    return v[:len(lo)] >= lo and v[:len(hi)] <= hi

ok = [r for r, v in found.items() if in_range(v)]
pool = ok or list(found)
if not ok:
    print(f"WARNING: no installed Xcode in range {lo}..{hi}; using the newest one.", file=sys.stderr)
print(max(pool, key=lambda r: found[r]))
