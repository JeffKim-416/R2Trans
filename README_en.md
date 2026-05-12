# R2Trans

A friendly macOS menu bar app for translating selected text with one global hotkey.

Select text in the app you are already using, press the hotkey, and R2Trans replaces the selection with a translated version. It works nicely with Notes, browsers, document editors, email drafts, and most places where copy and paste work.

[한국어 README](README.md)

## What It Does

- Translates selected text with a global hotkey.
- Supports translation directions such as `Korean -> English`, `English -> Korean`, `Japanese -> Korean`, and `Spanish -> English`.
- Can auto-detect direction for `Korean <-> English` and `Korean <-> Japanese`.
- Lets you choose a translation style: Natural, Formal, Polite, Overly Deferential, or Nyang style.
- Can show a confirmation window before replacing the selected text.
- Includes a Live Interpreter for translating microphone audio, system audio, or both.
- Provides quick menu bar controls for translation mode, auto detect, confirmation, style, Live Interpreter, and Launch at Login.

## How It Works

R2Trans copies the selected text, sends it to the OpenAI Responses API for translation, pastes the translated text back into the original selection, and then restores your previous clipboard.

The app does not include an OpenAI API key. Each user enters their own API key in the app settings, and the key is stored in the macOS Keychain.

## Supported Languages

R2Trans currently includes these language codes:

```text
en-US English
ko-KR Korean
es-ES Spanish
ja-JP Japanese
zh-CN Chinese
```

## Install Locally

Build the app first:

```sh
Scripts/build_app.sh
```

The app bundle is created at:

```text
build/R2Trans.app
```

For daily use, install the app into `/Applications`. This gives macOS a stable app path for Accessibility permission, which can otherwise break when the app path or code signature changes.

```sh
Scripts/install_app.sh
```

The app is copied to:

```text
/Applications/R2Trans.app
```

Launch `/Applications/R2Trans.app`, then grant macOS Accessibility permission when prompted.

## First-Time Setup

1. Launch `/Applications/R2Trans.app`.
2. Open `R2Trans Settings`.
3. Enter your own OpenAI API key.
4. Choose the translation mode, auto-detect behavior, translation style, OpenAI model, and hotkey.
5. Use the gear button in the settings title bar to change the app language immediately.
6. Enable `Launch at Login` if you want R2Trans to start automatically.
7. Grant macOS Accessibility permission when prompted.

The default hotkey is:

```text
control+option+t
```

Hotkeys support `command`, `control`, `option`, `shift`, letters, numbers, punctuation, and `space`.

## Permissions

R2Trans only asks for permissions needed by its features.

- Accessibility: required to copy selected text and paste translated text.
- Microphone: required for microphone translation in Live Interpreter.
- Screen & System Audio Recording: required for system audio translation in Live Interpreter.

If Accessibility permission is already enabled but R2Trans still asks again, remove the old R2Trans entry from System Settings, add `/Applications/R2Trans.app` again, then relaunch R2Trans.

## Create a DMG

To create an installer image:

```sh
Scripts/create_dmg.sh
```

The DMG is created at:

```text
build/R2Trans.dmg
```

## Privacy and Security

- OpenAI API keys are entered by each user in the app settings.
- API keys are stored in the user's macOS Keychain via `KeychainStore`.
- API keys are not stored in this repository, build scripts, app bundle metadata, or UserDefaults.
- Text selected for translation and Live Interpreter audio are sent to OpenAI to perform the requested translation.
- Local build artifacts, DMGs, app bundles, local IDE settings, environment files, certificates, provisioning profiles, logs, and local assistant settings are ignored by `.gitignore`.
- Do not commit local absolute paths, personal names, API keys, certificates, provisioning profiles, or generated app bundles.

Before publishing a fork or release, run:

```sh
rg -n "$(id -un)|OPENAI_API_KEY|sk-[A-Za-z0-9_-]+|BEGIN .*PRIVATE KEY|R2TRANS_CODESIGN_IDENTITY" .
git status --short --ignored
```

## Code Signing

Development builds are ad-hoc signed by default. Rebuilding the app can change the code signature macOS uses for Accessibility trust.

To sign with a stable local certificate instead, run:

```sh
R2TRANS_CODESIGN_IDENTITY="Your Code Signing Certificate" Scripts/install_app.sh
```

## License

R2Trans is released under the MIT License. See [LICENSE](LICENSE).
