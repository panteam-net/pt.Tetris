"""Check release metadata and reject unsuitable Apple signing profiles."""
from copy import deepcopy
from datetime import datetime, timedelta, timezone
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from prepare_testflight import prepare_metadata


class PrepareTestFlightTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 10, 4, tzinfo=timezone.utc)
        self.team = "RUPH5Y35UV"
        self.bundle = "pro.pteam.TetrisDuel"
        self.profile = {
            "UUID": "C8317CDA-6AC5-4EBC-9C94-44CB80EA3785",
            "TeamIdentifier": [self.team],
            "ApplicationIdentifierPrefix": [self.team],
            "Platform": ["iOS"],
            "ExpirationDate": self.now + timedelta(days=30),
            "Entitlements": {
                "application-identifier": f"{self.team}.{self.bundle}",
                "com.apple.developer.team-identifier": self.team,
                "get-task-allow": False,
            },
        }
        self.info = {
            "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "CFBundleLocalizations": ["en", "ru"],
            "ITSAppUsesNonExemptEncryption": False,
        }

    def prepare(self, version="v1.2.3", build_number="42.2"):
        result = prepare_metadata(
            info=self.info,
            profile=self.profile,
            team_id=self.team,
            bundle_id=self.bundle,
            version=version,
            build_number=build_number,
            now=self.now,
        )
        return result

    def test_sets_version_without_mutating_the_input_plist(self):
        original = deepcopy(self.info)
        result = self.prepare()

        self.assertEqual(result["info"]["CFBundleShortVersionString"], "1.2.3")
        self.assertEqual(result["info"]["CFBundleVersion"], "42.2")
        self.assertEqual(result["info"]["CFBundleLocalizations"], ["en", "ru"])
        self.assertFalse(result["info"]["ITSAppUsesNonExemptEncryption"])
        self.assertEqual(self.info, original)

    def test_exports_with_the_exact_profile_and_preserves_build_number(self):
        result = self.prepare()
        options = result["export_options"]

        self.assertEqual(options["method"], "app-store-connect")
        self.assertEqual(options["destination"], "export")
        self.assertEqual(options["signingStyle"], "manual")
        self.assertEqual(options["teamID"], self.team)
        self.assertEqual(
            options["provisioningProfiles"],
            {self.bundle: self.profile["UUID"]},
        )
        self.assertFalse(options["manageAppVersionAndBuildNumber"])

    def test_accepts_manual_version_and_naive_profile_expiration(self):
        self.profile["ExpirationDate"] = (
            self.profile["ExpirationDate"].replace(tzinfo=None)
        )
        result = self.prepare(version="1.0")

        self.assertEqual(result["info"]["CFBundleShortVersionString"], "1.0")

    def test_accepts_an_app_id_prefix_different_from_the_team_id(self):
        self.profile["ApplicationIdentifierPrefix"] = ["OLDPREFIX1"]
        self.profile["Entitlements"]["application-identifier"] = (
            f"OLDPREFIX1.{self.bundle}"
        )

        self.prepare()

    def test_rejects_development_ad_hoc_and_enterprise_profiles(self):
        for changes in (
            {"Entitlements": {"get-task-allow": True}},
            {"ProvisionedDevices": ["device-id"]},
            {"ProvisionsAllDevices": True},
        ):
            with self.subTest(changes=changes):
                original = deepcopy(self.profile)
                self.profile.update(changes)
                with self.assertRaisesRegex(ValueError, "App Store"):
                    self.prepare()

                self.profile = original

    def test_rejects_the_wrong_team(self):
        self.profile["TeamIdentifier"] = ["OTHERTEAM1"]

        with self.assertRaisesRegex(ValueError, "team"):
            self.prepare()

    def test_rejects_wrong_or_wildcard_bundle_identifiers(self):
        for bundle in ("pro.pteam.OtherApp", "*"):
            with self.subTest(bundle=bundle):
                self.profile["Entitlements"]["application-identifier"] = (
                    f"{self.team}.{bundle}"
                )
                with self.assertRaisesRegex(ValueError, "bundle"):
                    self.prepare()

    def test_rejects_an_expired_profile(self):
        self.profile["ExpirationDate"] = self.now - timedelta(seconds=1)

        with self.assertRaisesRegex(ValueError, "expired"):
            self.prepare()

    def test_rejects_an_invalid_profile_uuid(self):
        self.profile["UUID"] = "not-a-uuid"

        with self.assertRaisesRegex(ValueError, "UUID"):
            self.prepare()

    def test_rejects_versions_that_cannot_be_uploaded_to_apple(self):
        for version in ("", "main", "v1.0-beta", "1.2.3.4", "1.0\n"):
            with self.subTest(version=version):
                with self.assertRaisesRegex(ValueError, "version"):
                    self.prepare(version=version)

    def test_rejects_invalid_build_numbers(self):
        for number in ("", "0", "12-beta", "1.2.3.4", "10000.1", "1.100"):
            with self.subTest(number=number):
                with self.assertRaisesRegex(ValueError, "build number"):
                    self.prepare(build_number=number)


if __name__ == "__main__":
    unittest.main()
