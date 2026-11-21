#!/usr/bin/env python3
"""Write Engine/Saved/UnrealBuildTool/BuildConfiguration.xml for a small CI runner.

UnrealBuildTool rejects unknown XML elements, and setting names change between
engine versions, so every setting is written only if the engine source declares it.
"""
import os, re, sys
from pathlib import Path

ue = Path(sys.argv[1])
jobs = sys.argv[2] if len(sys.argv) > 2 else "3"
ubt = ue / "Engine/Source/Programs/UnrealBuildTool"
sources = {p: p.read_text(errors="ignore") for p in ubt.rglob("*.cs")}

def declared(category, name):
    field = rf"(?:\[[^\]]*\]\s*)*public\s+(?:static\s+)?[\w<>?]+\s+{name}\b"
    for path, text in sources.items():
        if re.search(rf'XmlConfigFile\(\s*Category\s*=\s*"{category}"[^\]]*\)\]\s*' + field, text):
            return True
        # [XmlConfigFile] without a category = category is the declaring class name
        if re.search(rf"class\s+{category}\b", text) and re.search(r"XmlConfigFile(?:\(\s*\))?\]\s*" + field, text):
            return True
    return False

wanted = {
    "BuildConfiguration": {
        "MaxParallelActions": jobs,       # 7 GB RAM runner: more clang jobs = swap stall
        "bDisableDebugInfo": "true",      # faster compile/link, much smaller state archive
        "bAllowUBAExecutor": "false",     # plain local executor: predictable stop/resume
        "bAllowUBALocalExecutor": "false",
        "bAllowXGE": "false",
        "bAllowFASTBuild": "false",
        "bAllowSNDBS": "false",
    },
    "ParallelExecutor": {"MaxProcessorCount": jobs, "ProcessorCountMultiplier": "1"},
    "LocalExecutor": {"MaxProcessorCount": jobs, "ProcessorCountMultiplier": "1"},
}
lines = ['<?xml version="1.0" encoding="utf-8" ?>',
         '<Configuration xmlns="https://www.unrealengine.com/BuildConfiguration">']
for category, fields in wanted.items():
    keep = [(k, v) for k, v in fields.items() if declared(category, k)]
    if keep:
        lines.append(f"  <{category}>")
        lines += [f"    <{k}>{v}</{k}>" for k, v in keep]
        lines.append(f"  </{category}>")
lines.append("</Configuration>")
out = ue / "Engine/Saved/UnrealBuildTool/BuildConfiguration.xml"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text("\n".join(lines) + "\n")
print(out.read_text())
