#!/usr/bin/env python3
"""Print the Android NDK major version this Unreal Engine wants (from Android_SDK.json)."""
import json, re, sys
from pathlib import Path

ue = Path(sys.argv[1])
for rel in ("Engine/Config/Android/Android_SDK.json", "Engine/Platforms/Android/Config/Android_SDK.json"):
    p = ue / rel
    if not p.is_file():
        continue
    text = re.sub(r"^\s*//.*$", "", p.read_text(), flags=re.M)
    text = re.sub(r",(\s*[}\]])", r"\1", text)
    data = json.loads(text)
    print(f"{rel}: {data}", file=sys.stderr)
    for key in ("MainVersion", "MinVersion"):
        v = str(data.get(key, ""))
        m = re.search(r"r(\d+)", v) or re.match(r"(\d+)\.", v)
        if m:
            print(m.group(1))
            sys.exit(0)
print("No NDK version found in Android_SDK.json; using 27", file=sys.stderr)
print("27")
