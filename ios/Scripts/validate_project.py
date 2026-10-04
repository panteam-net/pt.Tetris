"""Static checks available on Windows. This does not compile Swift or run XCTest.

Optional parser dependencies: pip install tree-sitter tree-sitter-swift openstep-parser
"""
from pathlib import Path
import json
import plistlib
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / ".validation"))


def validate_localizations(sources, project_text):
    catalogs = {}
    placeholder = r"%(?:\d+\$)?[-+0 #]*\d*(?:\.\d+)?(?:ll|l|z)?[@diufFeEgG]"
    for path in (ROOT / "TetrisDuel/Resources").glob("*.xcstrings"):
        catalog = json.loads(path.read_text(encoding="utf-8"))
        assert catalog["sourceLanguage"] == "en"
        assert path.relative_to(ROOT).as_posix() in project_text
        catalogs[path.stem] = catalog["strings"]
        for key, entry in catalog["strings"].items():
            values = {}
            for language in ("en", "ru"):
                unit = entry["localizations"][language]["stringUnit"]
                assert unit["state"] == "translated", f"Untranslated: {key}"
                assert unit["value"].strip(), f"Empty: {key}/{language}"
                values[language] = unit["value"]

            english = sorted(re.findall(placeholder, values["en"]))
            russian = sorted(re.findall(placeholder, values["ru"]))
            assert english == russian, f"Format mismatch: {key}"

    namespaces = "common|menu|player|lobby|nearby|game|controls|board"
    keys = set()
    for path in sources:
        keys.update(re.findall(
            rf'"((?:{namespaces})\.[A-Za-z0-9.]+)"',
            path.read_text(encoding="utf-8"),
        ))

    missing = keys - catalogs["Localizable"].keys()
    assert not missing, f"Missing localization keys: {sorted(missing)}"
    assert "NSLocalNetworkUsageDescription" in catalogs["InfoPlist"]
    count = sum(len(entries) for entries in catalogs.values())
    print(f"Localization checked: {count} English/Russian strings and formats")


def validate():
    for path in [*ROOT.rglob("*.plist"), *ROOT.rglob("*.xcprivacy")]:
        if ".validation" not in path.parts:
            with path.open("rb") as file:
                plistlib.load(file)
    for path in (ROOT / "TetrisDuel/Resources/Assets.xcassets").rglob("Contents.json"):
        data = json.loads(path.read_text())
        for entry in data.get("images", []):
            assert (path.parent / entry["filename"]).is_file(), f"Missing image in {path}"
    try:
        from PIL import Image
        with Image.open(ROOT / "TetrisDuel/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png") as icon:
            assert icon.size == (1024, 1024) and icon.mode == "RGB", "App icon must be opaque 1024-square RGB"
    except ImportError:
        pass
    with (ROOT / "TetrisDuel/Resources/Info.plist").open("rb") as file:
        info = plistlib.load(file)
    assert info["NSBonjourServices"] == ["_tetris-duel._tcp"]
    assert info.get("NSLocalNetworkUsageDescription")
    assert info["CFBundleLocalizations"] == ["en", "ru"]
    assert not any("Bluetooth" in key for key in info), "No Bluetooth permission should be requested"
    project_directory = ROOT / "pt.TetrisDuel.xcodeproj"
    project_path = project_directory / "project.pbxproj"
    project_text = project_path.read_text()
    all_sources = list((ROOT / "TetrisDuel").rglob("*.swift")) + list((ROOT / "TetrisDuelTests").rglob("*.swift")) + list((ROOT / "TetrisDuelUITests").rglob("*.swift"))
    validate_localizations(all_sources, project_text)
    for path in all_sources:
        assert path.relative_to(ROOT).as_posix() in project_text, f"Source missing from project: {path}"
    for path in (ROOT / "TetrisDuel/Core").glob("*.swift"):
        assert not re.search(r"import (UIKit|MultipeerConnectivity|CoreBluetooth)", path.read_text()), f"Platform dependency in core: {path}"
    scheme = ET.parse(
        project_directory / "xcshareddata/xcschemes/pt.TetrisDuel.xcscheme"
    )
    assert len(scheme.findall(".//TestableReference")) == 2
    try:
        from openstep_parser import OpenStepDecoder
        with project_path.open() as file:
            project = OpenStepDecoder.ParseFromFile(file)
        objects = project["objects"]
        assert project["rootObject"] in objects
        assert len([obj for obj in objects.values() if obj["isa"] == "PBXNativeTarget"]) == 3
        reference_keys = {"fileRef", "productReference", "buildConfigurationList", "target", "targetProxy", "mainGroup", "productRefGroup", "containerPortal"}
        reference_lists = {"children", "files", "buildPhases", "dependencies", "buildConfigurations", "targets"}
        for obj in objects.values():
            for key, value in obj.items():
                if key in reference_keys:
                    assert value in objects, f"Missing project object: {value}"
                if key in reference_lists:
                    assert all(ref in objects for ref in value), f"Missing object in {key}"
        print(f"Xcode project parsed: {len(objects)} valid objects, 3 targets, all sources linked")
    except ImportError:
        print("OpenStep parser unavailable; checked source references only")
    try:
        import tree_sitter_swift
        from tree_sitter import Language, Parser
        parser = Parser(Language(tree_sitter_swift.language()))
        errors = []
        for path in all_sources + [ROOT / "Package.swift"]:
            tree = parser.parse(path.read_bytes())
            stack = [tree.root_node]
            while stack:
                node = stack.pop()
                if node.type == "ERROR" or node.is_missing:
                    errors.append(f"{path.relative_to(ROOT)}:{node.start_point[0]+1}: {node.type}")
                stack.extend(node.children)
        assert not errors, "Swift syntax errors:\n" + "\n".join(errors)
        print(f"Swift grammar parsed: {len(all_sources)+1} files without syntax errors")
    except ImportError:
        print("Swift grammar parser unavailable; Swift syntax not checked")
    tests = sum(len(re.findall(r"func test\w+\(", p.read_text())) for p in all_sources if "Tests" in str(p))
    print(f"Plists, assets, Wi-Fi permissions and VIPER/core boundaries checked; {tests} XCTest methods provided")
    print("NOT RUN HERE: Xcode build, XCTest execution, simulator UI, two-device Multipeer connectivity")


if __name__ == "__main__":
    validate()
