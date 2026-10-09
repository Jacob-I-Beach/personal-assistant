"""Choose an installed iOS 27 iPhone simulator; never invent a device identifier."""
import json
import sys
from pathlib import Path

devices = json.loads(Path(sys.argv[1]).read_text())["devices"]
candidates = [
    device
    for runtime, entries in devices.items()
    if "SimRuntime.iOS-27-" in runtime
    for device in entries
    if device.get("isAvailable") and device["name"].startswith("iPhone")
]
if not candidates:
    raise SystemExit("No available iOS 27 iPhone simulator is installed on this runner.")
candidates.sort(key=lambda item: (item["name"] != "iPhone 18 Pro Max", item["name"]))
chosen = candidates[0]
print(f"Using {chosen['name']} ({chosen['udid']})", file=sys.stderr)
print(chosen["udid"])
