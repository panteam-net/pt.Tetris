#!/bin/bash
# Run from ios/ on a GitHub-hosted macOS runner.
set -euo pipefail
umask 077

: "${RUNNER_TEMP:?GitHub Actions RUNNER_TEMP is required}"
: "${RELEASE_VERSION:?A release version is required}"
: "${BUILD_NUMBER:?A build number is required}"

signing_dir=$(mktemp -d "$RUNNER_TEMP/testflight-signing.XXXXXX")
keychain_path="$signing_dir/signing.keychain-db"
output_dir="$RUNNER_TEMP/testflight"
info_path="TetrisDuel/Resources/Info.plist"
profile_path=""

cleanup() {
    local status=$?
    trap - EXIT
    security delete-keychain "$keychain_path" >/dev/null 2>&1 || true
    if [[ -f "$signing_dir/keychains.txt" ]]; then
        xargs security list-keychains -d user -s \
            < "$signing_dir/keychains.txt" || true
    fi

    if [[ -n "$profile_path" ]]; then
        rm -f "$profile_path"
    fi

    if [[ -f "$signing_dir/Info.plist" ]]; then
        cp "$signing_dir/Info.plist" "$info_path"
    fi

    rm -rf "$signing_dir"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

cp "$info_path" "$signing_dir/Info.plist"
profile_uuid=$(python3 -B Scripts/prepare_testflight.py \
    --signing-dir "$signing_dir" \
    --version "$RELEASE_VERSION" \
    --build-number "$BUILD_NUMBER")

keychain_password=$(openssl rand -hex 32)
printf '::add-mask::%s\n' "$keychain_password"
security list-keychains -d user > "$signing_dir/keychains.txt"
security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
security import "$signing_dir/certificate.p12" \
    -P "${APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD:-}" \
    -A -t cert -f pkcs12 -k "$keychain_path"
security set-key-partition-list -S apple-tool:,apple: \
    -k "$keychain_password" "$keychain_path" >/dev/null
security list-keychains -d user -s "$keychain_path"

profiles_dir="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
mkdir -p "$profiles_dir"
profile_path="$profiles_dir/$profile_uuid.mobileprovision"
cp "$signing_dir/profile.mobileprovision" "$profile_path"
mkdir -p "$output_dir"

xcodebuild -resolvePackageDependencies \
    -project pt.TetrisDuel.xcodeproj \
    -scheme pt.TetrisDuel \
    -clonedSourcePackagesDirPath "$RUNNER_TEMP/SourcePackages" \
    -onlyUsePackageVersionsFromResolvedFile

xcodebuild archive \
    -project pt.TetrisDuel.xcodeproj \
    -scheme pt.TetrisDuel \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$output_dir/pt.TetrisDuel.xcarchive" \
    -derivedDataPath "$RUNNER_TEMP/ReleaseDerivedData" \
    -clonedSourcePackagesDirPath "$RUNNER_TEMP/SourcePackages" \
    -disableAutomaticPackageResolution \
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
    TESTFLIGHT_PROVISIONING_PROFILE_UUID="$profile_uuid" \
    | tee "$output_dir/archive.log"

xcodebuild -exportArchive \
    -archivePath "$output_dir/pt.TetrisDuel.xcarchive" \
    -exportPath "$output_dir/export" \
    -exportOptionsPlist "$signing_dir/ExportOptions.plist" \
    | tee "$output_dir/export.log"

API_PRIVATE_KEYS_DIR="$signing_dir/private_keys" \
    xcrun altool --upload-app \
    --platform ios \
    --file "$output_dir/export/pt.TetrisDuel.ipa" \
    --api-key "$APP_STORE_CONNECT_KEY_ID" \
    --api-issuer "$APP_STORE_CONNECT_ISSUER_ID" \
    | tee "$output_dir/upload.log"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf '## TestFlight upload\n\nVersion: %s — build: %s\n\n' \
        "${RELEASE_VERSION#v}" "$BUILD_NUMBER" >> "$GITHUB_STEP_SUMMARY"
    printf '%s\n' \
        'Uploaded to App Store Connect. Check TestFlight after processing.' \
        >> "$GITHUB_STEP_SUMMARY"
fi
