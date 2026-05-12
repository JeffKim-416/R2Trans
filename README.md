# R2Trans

R2Trans is a macOS app that translates selected text in other apps with a global hotkey.
Each user provides their own OpenAI API key in the app settings; no API key is bundled with the app or stored in this repository.

## Behavior

- Choose a translation mode such as `ko-KR->en-US`, `en-US->ko-KR`, `es-ES->en-US`, or `ja-JP->ko-KR`.
- Optionally enable auto detect for `ko-KR<->en-US` or `ko-KR<->ja-JP`.
- Choose a translation style: Natural, Formal, Polite, Overly Deferential, or Nyang style for Korean output.
- Optionally confirm the translated text before replacing the current selection.
- Select text in Notes, browsers, document editors, or other apps, then press the hotkey to replace the selection with the translation.
- R2Trans copies the selected text, sends it to the OpenAI Responses API, pastes the translated text, then restores the previous clipboard.
- A Live Interpreter window can translate speech into the selected target language using microphone audio, system audio, or both.
- macOS Accessibility permission is required for global copy and paste.
- Microphone permission is required for microphone interpretation, and Screen & System Audio Recording permission is required for system audio interpretation.
- A `Translating...` popup appears while translation is running and disappears automatically when it finishes.
- The menu bar item provides quick controls for translation mode, auto detect, confirm-before-replace, style, Live Interpreter, and Launch at Login.

## Supported Languages

R2Trans currently includes these language codes:

```text
en-US English
ko-KR Korean
es-ES Spanish
ja-JP Japanese
zh-CN Chinese
```

## Build

```sh
Scripts/build_app.sh
```

The app bundle is created at:

```text
build/R2Trans.app
```

To create a DMG:

```sh
Scripts/create_dmg.sh
```

The installer image is created at:

```text
build/R2Trans.dmg
```

## Install Locally

For daily use, run the app from one stable location. Accessibility permission can
break if macOS sees a different app path or code signature.

```sh
Scripts/install_app.sh
```

This copies the latest build to:

```text
/Applications/R2Trans.app
```

Grant Accessibility permission to that exact app in System Settings.

If Accessibility permission is already enabled but R2Trans still asks again,
remove the old R2Trans entry from System Settings, add `/Applications/R2Trans.app`
again, then relaunch R2Trans.

Development builds are ad-hoc signed by default. Rebuilding the app can change
the code signature macOS uses for Accessibility trust. To sign with a stable
local certificate instead, set:

```sh
R2TRANS_CODESIGN_IDENTITY="Your Code Signing Certificate" Scripts/install_app.sh
```

## Setup

1. Launch `/Applications/R2Trans.app`.
2. Open `R2Trans Settings`.
3. Enter your own OpenAI API key.
4. Choose the translation mode, auto detect behavior, translation style, OpenAI model, and hotkey.
5. Use the gear button in the R2Trans settings title bar to change the app language immediately.
6. Enable Launch at Login if you want R2Trans to start automatically.
7. Grant macOS Accessibility permission when prompted.

The default hotkey is:

```text
control+option+t
```

Hotkeys support `command`, `control`, `option`, `shift`, letters, numbers, punctuation, and `space`.

## Privacy and Security

- OpenAI API keys are entered by each user in the app settings.
- API keys are stored in the user's macOS Keychain via `KeychainStore`.
- API keys are not stored in this repository, build scripts, app bundle metadata, or UserDefaults.
- Text selected for translation and live interpreter audio are sent to OpenAI to perform the requested translation.
- The app requests macOS Accessibility permission only to copy selected text and paste translated text.
- The app requests Microphone and Screen & System Audio Recording permissions only for Live Interpreter audio capture.
- Local build artifacts, DMGs, app bundles, local IDE settings, environment files, certificates, provisioning profiles, logs, and local assistant settings are ignored by `.gitignore`.
- Do not commit local absolute paths, personal names, API keys, certificates, provisioning profiles, or generated app bundles.

Before publishing a fork or release, run:

```sh
rg -n "$(id -un)|OPENAI_API_KEY|sk-[A-Za-z0-9_-]+|BEGIN .*PRIVATE KEY|R2TRANS_CODESIGN_IDENTITY" .
git status --short --ignored
```

## License

R2Trans is released under the MIT License. See [LICENSE](LICENSE).
