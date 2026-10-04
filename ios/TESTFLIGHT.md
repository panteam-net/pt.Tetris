# GitHub Actions → TestFlight

The workflow is [`.github/workflows/ios.yml`](../.github/workflows/ios.yml).
It uses GitHub-hosted `macos-26` runners, Xcode 26.3, and Apple's command-line
tools. Signing and release preparation use Python's standard library and Bash.

## What runs

| Event | Result |
| --- | --- |
| iOS/workflow pull request | Build and test on iPhone and iPad simulators |
| iOS/workflow push to `main` | Build and test on both simulators |
| Push a numeric version tag, e.g. `v1.0.0` | Test, sign, archive, upload |
| Manual **Run workflow** with a version | Test, sign, archive, upload |

The publish job depends on both simulator jobs passing. The iPhone job also
runs static project validation, release-preparation tests, and portable Swift
core tests. Swift packages are resolved from the committed `Package.resolved`.

The app version comes from the tag without `v`, or from the manual input.
The build number is `<GitHub run number>.<run attempt>`: for example `42.1`,
then `42.2` on retry, and `43.1` on the next run. These values are written into
the checkout's `Info.plist` before archiving because its versions are literal
strings. Xcode's automatic build-number management is disabled during export.

Test results and logs are saved as workflow artifacts for 14 days. The publish
job also saves its `.xcarchive`, exported `.ipa`, and archive/upload logs.
Signing files are kept in a separate temporary directory and cleaned up on
success or failure, together with the temporary keychain and installed profile.

## One-time Apple setup

1. Use an active paid Apple Developer Program team.
2. Register the explicit App ID **`pro.pteam.TetrisDuel`** for that team.
3. Create an iOS app in App Store Connect with this exact bundle identifier.
4. Create an **Apple Distribution** certificate. In macOS Keychain Access,
   export its identity from **My Certificates** as a password-protected `.p12`.
   The export must contain the certificate and its private key.
5. Create an **App Store Connect** distribution provisioning profile for this
   App ID, selecting that distribution certificate, and download it.
6. In App Store Connect → **Users and Access → Integrations → App Store Connect
   API → Team Keys**, create an API key with **App Manager** access. Download
   the `.p8` private key and record its **Key ID** and **Issuer ID**.

The workflow expects a team API key. A development, ad hoc, or enterprise
profile is rejected before archiving. The profile must be unexpired and match
the configured team and app bundle identifier.

## GitHub configuration

In the repository's **Settings → Environments**, create an environment named
**`testflight`**. Add the following environment variable and secrets there.
Repository-level Actions variables/secrets with the same names also work.

### Variable

- **`APPLE_TEAM_ID`** — your ten-character Apple developer team ID.
  The checked-in project currently uses `RUPH5Y35UV`. The workflow passes this
  variable to Xcode when signing, so it can use your selected team.

### Secrets

- **`APPLE_DISTRIBUTION_CERTIFICATE_BASE64`** — Base64 of the `.p12` identity.
- **`APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD`** — the `.p12` export password.
- **`APPLE_PROVISIONING_PROFILE_BASE64`** — Base64 of the `.mobileprovision`.
- **`APP_STORE_CONNECT_KEY_ID`** — the team API key's Key ID.
- **`APP_STORE_CONNECT_ISSUER_ID`** — the team's API Issuer ID.
- **`APP_STORE_CONNECT_PRIVATE_KEY`** — the complete contents of the `.p8`
  file, including its `BEGIN PRIVATE KEY` and `END PRIVATE KEY` lines. Paste
  the PEM text directly; this secret is not Base64-encoded.

On a Mac, copy the signing files to the clipboard for their respective secrets:

```sh
base64 -i "AppleDistribution.p12" | pbcopy
base64 -i "TetrisDuel.mobileprovision" | pbcopy
pbcopy < "AuthKey_YOUR_KEY_ID.p8"
```

The publisher creates a temporary keychain with a random password. No separate
keychain password secret or Apple account password is needed.

## Publish a build

After committing and pushing the workflow to GitHub, either:

### Run manually

1. Open **Actions → iOS build and TestFlight → Run workflow**.
2. Select the branch to build, normally `main`.
3. Enter a numeric app version, for example `1.0.0`.
4. Run the workflow. Its publish job starts after the tests pass.

### Push a version tag

Tag the commit you want to distribute:

```sh
git tag v1.0.0
git push origin v1.0.0
```

Tags must contain a numeric Apple version with up to three components. Use
`v1.0.0`, rather than prerelease suffixes such as `v1.0.0-beta`.

## Make the uploaded build available to testers

A successful upload means Apple accepted the delivery. Apple still processes
the build before it appears in **App Store Connect → your app → TestFlight**.

Create an internal testing group and add the processed build and testers. You
can enable automatic distribution for future builds in that group's settings.
Complete any export-compliance prompts shown for the build.

For external testers, create an external group, provide the beta test/review
information, and submit the first build for TestFlight App Review. After
approval, invite people by email or share the group's public invitation link.
TestFlight builds expire after 90 days. App Store release submission is a
separate step in App Store Connect.

The current app includes Firebase Analytics; reflect its collection in your
privacy policy and data disclosures. Nearby multiplayer acceptance checks are
in [`DEVICE_TESTS.md`](DEVICE_TESTS.md).

## Troubleshooting and maintenance

- **Missing GitHub configuration:** add the named variable/secrets to the
  `testflight` environment or the repository's Actions settings.
- **Signing certificate/profile mismatch:** regenerate the profile with the
  certificate whose private key was exported in the `.p12`.
- **Expired profile/certificate:** renew it and update the signing secrets.
- **Duplicate or lower build number:** check existing TestFlight builds. For an
  app already using higher numbers, adjust `BUILD_NUMBER` in the workflow to
  continue that numbering, or start a new app version. Every retry includes its
  run attempt; Apple still enforces increasing build numbers per version.
- **Rejected upload or processing failure:** inspect the workflow's upload
  log and Apple's processing email; correct the issue before another run.
- **Runner image changes:** update `DEVELOPER_DIR`, the cache's Xcode version,
  and the simulator OS/device matrix together in the workflow.

The workflow builds the checked-in Xcode project. The project generator still
uses template signing identifiers and lacks the current Firebase additions;
regenerating the project requires reapplying those customizations.

Local checks, from the repository root:

```sh
python3 -B -m unittest discover -s ios/Scripts/tests -v
bash -n ios/Scripts/publish_testflight.sh
actionlint .github/workflows/ios.yml
```
