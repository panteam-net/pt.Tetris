#!/usr/bin/env python3
"""Build a simulator capture host from the production UI and record native PNGs.

Requires macOS, Xcode and installed iPhone/iPad simulators. Uses only Python's
standard library. The separate host never links Firebase or opens a real room.
"""

import argparse
import json
import platform
import plistlib
import shutil
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT.parent
BUNDLE_ID = "pro.pteam.TetrisDuel.AppStoreCapture"
SCENES = {"iphone": ["solo", "nearby", "strategy", "speed", "menu"],
          "ipad": ["duel", "solo", "strategy", "nearby", "menu"]}
SCENES["iphone-6.5"] = SCENES["iphone"]
DEVICE_NAMES = {"iphone": "iPhone 17 Pro Max", "iphone-6.5": "iPhone 13 Pro Max",
                "ipad": "iPad Pro 13-inch (M5)"}


def run(*arguments, **kwargs):
    return subprocess.run(arguments, check=True, text=True, **kwargs)


def build(work):
    app = work / "StoreCapture.app"
    app.mkdir(parents=True, exist_ok=True)
    sources = list((IOS / "TetrisDuel/Core").glob("*.swift"))
    sources += list((IOS / "TetrisDuel/UI").glob("*.swift"))
    sources += [IOS / ("TetrisDuel/" + name) for name in [
        "App/Localization.swift", "Services/ServiceContracts.swift",
        "Modules/Menu/MenuVIPER.swift", "Modules/Menu/MenuViewController.swift",
        "Modules/Game/GameContracts.swift", "Modules/Game/GamePresenter.swift",
        "Modules/Game/GameRouter.swift", "Modules/Game/GameViewController.swift",
    ]]
    sources.append(ROOT / "tools/CaptureScene.swift")
    sdk = run("xcrun", "--sdk", "iphonesimulator", "--show-sdk-path", capture_output=True).stdout.strip()
    architecture = "arm64" if platform.machine() == "arm64" else "x86_64"
    run("xcrun", "--sdk", "iphonesimulator", "swiftc", "-swift-version", "5", "-sdk", sdk,
        "-target", f"{architecture}-apple-ios16.0-simulator",
        "-module-name", "TetrisDuelStoreCapture", "-O",
        *map(str, sources), "-o", str(app / "StoreCapture"))
    info = {
        "CFBundleIdentifier": BUNDLE_ID, "CFBundleExecutable": "StoreCapture",
        "CFBundleName": "StoreCapture", "CFBundleDisplayName": "pt.TetrisDuel",
        "CFBundlePackageType": "APPL", "CFBundleVersion": "1",
        "CFBundleShortVersionString": "1.0", "CFBundleDevelopmentRegion": "en",
        "CFBundleLocalizations": ["en", "ru"], "MinimumOSVersion": "16.0",
        "UIDeviceFamily": [1, 2], "UILaunchScreen": {},
        "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
        "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False},
    }
    (app / "Info.plist").write_bytes(plistlib.dumps(info))
    catalog = json.loads((IOS / "TetrisDuel/Resources/Localizable.xcstrings").read_text())
    for language in ["en", "ru"]:
        directory = app / f"{language}.lproj"
        directory.mkdir(exist_ok=True)
        strings = []
        for key, entry in catalog["strings"].items():
            value = entry.get("localizations", {}).get(language, {}).get("stringUnit", {}).get("value")
            if value is None:
                raise ValueError(f"Missing {language} translation: {key}")
            strings.append(f"{json.dumps(key, ensure_ascii=False)} = {json.dumps(value, ensure_ascii=False)};")
        (directory / "Localizable.strings").write_text("\n".join(strings), encoding="utf-16")
    run("codesign", "--force", "--sign", "-", str(app))
    return app


def select_device(name):
    devices = json.loads(run("xcrun", "simctl", "list", "devices", "available", "-j", capture_output=True).stdout)
    for runtime, entries in sorted(devices["devices"].items(), reverse=True):
        for device in entries:
            if device["name"] == name:
                return device["udid"]
    raise SystemExit(f"Simulator '{name}' not found. Pass the corresponding --iphone, --iphone-65 or --ipad simulator UDID.")


def capture(device, family, app, languages):
    state = json.loads(run("xcrun", "simctl", "list", "devices", "-j", capture_output=True).stdout)
    booted = any(d["udid"] == device and d["state"] == "Booted"
                 for devices in state["devices"].values() for d in devices)
    if not booted:
        run("xcrun", "simctl", "boot", device)
    run("xcrun", "simctl", "bootstatus", device, "-b")
    run("xcrun", "simctl", "status_bar", device, "override", "--time", "9:41",
        "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
        "--batteryState", "charged", "--batteryLevel", "100")
    try:
        run("xcrun", "simctl", "install", device, str(app))
        container = Path(run("xcrun", "simctl", "get_app_container", device, BUNDLE_ID, "data", capture_output=True).stdout.strip())
        ready = container / "Documents/capture.json"
        for language in languages:
            destination = ROOT / "captures" / language / family
            destination.mkdir(parents=True, exist_ok=True)
            for scene in SCENES[family]:
                # launch --terminate-running-process is atomic with respect to the old host.
                ready.unlink(missing_ok=True)
                run("xcrun", "simctl", "launch", "--terminate-running-process", device, BUNDLE_ID,
                    "--scene", scene, "-AppleLanguages", f"({language})", "-AppleLocale",
                    "ru_RU" if language == "ru" else "en_US")
                deadline = time.monotonic() + 60
                while not ready.exists():
                    if time.monotonic() > deadline:
                        raise TimeoutError(f"Capture host did not render {family}/{language}/{scene}")
                    time.sleep(0.25)
                metadata = json.loads(ready.read_text())
                if metadata["scene"] != scene:
                    raise RuntimeError("Stale capture marker")
                time.sleep(0.5)
                run("xcrun", "simctl", "io", device, "screenshot", str(destination / f"{scene}.png"))
                shutil.copyfile(ready, destination / f"{scene}.json")
                print(f"Captured {language}/{family}/{scene}: {metadata.get('boards', 'menu')}")
    finally:
        run("xcrun", "simctl", "status_bar", device, "clear")
        subprocess.run(["xcrun", "simctl", "terminate", device, BUNDLE_ID], check=False, capture_output=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work-dir", type=Path, required=True, help="Directory for the temporary simulator host")
    parser.add_argument("--iphone", help="iPhone Pro Max simulator UDID; defaults to iPhone 17 Pro Max")
    parser.add_argument("--iphone-65", help="6.5-inch slot simulator UDID; defaults to iPhone 13 Pro Max (1284 × 2778)")
    parser.add_argument("--ipad", help="13-inch iPad simulator UDID; defaults to iPad Pro 13-inch (M5)")
    parser.add_argument("--languages", nargs="+", choices=["en", "ru"], default=["en", "ru"])
    parser.add_argument("--devices", nargs="+", choices=list(DEVICE_NAMES), default=list(DEVICE_NAMES))
    args = parser.parse_args()
    args.work_dir.mkdir(parents=True, exist_ok=True)
    app = build(args.work_dir)
    overrides = {"iphone": args.iphone, "iphone-6.5": args.iphone_65, "ipad": args.ipad}
    for family in args.devices:
        device = overrides[family] or select_device(DEVICE_NAMES[family])
        capture(device, family, app, args.languages)


if __name__ == "__main__":
    main()
