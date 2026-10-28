#!/usr/bin/env python3
"""Refresh what the admin's Tour tab shows of the app, on several iPhone sizes.

For each device below: boot the simulator, install the Debug app, run the four tour stubs,
screenshot each tab and read every tagged element's frame. Writes
  backend/src/admin/tourScreens.ts   the screenshots, as WebP data URIs, per device
  backend/src/tour/devices.ts        each device's screen size and where each element sits (points)

Build the Debug app first (xcodebuild ... -derivedDataPath ios/DerivedData), then:
  python3 ios/scripts/tour_screens.py            all devices
  python3 ios/scripts/tour_screens.py 16pro 16e  only these (the others keep what they had)
Needs Pillow (pip install pillow).
"""
import base64, io, json, pathlib, re, subprocess, sys, time

ROOT = pathlib.Path(__file__).resolve().parents[2]
BUNDLE = "com.michaelhalperin.setpointapp"
APP = ROOT / "ios/DerivedData/Build/Products/Debug-iphonesimulator/SetPoint.app"
TABS = ["today", "train", "progress", "you"]
# id -> simulator name. Sizes come from the screenshots, not from here.
DEVICES = {
    "18promax": "iPhone 18 Pro Max",
    "18pro": "iPhone 18 Pro",
    "17promax": "iPhone 17 Pro Max",
    "17pro": "iPhone 17 Pro",
    "17": "iPhone 17",
    "16promax": "iPhone 16 Pro Max",
    "16plus": "iPhone 16 Plus",
    "air": "iPhone Air",
    "16pro": "iPhone 16 Pro",
    "16": "iPhone 16",
    "16e": "iPhone 16e",
}
SHOTS_TS = ROOT / "backend/src/admin/tourScreens.ts"
DEVICES_TS = ROOT / "backend/src/tour/devices.ts"


def sh(*args, check=True):
    return subprocess.run(args, check=check, capture_output=True, text=True).stdout.strip()


def udid_for(name):
    data = json.loads(sh("xcrun", "simctl", "list", "devices", "available", "-j"))["devices"]
    for group in data.values():
        for d in group:
            if d["name"] == name:
                return d["udid"]
    # Not there yet: make one on the newest iOS runtime that takes this phone.
    runtimes = json.loads(sh("xcrun", "simctl", "list", "runtimes", "available", "-j"))["runtimes"]
    ios = [r for r in runtimes if r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]
    ios.sort(key=lambda r: [int(x) for x in re.findall(r"\d+", r["version"])], reverse=True)
    kind = "com.apple.CoreSimulator.SimDeviceType." + name.replace(" ", "-")
    for runtime in ios:
        made = subprocess.run(["xcrun", "simctl", "create", name, kind, runtime["identifier"]], capture_output=True, text=True)
        if made.returncode == 0:
            print(f"{name}: created a simulator on {runtime['name']}", flush=True)
            return made.stdout.strip()
    sys.exit(f"No installed iOS runtime can run {name}")


def read_ts_object(path, marker):
    """The JSON object a generated file holds after `marker`, or {}."""
    if not path.exists():
        return {}
    text = path.read_text()
    m = re.search(re.escape(marker) + r"\s*=\s*(\{.*\})\s*(?:as const)?;?\s*$", text, re.S)
    return json.loads(m.group(1)) if m else {}


def capture(device_id, name):
    from PIL import Image

    udid = udid_for(name)
    print(f"{name}: booting", flush=True)
    sh("xcrun", "simctl", "boot", udid, check=False)
    sh("xcrun", "simctl", "bootstatus", udid, "-b")
    sh("xcrun", "simctl", "install", udid, str(APP))
    sh("xcrun", "simctl", "status_bar", udid, "override", "--time", "9:41", "--dataNetwork", "wifi", "--wifiMode", "active",
       "--wifiBars", "3", "--cellularMode", "active", "--cellularBars", "4", "--batteryState", "charged", "--batteryLevel", "100")
    docs = pathlib.Path(sh("xcrun", "simctl", "get_app_container", udid, BUNDLE, "data")) / "Documents"
    for old in docs.glob("tour-frames-*.json"):
        old.unlink()

    shots, frames, screen = {}, {}, None
    for tab in TABS:
        sh("xcrun", "simctl", "terminate", udid, BUNDLE, check=False)
        sh("xcrun", "simctl", "launch", udid, BUNDLE, "-uiStub", f"tour-{tab}", "-dumpTourFrames")
        time.sleep(8)
        png = pathlib.Path(f"/tmp/tour-{device_id}-{tab}.png")
        sh("xcrun", "simctl", "io", udid, "screenshot", str(png))
        dumped = json.loads((docs / f"tour-frames-{tab}.json").read_text())
        screen = dumped["screen"]
        for key, rect in dumped["anchors"].items():
            frames[key] = [round(v, 1) for v in rect]
        image = Image.open(png).convert("RGB").resize((int(screen[0] * 2), int(screen[1] * 2)), Image.LANCZOS)
        buf = io.BytesIO()
        image.save(buf, "WEBP", quality=80, method=6)
        shots[tab] = "data:image/webp;base64," + base64.b64encode(buf.getvalue()).decode()
    sh("xcrun", "simctl", "status_bar", udid, "clear", check=False)
    sh("xcrun", "simctl", "shutdown", udid, check=False)
    return {"name": name, "screen": screen, "frames": frames}, shots


def main():
    if not APP.exists():
        sys.exit("Build the Debug app for the simulator first: " + str(APP))
    wanted = sys.argv[1:] or list(DEVICES)
    devices = read_ts_object(DEVICES_TS, "export const TOUR_DEVICES")
    shots = read_ts_object(SHOTS_TS, "export const TOUR_SHOTS")
    for device_id in wanted:
        if device_id not in DEVICES:
            sys.exit(f"Unknown device {device_id}; choose from {', '.join(DEVICES)}")
        info, device_shots = capture(device_id, DEVICES[device_id])
        devices[device_id] = info
        shots[device_id] = device_shots
        print(f"{DEVICES[device_id]}: {info['screen']}, {len(info['frames'])} elements", flush=True)
    order = [d for d in DEVICES if d in devices]
    devices = {d: devices[d] for d in order}
    shots = {d: shots[d] for d in order if d in shots}
    DEVICES_TS.write_text(
        "// Generated by ios/scripts/tour_screens.py: each phone's screen size and where each tour element sits, in points.\n"
        "export const TOUR_DEVICES = " + json.dumps(devices, indent=2) + " as const;\n")
    SHOTS_TS.write_text(
        "// Generated by ios/scripts/tour_screens.py. The app's own screens per phone, for the admin's Tour tab.\n"
        "export const TOUR_SHOTS = " + json.dumps(shots) + " as const;\n")


if __name__ == "__main__":
    main()
