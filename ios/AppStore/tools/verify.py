#!/usr/bin/env python3
"""Verify generated image formats, native dimensions, and App Store text limits."""

import json
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path
from zipfile import ZipFile

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SIZES = {"iphone-6.5": (1284, 2778), "iphone": (1320, 2868), "ipad": (2064, 2752)}
LIMITS = {"name": 30, "subtitle": 30, "promotional_text": 170, "keywords": 100, "description": 4000}


class PreviewLinks(HTMLParser):
    def handle_starttag(self, tag, attributes):
        for key, value in attributes:
            if key in {"href", "src"}:
                assert (ROOT / value).is_file(), f"Broken preview link: {value}"


def main():
    manifest = json.loads((ROOT / "manifest.json").read_text())
    counts = Counter()
    for entry in manifest["screenshots"]:
        path = ROOT / entry["file"]
        with Image.open(path) as image:
            image.verify()
        with Image.open(path) as image:
            assert image.format == "PNG", path
            assert image.mode == "RGB", f"Alpha channel or unexpected color mode: {path}"
            assert image.size == SIZES[entry["device"]], path
        counts[entry["language"], entry["device"]] += 1
    assert counts == Counter({(language, family): 5 for language in ("en", "ru") for family in SIZES}), counts
    actual_files = set((ROOT / "screenshots").glob("*/*/*.png"))
    assert actual_files == {ROOT / entry["file"] for entry in manifest["screenshots"]}, "Manifest does not match image files"
    with Image.open(ROOT / manifest["icon"]) as icon:
        assert icon.size == (1024, 1024) and icon.mode == "RGB"

    snapshot_manifest = json.loads((ROOT / "snapshot-manifest.json").read_text())
    snapshot_counts = Counter()
    for entry in snapshot_manifest["snapshots"]:
        path = ROOT / entry["file"]
        with Image.open(path) as image:
            image.verify()
        with Image.open(path) as image:
            assert image.format == "PNG" and image.mode == "RGB", path
            assert image.size == SIZES[entry["device"]], path
            assert image.size == (entry["width"], entry["height"]), path
        snapshot_counts[entry["language"], entry["device"]] += 1
    assert snapshot_counts == Counter({(language, family): 5
                                       for language in ("en", "ru") for family in ("iphone", "ipad")}), snapshot_counts
    assert set((ROOT / "snapshots").glob("*/*/*.png")) == {
        ROOT / entry["file"] for entry in snapshot_manifest["snapshots"]
    }, "Snapshot manifest does not match exported files"
    with ZipFile(ROOT / "snapshots/appstore-snapshots.zip") as archive:
        assert archive.testzip() is None, "Snapshot ZIP is corrupt"
        assert set(archive.namelist()) == {"README.md"} | {
            str((ROOT / entry["file"]).relative_to(ROOT / "snapshots"))
            for entry in snapshot_manifest["snapshots"]
        }, "Snapshot ZIP has missing or extra files"

    promotional_archive = manifest["promotional_archive"]
    requested_files = {entry["file"] for entry in manifest["screenshots"]
                       if entry["device"] in {"iphone-6.5", "ipad"}}
    assert len(requested_files) == 20
    assert {entry["file"] for entry in promotional_archive["files"]} == requested_files
    with ZipFile(ROOT / promotional_archive["file"]) as archive:
        assert archive.testzip() is None, "Promotional ZIP is corrupt"
        assert set(archive.namelist()) == {"README.txt"} | {
            entry["archive_name"] for entry in promotional_archive["files"]
        }, "Promotional ZIP has missing or extra files"
        for entry in promotional_archive["files"]:
            assert archive.read(entry["archive_name"]) == (ROOT / entry["file"]).read_bytes(), entry

    for language, family in counts:
        capture_paths = list((ROOT / "captures" / language / family).glob("*.json"))
        assert len(capture_paths) == 5
        for path in capture_paths:
            metadata = json.loads(path.read_text())
            assert (round(metadata["width"] * metadata["scale"]),
                    round(metadata["height"] * metadata["scale"])) == SIZES[family]
            for board in metadata.get("boards", []):
                assert board["level"] == 1 + board["lines"] // 10

    for path in sorted((ROOT / "metadata").glob("*.json")):
        metadata = json.loads(path.read_text())
        for field, limit in LIMITS.items():
            length = len(metadata[field])
            assert 0 < length <= limit, f"{path.name}/{field}: {length} > {limit}"
            print(f"{path.stem}: {field} {length}/{limit}")
        # Stay within 100 UTF-8 bytes too, for conservative keyword portability.
        assert len(metadata["keywords"].encode("utf-8")) <= 100, f"{path.name}: keywords exceed 100 UTF-8 bytes"
        description_document = (ROOT / "DESCRIPTION.md").read_text()
        assert metadata["description"] in description_document, f"Stale readable description: {path.name}"
        assert metadata["keywords"] in description_document, f"Stale readable keywords: {path.name}"
    PreviewLinks().feed((ROOT / "index.html").read_text())
    print("Verified: 30 promotional screenshots, 20-image iPhone 6.5-inch + iPad promotional ZIP, 20 plain snapshots, 30 capture records, 1024px icon, and 2 localized listings.")


if __name__ == "__main__":
    main()
