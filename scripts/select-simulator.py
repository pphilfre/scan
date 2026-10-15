import json
import subprocess

runtimes = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "runtimes", "-j"]))["runtimes"]
ios26 = {r["identifier"] for r in runtimes if r.get("isAvailable") and r.get("version", "").startswith("26.") and "iOS" in r["name"]}
devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))["devices"]
candidates = [d for runtime, items in devices.items() if runtime in ios26 for d in items if d.get("isAvailable") and "iPhone" in d["name"]]
if not candidates:
    raise SystemExit("No preinstalled iOS 26 iPhone simulator. Refusing a slow runtime download.")
candidates.sort(key=lambda d: (d.get("state") != "Booted", "iPhone 17" not in d["name"], d["name"]))
print(candidates[0]["udid"])
