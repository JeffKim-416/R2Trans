# R2Trans

A friendly macOS menu bar app for translating selected text with one global hotkey.

Select text in the app you are already using, press the hotkey, and R2Trans replaces the selection with a translated version. It works nicely with email drafts, Notes, browsers, document editors, and most places where copy and paste work.

[한국어 README](README.md)

## Features

- Translates selected text with a global hotkey.
- Supports translation directions such as `Korean -> English`, `English -> Korean`, `Japanese -> Korean`, and `Spanish -> English`.
- Can auto-detect direction for `Korean <-> English` and `Korean <-> Japanese`.
- Lets you choose a translation style: Natural, Formal, Polite, Overly Deferential, or Nyang style for Korean output.
- Can show a confirmation window before replacing the selected text.
- Includes a Live Interpreter for translating microphone audio, system audio, or both.
- Includes Live Transcription for displaying the same audio as realtime source-language captions without translation.
- Provides quick menu bar controls for translation mode, auto detect, confirmation, style, Live Interpreter, Live Transcription, and Launch at Login.

## Installation

### Standard Install

1. Download the latest `R2Trans.dmg` from [GitHub Releases](https://github.com/JeffKim-416/R2Trans/releases/latest).
2. Open the downloaded DMG file.
3. Move `R2Trans.app` into the `Applications` folder.
4. Launch `R2Trans` from `Applications`.
5. Grant the macOS permissions requested by the app.

New GitHub Releases are configured to publish only after Developer ID signing and notarization checks pass. If Gatekeeper reports that the app is damaged or cannot verify its developer, do not bypass the warning; download it again from the official Release and report the problem.

### Install from Source ZIP

If you downloaded the source code as a ZIP from GitHub, double-click `Install.command` in the top-level folder to build the app, install it to `/Applications/R2Trans.app`, and launch it.

1. Download the source code with `Code > Download ZIP` on GitHub.
2. Unzip the download.
3. Double-click `Install.command` in the unzipped folder.
4. Wait for the Terminal window to finish the install.
5. Grant the macOS permissions requested by the app.

This method builds the app locally, so it requires Xcode Command Line Tools or a Swift toolchain. The result is ad-hoc signed for local use and is not a notarized distribution artifact, so most users should install the DMG from GitHub Releases.

## First-Time Setup

1. Click the R2Trans icon in the menu bar.
2. Open `R2Trans Settings`.
3. Enter your own OpenAI API key.
4. Choose the translation direction, auto-detect behavior, translation style, OpenAI model, and hotkey.
5. Use the gear button in the settings title bar to change the app language.
6. Enable `Launch at Login` if you want R2Trans to start automatically.

R2Trans does not include an OpenAI API key. To use the app, each user needs to enter their own key.

The default hotkey is:

```text
control+option+t
```

## How to Use

1. Select the text you want to translate.
2. Press the hotkey.
3. R2Trans translates the selected text.
4. If confirmation is enabled, review the translation before replacing the text.
5. If confirmation is disabled, the selected text is replaced immediately.

R2Trans briefly shows a `Translating...` window while the translation is running, then closes it automatically when finished.

## Live Interpreter

Live Interpreter translates speech into the selected target language in real time.

- It can translate microphone audio.
- It can translate system audio.
- It can use microphone and system audio together.

Microphone translation requires microphone permission. System audio translation requires Screen & System Audio Recording permission.

In addition to the realtime audio translation request, Live Interpreter may send part of the accumulated source transcript to the Responses API to produce fast provisional subtitles. Audio usage and text-token usage can therefore be charged separately.

## Live Transcription

Live Transcription displays speech as realtime captions in its original language, without translating it. Open `Live Transcription...` from the menu to use it.

- Uses `gpt-live-transcribe` to update partial captions as speech arrives.
- Supports microphone audio, all system audio, one application's audio, or microphone and system audio together.
- Lets you leave the spoken language on automatic or provide one supported language as a hint.
- Live transcription is billed separately by audio duration and is not supported on the Free tier.

## Supported Languages

R2Trans currently includes these language codes:

```text
en-US English
ko-KR Korean
es-ES Spanish
ja-JP Japanese
zh-CN Chinese
```

## Permissions

R2Trans only asks for permissions needed by its features.

- Accessibility: required to copy selected text and paste translated text.
- Microphone: required for microphone audio in Live Interpreter or Live Transcription.
- Screen & System Audio Recording: required for system audio in Live Interpreter or Live Transcription.

If Accessibility permission is already enabled but R2Trans still asks again, remove the old R2Trans entry from System Settings, add `/Applications/R2Trans.app` again, then relaunch R2Trans.

## Privacy

- OpenAI API keys are entered by each user.
- API keys are stored in the macOS Keychain.
- Text selected for translation, Live Interpreter audio and accumulated transcript text used for provisional subtitles, and Live Transcription audio are sent to OpenAI to perform the requested feature.
- Text translation requests use `store: false` so Responses API results are not stored.
- On launch, R2Trans checks GitHub Releases to see whether a newer version is available.
- R2Trans is designed to copy selected text, paste the translated result, and then restore the previous clipboard.

## License

R2Trans is released under the MIT License. See [LICENSE](LICENSE).
