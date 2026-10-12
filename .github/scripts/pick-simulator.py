#!/usr/bin/env python3
"""Print the UDID of an available iPhone simulator on the newest iOS runtime."""
import json
import subprocess
import sys

out = subprocess.run(
    ["xcrun", "simctl", "list", "devices", "available", "-j"],
    check=True, capture_output=True, text=True,
).stdout
devices = json.loads(out)["devices"]
for runtime, devs in sorted(devices.items(), reverse=True):
    if "iOS" not in runtime:
        continue
    for dev in devs:
        if dev["name"].startswith("iPhone"):
            print(dev["udid"])
            sys.exit(0)
sys.exit("no available iPhone simulator")
