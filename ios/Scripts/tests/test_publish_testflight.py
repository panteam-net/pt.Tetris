"""Keep TestFlight signing settings scoped to the app target."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PublishTestFlightTests(unittest.TestCase):
    def test_manual_signing_is_configured_only_on_the_app_release_target(self):
        project = (ROOT / "pt.TetrisDuel.xcodeproj/project.pbxproj").read_text()
        release = re.search(
            r"F10AEB8D0775536BCC747138 /\* Release \*/ = \{(.*?)\n\t\t};",
            project,
            re.DOTALL,
        )

        self.assertIsNotNone(release)
        self.assertIn('CODE_SIGN_IDENTITY = "Apple Distribution";', release.group(1))
        self.assertIn("CODE_SIGN_STYLE = Manual;", release.group(1))
        self.assertIn(
            'PROVISIONING_PROFILE_SPECIFIER = "$(TESTFLIGHT_PROVISIONING_PROFILE_UUID)";',
            release.group(1),
        )

    def test_archive_passes_profile_uuid_without_global_signing_overrides(self):
        publisher = (ROOT / "Scripts/publish_testflight.sh").read_text()

        self.assertIn(
            'TESTFLIGHT_PROVISIONING_PROFILE_UUID="$profile_uuid"',
            publisher,
        )
        self.assertNotIn("PROVISIONING_PROFILE_SPECIFIER=", publisher)
        self.assertNotIn("CODE_SIGN_STYLE=", publisher)
        self.assertNotIn("CODE_SIGN_IDENTITY=", publisher)


if __name__ == "__main__":
    unittest.main()
