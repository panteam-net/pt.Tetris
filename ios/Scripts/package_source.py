"""Bundle a clean, portable source project for transfer to a Mac."""
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE_ROOT = "pt.TetrisDuel-iOS"
OUTPUT = ROOT.parent / "artifacts" / (ARCHIVE_ROOT + ".zip")
EXCLUDED = {".validation", ".build", ".swiftpm", "build", "DerivedData", "__pycache__", "xcuserdata", "TestResults.xcresult"}

OUTPUT.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(OUTPUT, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for path in sorted(ROOT.rglob("*")):
        relative = path.relative_to(ROOT)
        if path.is_file() and not any(part in EXCLUDED for part in relative.parts) and path.suffix != ".pyc":
            archive.write(
                path,
                ARCHIVE_ROOT + "/ios/" + relative.as_posix(),
            )
    workflow = ROOT.parent / ".github/workflows/ios.yml"
    archive.write(
        workflow,
        ARCHIVE_ROOT + "/.github/workflows/ios.yml",
    )
    archive.writestr(
        ARCHIVE_ROOT + "/README.md",
        "# pt.TetrisDuel for iOS\n\n"
        "Open `ios/pt.TetrisDuel.xcodeproj` in Xcode 15+ on a Mac.\n"
        "See `ios/README.md` for setup, architecture and validation status.\n"
        "UIKit, VIPER, dependency injection and nearby Wi-Fi multiplayer "
        "with Multipeer Connectivity.\n",
    )
with zipfile.ZipFile(OUTPUT) as archive:
    assert archive.testzip() is None
    assert (
        ARCHIVE_ROOT + "/ios/pt.TetrisDuel.xcodeproj/project.pbxproj"
    ) in archive.namelist()
    assert not any("/.validation/" in name for name in archive.namelist())
    print(f"Packaged {len(archive.namelist())} files: {OUTPUT} ({OUTPUT.stat().st_size:,} bytes)")
