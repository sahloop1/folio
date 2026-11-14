#!/usr/bin/env python3
"""Select an available iPad simulator by ID instead of assuming a device model."""
import json
import subprocess
import sys

result = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "--json"], check=True, capture_output=True, text=True)
devices = json.loads(result.stdout)["devices"]
for runtime in sorted(devices, reverse=True):
    if "iOS" not in runtime:
        continue
    for device in devices[runtime]:
        if device.get("isAvailable", True) and "iPad" in device["name"]:
            print(device["udid"])
            sys.exit(0)
sys.exit("No available iPad Simulator. Install an iOS simulator runtime in Xcode Settings > Components.")
