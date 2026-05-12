# R2Trans

선택한 문장을 단축키 한 번으로 번역해 주는 macOS 메뉴바 앱입니다.

메일, 메모, 브라우저, 문서 편집기처럼 평소에 쓰던 앱에서 텍스트를 선택하고 단축키를 누르면, R2Trans가 번역한 문장으로 바로 바꿔 줍니다.

[English README](README_en.md)

## 주요 기능

- 선택한 텍스트를 전역 단축키로 바로 번역합니다.
- `한국어 -> 영어`, `영어 -> 한국어`, `일본어 -> 한국어`, `스페인어 -> 영어` 같은 번역 방향을 고를 수 있습니다.
- `한국어 <-> 영어`, `한국어 <-> 일본어`는 자동 언어 감지를 사용할 수 있습니다.
- 번역 스타일을 Natural, Formal, Polite, Overly Deferential, Nyang style(냥냥체, 한국어 한정) 중에서 고를 수 있습니다.
- 번역 결과를 바로 바꾸기 전에 확인 창을 띄울 수 있습니다.
- Live Interpreter로 마이크 오디오, 시스템 오디오, 또는 둘 다를 실시간 번역할 수 있습니다.
- 메뉴바에서 번역 방향, 자동 감지, 확인 후 교체, 번역 스타일, Live Interpreter, 로그인 시 실행을 빠르게 바꿀 수 있습니다.

## 설치 방법

### 일반 설치

1. [GitHub Releases](https://github.com/JeffKim-416/R2Trans/releases/latest)에서 최신 `R2Trans.dmg` 파일을 다운로드합니다.
2. 다운로드한 DMG 파일을 엽니다.
3. `R2Trans.app`을 `Applications` 폴더로 옮깁니다.
4. `Applications` 폴더에서 `R2Trans`를 실행합니다.
5. macOS가 권한을 요청하면 안내에 따라 허용합니다.

macOS에서 "확인되지 않은 개발자" 경고가 보이면 `System Settings > Privacy & Security`에서 R2Trans 실행을 허용한 뒤 다시 열어 주세요.

### 소스 ZIP에서 설치

GitHub에서 소스 코드를 ZIP으로 받은 경우, 최상위 폴더의 `Install.command`를 더블클릭하면 앱을 빌드해서 `/Applications/R2Trans.app`에 설치하고 실행합니다.

1. GitHub의 `Code > Download ZIP`으로 소스 코드를 다운로드합니다.
2. 압축을 풉니다.
3. 압축을 푼 폴더 안의 `Install.command`를 더블클릭합니다.
4. 터미널이 열리면 설치가 끝날 때까지 기다립니다.
5. macOS가 권한을 요청하면 안내에 따라 허용합니다.

이 방법은 로컬에서 앱을 빌드하므로 Xcode Command Line Tools 또는 Swift toolchain이 필요합니다. 일반 사용자는 GitHub Releases의 DMG 설치를 권장합니다.

## 처음 설정하기

1. 메뉴바에서 R2Trans 아이콘을 클릭합니다.
2. `R2Trans Settings`를 엽니다.
3. 본인의 OpenAI API 키를 입력합니다.
4. 번역 방향, 자동 감지, 번역 스타일, OpenAI 모델, 단축키를 고릅니다.
5. 설정 창 상단의 기어 버튼에서 앱 표시 언어를 바꿀 수 있습니다.
6. 필요하면 `Launch at Login`을 켜서 로그인할 때 자동 실행되게 합니다.

앱에는 OpenAI API 키가 포함되어 있지 않습니다. R2Trans를 사용하려면 사용자가 직접 OpenAI API 키를 입력해야 합니다.

기본 단축키는 다음과 같습니다.

```text
control+option+t
```

## 사용 방법

1. 번역하고 싶은 문장을 선택합니다.
2. 단축키를 누릅니다.
3. R2Trans가 선택한 문장을 번역합니다.
4. 확인 옵션을 켜둔 경우, 번역 결과를 확인한 뒤 바꿉니다.
5. 확인 옵션을 꺼둔 경우, 선택한 문장이 바로 번역문으로 교체됩니다.

R2Trans는 번역 중에 `Translating...` 창을 잠깐 보여주고, 작업이 끝나면 자동으로 닫습니다.

## Live Interpreter

Live Interpreter는 음성을 선택한 언어로 실시간 번역하는 기능입니다.

- 마이크 오디오를 번역할 수 있습니다.
- 시스템 오디오를 번역할 수 있습니다.
- 마이크와 시스템 오디오를 함께 사용할 수 있습니다.

마이크 번역에는 마이크 권한이 필요하고, 시스템 오디오 번역에는 화면 및 시스템 오디오 녹음 권한이 필요합니다.

## 지원 언어

현재 앱에 포함된 언어 코드는 다음과 같습니다.

```text
en-US English
ko-KR Korean
es-ES Spanish
ja-JP Japanese
zh-CN Chinese
```

## 권한 안내

R2Trans가 요청하는 권한은 기능을 실행하는 데 필요한 범위로 제한됩니다.

- 접근성 권한: 선택한 텍스트를 복사하고 번역 결과를 붙여넣기 위해 필요합니다.
- 마이크 권한: Live Interpreter에서 마이크 오디오를 번역할 때 필요합니다.
- 화면 및 시스템 오디오 녹음 권한: Live Interpreter에서 시스템 오디오를 번역할 때 필요합니다.

접근성 권한을 이미 허용했는데도 다시 요청된다면, 시스템 설정에서 기존 R2Trans 항목을 삭제한 뒤 `/Applications/R2Trans.app`을 다시 추가하고 앱을 재실행해 주세요.

## 개인정보 안내

- OpenAI API 키는 사용자가 직접 입력합니다.
- API 키는 macOS Keychain에 저장됩니다.
- 번역할 텍스트와 Live Interpreter 오디오는 요청한 번역을 수행하기 위해 OpenAI로 전송됩니다.
- R2Trans는 선택한 텍스트를 복사하고 번역 결과를 붙여넣은 뒤, 이전 클립보드를 되돌리도록 설계되어 있습니다.

## 라이선스

R2Trans는 MIT License로 배포됩니다. 자세한 내용은 [LICENSE](LICENSE)를 확인해 주세요.
