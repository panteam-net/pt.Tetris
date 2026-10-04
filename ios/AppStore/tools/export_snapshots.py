#!/usr/bin/env python3
"""Export plain app screenshots for the required iPhone and iPad display slots."""

import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SLOTS = {
    "iphone": ("iphone-6.9-1320x2868", (1320, 2868), ["solo", "nearby", "strategy", "speed", "menu"]),
    "ipad": ("ipad-13-2064x2752", (2064, 2752), ["duel", "solo", "strategy", "nearby", "menu"]),
}


def export_snapshots():
    entries = []
    for language in ("en", "ru"):
        for family, (folder, size, scenes) in SLOTS.items():
            destination = ROOT / "snapshots" / language / folder
            destination.mkdir(parents=True, exist_ok=True)
            for index, scene in enumerate(scenes, start=1):
                source = ROOT / "captures" / language / family / f"{scene}.png"
                path = destination / f"{index:02d}-{scene}.png"
                with Image.open(source) as image:
                    if image.size != size:
                        raise ValueError(f"Expected native capture size {size}, got {image.size}: {source}")
                    image.convert("RGB").save(path, optimize=True)
                entries.append({"file": str(path.relative_to(ROOT)), "language": language,
                                "device": family, "slot": folder, "width": size[0], "height": size[1],
                                "scene": scene, "mode": "RGB"})
    (ROOT / "snapshot-manifest.json").write_text(json.dumps({
        "specification": "https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/",
        "snapshots": entries,
    }, indent=2) + "\n")
    archive_path = ROOT / "snapshots/appstore-snapshots.zip"
    with ZipFile(archive_path, "w", compression=ZIP_DEFLATED, compresslevel=6) as archive:
        archive.write(ROOT / "snapshots/README.md", "README.md")
        for entry in entries:
            path = ROOT / entry["file"]
            archive.write(path, str(path.relative_to(ROOT / "snapshots")))
    print("Exported 20 plain, native-size RGB snapshots and snapshots/appstore-snapshots.zip")


if __name__ == "__main__":
    export_snapshots()
