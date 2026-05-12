# R2Trans

선택한 문장을 단축키 한 번으로 번역해 주는 macOS 메뉴바 앱입니다.

메일, 메모, 브라우저, 문서 편집기처럼 평소에 쓰던 앱에서 텍스트를 선택하고 단축키를 누르면, R2Trans가 선택한 문장을 번역한 뒤 그 자리에 자연스럽게 바꿔 넣어 줍니다.

버그 제보, 기능 추가 문의는 언제나 환영입니다.

[English README](README_en.md)

## 이런 일을 할 수 있어요

- 선택한 텍스트를 전역 단축키로 바로 번역합니다.
- `한국어 -> 영어`, `영어 -> 한국어`, `일본어 -> 한국어`, `스페인어 -> 영어` 같은 번역 방향을 고를 수 있습니다.
- `한국어 <-> 영어`, `한국어 <-> 일본어`는 자동 언어 감지를 사용할 수 있습니다.
- 번역 스타일을 Natural, Formal, Polite, Overly Deferential, Nyang style(냥냥체, 한국어 한정) 중에서 고를 수 있습니다.
- 번역 결과를 바로 바꾸기 전에 확인 창을 띄울 수 있습니다.
- Live Interpreter로 마이크 오디오, 시스템 오디오, 또는 둘 다를 실시간 번역할 수 있습니다.
- 메뉴바에서 번역 방향, 자동 감지, 확인 후 교체, 번역 스타일, Live Interpreter, 로그인 시 실행을 빠르게 바꿀 수 있습니다.

## 작동 방식

R2Trans는 사용자가 선택한 텍스트를 복사하고, OpenAI Responses API로 번역을 요청한 뒤, 번역된 텍스트를 다시 붙여넣습니다. 작업이 끝나면 이전 클립보드를 되돌리도록 설계되어 있습니다.

앱에는 OpenAI API 키가 포함되어 있지 않습니다. 사용자가 직접 앱 설정에 API 키를 입력해야 하며, 입력한 키는 macOS Keychain에 저장됩니다.

## 지원 언어

현재 앱에 포함된 언어 코드는 다음과 같습니다.

```text
en-US English
ko-KR Korean
es-ES Spanish
ja-JP Japanese
zh-CN Chinese
```

## 설치해서 사용하기

먼저 앱을 빌드합니다.

```sh
Scripts/build_app.sh
```

빌드가 끝나면 앱이 아래 위치에 생성됩니다.

```text
build/R2Trans.app
```

앱을 설치할거라면 `/Applications`에 설치하는 것을 권장합니다.

```sh
Scripts/install_app.sh
```

설치 위치는 다음과 같습니다.

```text
/Applications/R2Trans.app
```

그다음 `/Applications/R2Trans.app`을 실행하고, 안내에 따라 macOS 접근성 권한을 허용해 주세요.

## 처음 설정하기

1. `/Applications/R2Trans.app`을 실행합니다.
2. `R2Trans Settings`를 엽니다.
3. 본인의 OpenAI API 키를 입력합니다.
4. 번역 방향, 자동 감지, 번역 스타일, OpenAI 모델, 단축키를 고릅니다.
5. 설정 창 상단의 기어 버튼에서 앱 표시 언어를 바로 바꿀 수 있습니다.
6. 필요하면 `Launch at Login`을 켜서 로그인할 때 자동 실행되게 합니다.
7. macOS가 접근성 권한을 요청하면 허용합니다.

기본 단축키는 다음과 같습니다.

```text
control+option+t
```

단축키에는 `command`, `control`, `option`, `shift`, 문자, 숫자, 구두점, `space`를 사용할 수 있습니다.

## 권한 안내

R2Trans가 요청하는 권한은 기능을 실행하는 데 필요한 범위로 제한됩니다.

- 접근성 권한: 선택한 텍스트를 복사하고 번역 결과를 붙여넣기 위해 필요합니다.
- 마이크 권한: Live Interpreter에서 마이크 오디오를 번역할 때 필요합니다.
- 화면 및 시스템 오디오 녹음 권한: Live Interpreter에서 시스템 오디오를 번역할 때 필요합니다.

접근성 권한을 이미 허용했는데도 다시 요청된다면, 시스템 설정에서 기존 R2Trans 항목을 삭제한 뒤 `/Applications/R2Trans.app`을 다시 추가하고 앱을 재실행해 주세요.

## DMG 만들기

배포용 DMG가 필요하면 아래 명령을 실행합니다.

```sh
Scripts/create_dmg.sh
```

생성 위치는 다음과 같습니다.

```text
build/R2Trans.dmg
```

## 개인정보와 보안

- OpenAI API 키는 사용자가 직접 입력합니다.
- API 키는 `KeychainStore`를 통해 macOS Keychain에 저장됩니다.
- API 키는 이 저장소, 빌드 스크립트, 앱 번들 메타데이터, UserDefaults에 저장하지 않습니다.
- 번역할 텍스트와 Live Interpreter 오디오는 요청한 번역을 수행하기 위해 OpenAI로 전송됩니다.
- 로컬 빌드 결과물, DMG, 앱 번들, IDE 설정, 환경 파일, 인증서, provisioning profile, 로그, 로컬 assistant 설정은 `.gitignore`로 제외됩니다.
- 로컬 절대 경로, 개인 이름, API 키, 인증서, provisioning profile, 생성된 앱 번들은 커밋하지 않는 것을 권장합니다.

공개 배포나 fork를 만들기 전에는 한 번 더 확인해 주세요.

```sh
rg -n "$(id -un)|OPENAI_API_KEY|sk-[A-Za-z0-9_-]+|BEGIN .*PRIVATE KEY|R2TRANS_CODESIGN_IDENTITY" .
git status --short --ignored
```

## 코드 서명

개발 빌드는 기본적으로 ad-hoc signing을 사용합니다. 앱을 다시 빌드하면 macOS가 접근성 신뢰에 사용하는 코드 서명이 바뀔 수 있습니다.

안정적인 로컬 인증서로 서명하려면 다음처럼 실행합니다.

```sh
R2TRANS_CODESIGN_IDENTITY="Your Code Signing Certificate" Scripts/install_app.sh
```

## 라이선스

R2Trans는 MIT License로 배포됩니다. 자세한 내용은 [LICENSE](LICENSE)를 확인해 주세요.
