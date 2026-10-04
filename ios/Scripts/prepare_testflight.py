"""Prepare TestFlight signing files using only Python's standard library."""
import argparse
import base64
from datetime import datetime, timezone
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
BUNDLE_ID = "pro.pteam.TetrisDuel"
INFO_PATH = ROOT / "TetrisDuel/Resources/Info.plist"


def prepare_metadata(
    info,
    profile,
    team_id,
    bundle_id,
    version,
    build_number,
    now,
):
    version = version.removeprefix("v")
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", version):
        raise ValueError("App version must contain one to three numbers")

    if not re.fullmatch(r"[0-9]{1,4}(?:\.[0-9]{1,2}){0,2}", build_number):
        raise ValueError("Invalid Apple build number")

    if int(build_number.split(".")[0]) < 1:
        raise ValueError("The build number must start with a positive number")

    if not re.fullmatch(r"[A-Z0-9]{10}", team_id):
        raise ValueError("APPLE_TEAM_ID must be a ten-character team ID")

    entitlements = profile.get("Entitlements", {})
    if (
        entitlements.get("get-task-allow")
        or "ProvisionedDevices" in profile
        or profile.get("ProvisionsAllDevices")
        or "iOS" not in profile.get("Platform", [])
    ):
        raise ValueError("Use an iOS App Store distribution profile")

    if (
        team_id not in profile.get("TeamIdentifier", [])
        or entitlements.get("com.apple.developer.team-identifier") != team_id
    ):
        raise ValueError("The provisioning profile belongs to another team")

    identifiers = {
        f"{prefix}.{bundle_id}"
        for prefix in profile.get("ApplicationIdentifierPrefix", [])
    }
    if entitlements.get("application-identifier") not in identifiers:
        raise ValueError("The provisioning profile has the wrong bundle ID")

    expiration = profile.get("ExpirationDate")
    if not isinstance(expiration, datetime):
        raise ValueError("The provisioning profile has no expiration date")

    if expiration.tzinfo is None:
        expiration = expiration.replace(tzinfo=timezone.utc)

    if expiration <= now:
        raise ValueError("The provisioning profile has expired")

    profile_uuid = profile.get("UUID", "")
    try:
        uuid.UUID(profile_uuid)
    except (ValueError, AttributeError) as error:
        raise ValueError(
            "The provisioning profile has an invalid UUID",
        ) from error

    result = {
        "info": dict(
            info,
            CFBundleShortVersionString=version,
            CFBundleVersion=build_number,
        ),
        "export_options": {
            "method": "app-store-connect",
            "destination": "export",
            "teamID": team_id,
            "signingStyle": "manual",
            "signingCertificate": "Apple Distribution",
            "provisioningProfiles": {bundle_id: profile_uuid},
            "manageAppVersionAndBuildNumber": False,
            "stripSwiftSymbols": True,
            "uploadSymbols": True,
        },
        "profile_uuid": profile_uuid,
    }
    return result


def required_environment():
    names = (
        "APPLE_TEAM_ID",
        "APPLE_DISTRIBUTION_CERTIFICATE_BASE64",
        "APPLE_PROVISIONING_PROFILE_BASE64",
        "APP_STORE_CONNECT_KEY_ID",
        "APP_STORE_CONNECT_ISSUER_ID",
        "APP_STORE_CONNECT_PRIVATE_KEY",
    )
    result = {name: os.environ.get(name, "") for name in names}
    missing = [name for name, value in result.items() if not value.strip()]
    if missing:
        raise ValueError("Missing GitHub configuration: " + ", ".join(missing))

    if not re.fullmatch(r"[A-Z0-9]{10}", result["APP_STORE_CONNECT_KEY_ID"]):
        raise ValueError("APP_STORE_CONNECT_KEY_ID must be a valid key ID")

    try:
        uuid.UUID(result["APP_STORE_CONNECT_ISSUER_ID"])
    except ValueError as error:
        raise ValueError(
            "APP_STORE_CONNECT_ISSUER_ID must be a UUID",
        ) from error

    private_key = result["APP_STORE_CONNECT_PRIVATE_KEY"].strip()
    if not (
        private_key.startswith("-----BEGIN PRIVATE KEY-----\n")
        and private_key.endswith("-----END PRIVATE KEY-----")
    ):
        raise ValueError(
            "APP_STORE_CONNECT_PRIVATE_KEY must contain the .p8 PEM",
        )

    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--signing-dir", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", required=True)
    arguments = parser.parse_args()
    environment = required_environment()
    directory = arguments.signing_dir
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    certificate = base64.b64decode(
        "".join(environment["APPLE_DISTRIBUTION_CERTIFICATE_BASE64"].split()),
        validate=True,
    )
    profile_bytes = base64.b64decode(
        "".join(environment["APPLE_PROVISIONING_PROFILE_BASE64"].split()),
        validate=True,
    )
    profile_path = directory / "profile.mobileprovision"
    profile_path.write_bytes(profile_bytes)
    decoded = subprocess.run(
        ["security", "cms", "-D", "-i", str(profile_path)],
        capture_output=True,
        check=False,
    )
    if decoded.returncode:
        raise ValueError("Cannot decode APPLE_PROVISIONING_PROFILE_BASE64")

    metadata = prepare_metadata(
        info=plistlib.loads(INFO_PATH.read_bytes()),
        profile=plistlib.loads(decoded.stdout),
        team_id=environment["APPLE_TEAM_ID"],
        bundle_id=BUNDLE_ID,
        version=arguments.version,
        build_number=arguments.build_number,
        now=datetime.now(timezone.utc),
    )
    (directory / "certificate.p12").write_bytes(certificate)
    keys_directory = directory / "private_keys"
    keys_directory.mkdir(mode=0o700, exist_ok=True)
    key_id = environment["APP_STORE_CONNECT_KEY_ID"]
    key_path = keys_directory / f"AuthKey_{key_id}.p8"
    key_path.write_text(
        environment["APP_STORE_CONNECT_PRIVATE_KEY"].strip() + "\n",
        encoding="utf-8",
    )
    key_path.chmod(0o600)
    (directory / "ExportOptions.plist").write_bytes(
        plistlib.dumps(metadata["export_options"]),
    )
    INFO_PATH.write_bytes(plistlib.dumps(metadata["info"], sort_keys=False))
    print(metadata["profile_uuid"])


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError) as error:
        print(f"TestFlight preparation failed: {error}", file=sys.stderr)
        sys.exit(1)
