"""Keep localization validation compatible with Xcode's extracted metadata."""
from copy import deepcopy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import validate_project


class ValidateProjectTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.resources = self.root / "TetrisDuel/Resources"
        self.resources.mkdir(parents=True)
        self.localizations = {
            language: {
                "stringUnit": {"state": "translated", "value": "Hello %@"},
            }
            for language in ("en", "ru")
        }

    def validate(self, info_entries, ui_entries=None):
        catalogs = {
            "InfoPlist": info_entries,
            "Localizable": ui_entries or {},
        }
        references = []
        for name, strings in catalogs.items():
            path = self.resources / f"{name}.xcstrings"
            path.write_text(
                json.dumps({"sourceLanguage": "en", "strings": strings}),
                encoding="utf-8",
            )
            references.append(path.relative_to(self.root).as_posix())

        with patch.object(validate_project, "ROOT", self.root):
            validate_project.validate_localizations([], "\n".join(references))

    def test_accepts_xcode_extracted_bundle_names_in_the_source_language(self):
        entries = {
            "NSLocalNetworkUsageDescription": {
                "localizations": self.localizations,
            },
        }
        for name in ("CFBundleDisplayName", "CFBundleName"):
            entries[name] = {
                "extractionState": "extracted_with_value",
                "localizations": {
                    "en": {
                        "stringUnit": {
                            "state": "new",
                            "value": "pt.TetrisDuel",
                        },
                    },
                },
            }

        self.validate(entries)

    def test_permission_text_still_requires_russian(self):
        del self.localizations["ru"]

        with self.assertRaises(KeyError):
            self.validate({
                "NSLocalNetworkUsageDescription": {
                    "localizations": self.localizations,
                },
            })

    def test_manual_ui_strings_still_require_a_translated_state(self):
        info_localizations = deepcopy(self.localizations)
        self.localizations["en"]["stringUnit"]["state"] = "new"

        with self.assertRaisesRegex(AssertionError, "Untranslated"):
            self.validate(
                info_entries={
                    "NSLocalNetworkUsageDescription": {
                        "localizations": info_localizations,
                    },
                },
                ui_entries={
                    "menu.title": {"localizations": self.localizations},
                },
            )


if __name__ == "__main__":
    unittest.main()
