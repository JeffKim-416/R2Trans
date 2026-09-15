# Release Automation

R2Trans releases are built by GitHub Actions. Release artifacts and credentials are never committed to the repository.

## Version Source of Truth

`VERSION` is the single source of truth for `CFBundleShortVersionString`. Before creating a release, update and commit `VERSION` using the exact `X.Y.Z` value that the tag will use.

The build rejects a release tag or `R2TRANS_VERSION` that does not match `VERSION`. This also keeps builds from a GitHub source ZIP or from `main` on the correct version when Git metadata is unavailable or the checkout is not exactly on a tag.

## Unsigned open-source releases

The default GitHub Actions release workflow does not require Apple credentials or GitHub Secrets. It builds an ad-hoc signed universal DMG and uploads it to a GitHub Release. Users may need to approve the unsigned app in macOS Privacy & Security settings.

For a signed and notarized distribution, configure the following repository Actions secrets:

- `MACOS_CERTIFICATE_BASE64`: base64-encoded Developer ID Application certificate and private key exported as PKCS#12 (`.p12`).
- `MACOS_CERTIFICATE_PASSWORD`: password used when exporting the `.p12`.
- `MACOS_SIGNING_IDENTITY`: full Keychain identity name, such as `Developer ID Application: Example (TEAMID1234)`.
- `MACOS_PROVISIONING_PROFILE_BASE64`: base64-encoded Developer ID provisioning profile for `io.github.r2trans.R2Trans`.
- `APPLE_TEAM_ID`: 10-character Apple Developer Team ID.
- `APPLE_NOTARY_KEY_ID`: App Store Connect API key ID.
- `APPLE_NOTARY_ISSUER_ID`: App Store Connect API issuer UUID.
- `APPLE_NOTARY_KEY_BASE64`: base64-encoded App Store Connect `.p8` private key.

The provisioning profile's application identifier must end in `.io.github.r2trans.R2Trans`. Its App ID prefix is used as part of the stable data-protection Keychain access group; for most teams this prefix is the Team ID, but older accounts can differ. Never paste decoded credentials into Actions logs.

## Create a Release

1. Update `VERSION` and commit all intended release changes.
2. Create and push the matching tag:

   ```sh
   version="$(tr -d '[:space:]' < VERSION)"
   git tag "v$version"
   git push origin "v$version"
   ```

3. GitHub Actions runs `.github/workflows/release.yml` on the pinned `macos-15` runner and Xcode 16.4 toolchain.
4. The read-only build job cross-compiles `arm64` and `x86_64`, creates a universal app, imports temporary signing credentials, applies hardened runtime and a secure timestamp, notarizes and staples the app and DMG, and verifies both with `codesign`, `stapler`, and `spctl`.
5. A separate job with `contents: write` permission publishes `R2Trans.dmg` and `R2Trans.dmg.sha256`. Repository code never runs in that write-enabled job.

## Update Existing Release Assets

To rebuild an existing release, run the `Release` workflow manually with its exact tag. The tag must still match the `VERSION` file in that tagged commit. The publish job uses `gh release upload --clobber` after the replacement assets pass signing and notarization checks.

## Local Development Builds

Ad-hoc signing is an explicit local-only fallback:

```sh
R2TRANS_ALLOW_ADHOC=1 Scripts/build_app.sh
R2TRANS_ALLOW_ADHOC=1 Scripts/create_dmg.sh
```

`Install.command` passes this opt-in for source ZIP installation. Local artifacts are universal and hardened but are not authenticated or notarized, will fail Gatekeeper distribution assessment, and may use the legacy Keychain fallback because they do not have the production Developer ID application identifier. Never upload them to a release.

Without `R2TRANS_ALLOW_ADHOC=1`, a missing signing identity is a build error. CI additionally sets `R2TRANS_REQUIRE_DISTRIBUTION=1`, which prevents ad-hoc fallback even if it is accidentally requested.

## Manual Verification

After a successful distribution build, verify the artifacts before upload:

```sh
codesign --verify --deep --strict --verbose=2 build/R2Trans.app
lipo -archs build/R2Trans.app/Contents/MacOS/R2Trans
xcrun stapler validate build/R2Trans.app
spctl --assess --type execute --verbose=4 build/R2Trans.app
codesign --verify --verbose=2 build/R2Trans.dmg
xcrun stapler validate build/R2Trans.dmg
spctl --assess --type open --context context:primary-signature --verbose=4 build/R2Trans.dmg
(cd build && shasum -a 256 -c R2Trans.dmg.sha256)
```
