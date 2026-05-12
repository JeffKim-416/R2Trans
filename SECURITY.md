# Security Policy

## API Keys

R2Trans does not include an OpenAI API key. Each user must enter their own API key in the app settings after installing the app.

The API key is stored locally in the user's macOS Keychain through `KeychainStore`. It is not written to source files, build artifacts, app metadata, logs, or UserDefaults by the app.

## Data Sent to OpenAI

R2Trans sends selected text to OpenAI when the user triggers a text translation.

The Live Interpreter sends microphone audio and/or system audio to OpenAI when the user starts a live interpreter session.

Do not use R2Trans with text or audio you are not allowed to send to OpenAI.

## macOS Permissions

R2Trans may request these macOS permissions:

- Accessibility: used for global copy and paste.
- Microphone: used for microphone-based live interpretation.
- Screen & System Audio Recording: used for system-audio live interpretation.
- Launch at Login: optional, used only when enabled by the user.

## Repository Hygiene

Before publishing changes, check that no local secrets or personal machine paths are included:

```sh
rg -n "$(id -un)|OPENAI_API_KEY|sk-[A-Za-z0-9_-]+|BEGIN .*PRIVATE KEY|R2TRANS_CODESIGN_IDENTITY" .
git status --short --ignored
```

Do not commit:

- API keys or bearer tokens
- Local absolute paths
- Code signing identities or certificates
- Provisioning profiles
- Generated app bundles, DMGs, packages, or archives
- Local IDE, assistant, or machine-specific settings

## Reporting Vulnerabilities

If you publish this project publicly, add your preferred security contact here so users can report vulnerabilities privately.
