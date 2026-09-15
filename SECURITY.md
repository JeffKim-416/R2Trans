# Security Policy

## API Keys

R2Trans does not include an OpenAI API key. Each user must enter their own API key in the app settings after installing the app.

The API key is stored locally in the user's macOS data-protection Keychain through `KeychainStore`, using `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Existing file-based Keychain items are copied and verified before legacy cleanup is attempted, so a cleanup failure cannot discard the migrated credential. The app does not write API keys to source files, build artifacts, app metadata, logs, or UserDefaults.

Ad-hoc local development builds cannot establish the production app's Apple Developer identity. Their explicit compatibility fallback may continue to use the legacy file-based Keychain. Ad-hoc artifacts must not be distributed.

## Data Sent to OpenAI

R2Trans sends selected text to OpenAI when the user triggers a text translation.

When the user starts a Live Interpreter session, R2Trans sends microphone audio and/or system audio to OpenAI. It may also send rolling source-transcript excerpts to the OpenAI Responses API to produce provisional subtitles.

When the user starts Live Transcription, R2Trans sends microphone audio and/or system audio to OpenAI's `gpt-live-transcribe` model to produce a transcript.

Do not use R2Trans with text or audio you are not allowed to send to OpenAI.

## macOS Permissions

R2Trans may request these macOS permissions:

- Accessibility: used for global copy and paste.
- Microphone: used for microphone-based live interpretation and live transcription.
- Screen & System Audio Recording: used for system-audio live interpretation and live transcription.
- Launch at Login: optional, used only when enabled by the user.

## Release Integrity

Official signed releases must be universal (`arm64` and `x86_64`), signed with a Developer ID Application certificate and hardened runtime, notarized by Apple, and stapled before upload. The default open-source workflow publishes an ad-hoc signed, unnotarized artifact and clearly labels it as such.

Each release includes `R2Trans.dmg.sha256`. Verify a downloaded DMG with:

```sh
shasum -a 256 -c R2Trans.dmg.sha256
spctl --assess --type open --context context:primary-signature --verbose=4 R2Trans.dmg
```

## Repository Hygiene

Before publishing changes, inspect the staged diff, tracked files, ignored files, and generated artifacts. The commands below avoid printing complete matching secret lines:

```sh
git diff --cached --check
git grep -IlE 'sk-[A-Za-z0-9_-]{20,}|Bearer[[:space:]]+[A-Za-z0-9._-]{20,}|BEGIN .*PRIVATE KEY' -- . ':!SECURITY.md'
git grep -IlF "/Users/$(id -un)/" -- . ':!SECURITY.md'
git status --short --ignored
```

If `gitleaks` is installed, also run:

```sh
gitleaks git --redact --no-banner
```

Do not commit:

- API keys or bearer tokens
- Local absolute paths
- Code signing identities or certificates
- Provisioning profiles
- Notarization private keys
- Generated app bundles, DMGs, packages, or archives
- Local IDE, assistant, or machine-specific settings

Release credential names and setup are documented in `RELEASING.md`; their values belong only in GitHub Actions secrets.

## Reporting Vulnerabilities

Report vulnerabilities privately through [GitHub Security Advisories](https://github.com/JeffKim-416/R2Trans/security/advisories/new). Do not open a public issue for a vulnerability before a fix is available.
