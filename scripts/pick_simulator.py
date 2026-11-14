#!/usr/bin/env python3
"""Picks an iPhone simulator among the destinations the selected Xcode really offers.

Prints SIM_UDID, SIM_NAME and SIM_OS as KEY=value lines (for $GITHUB_ENV).
"""
import os
import re
import subprocess
import sys

project = os.environ.get("PROJECT", "Itinera.xcodeproj")
scheme = os.environ.get("SCHEME", "ItineraUITests")
out = subprocess.run(
    ["xcodebuild", "-showdestinations", "-project", project, "-scheme", scheme],
    capture_output=True, text=True,
).stdout

found = []
for line in out.splitlines():
    if "platform:iOS Simulator" not in line or "placeholder" in line:
        continue
    fields = dict(re.findall(r"(\w+):([^,}]+)", line))
    name, udid, version = fields.get("name", "").strip(), fields.get("id", "").strip(), fields.get("OS", "").strip()
    if not name.startswith("iPhone") or not re.fullmatch(r"[0-9A-Fa-f-]{36}", udid):
        continue
    numbers = tuple(int(n) for n in re.findall(r"\d+", version))
    # Prefer the standard model ("iPhone 16"), then Pro, then anything else.
    rank = 2 if re.fullmatch(r"iPhone \d+", name) else 1 if re.fullmatch(r"iPhone \d+ Pro", name) else 0
    found.append((numbers, rank, name, udid, version))

if not found:
    sys.stderr.write("Nessun simulatore iPhone disponibile.\n" + out)
    sys.exit(1)

numbers, rank, name, udid, version = max(found)
print(f"SIM_UDID={udid}")
print(f"SIM_NAME={name}")
print(f"SIM_OS={version}")
