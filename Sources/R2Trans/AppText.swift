import Foundation

enum AppText {
    static var language: AppLanguage {
        AppSettings.shared.appLanguage
    }

    static func text(_ key: Key) -> String {
        switch language {
        case .english:
            return english[key]!
        case .korean:
            return korean[key]!
        case .japanese:
            return japanese[key]!
        case .chinese:
            return chinese[key]!
        }
    }

    enum Key {
        case quitR2Trans
        case edit
        case cut
        case copy
        case paste
        case selectAll
        case translateSelection
        case translationMode
        case settings
        case requestAccessibilityPermission
        case hotkeyError
        case accessibilityPermission
        case settingsTitle
        case openAIAPIKey
        case appLanguage
        case hotkey
        case model
        case autoDetect
        case autoDetectPair
        case confirmBeforeReplace
        case translationStyle
        case launchAtLogin
        case showStatusBarIcon
        case inputSource
        case audioApplication
        case allSystemAudio
        case loadingAudioApplications
        case audioLevel
        case microphoneLevel
        case systemAudioLevel
        case keepInterpreterOnTop
        case sourceTranscript
        case translatedSubtitle
        case sourceLanguage
        case targetLanguage
        case createAPIKey
        case openAIAPIKeyHelp
        case menuSectionTranslate
        case menuSectionMode
        case menuSectionOptions
        case workMode
        case multilingualTranslationMode
        case sameLanguageRewriteMode
        case currentMode
        case confirmTranslationTitle
        case confirmTranslationMessage
        case replace
        case copyOnly
        case cancel
        case clear
        case ok
        case start
        case stop
        case styleNatural
        case styleFormal
        case stylePolite
        case styleGroveling
        case styleNyang
        case networkError
        case openAIUnauthorized
        case openAIRateLimited
        case openAITemporaryFailure
        case save
        case close
        case updateAvailableTitle
        case updateAvailableMessage
        case downloadUpdate
        case later
        case settingsError
        case pressShortcut
        case pressModifierAndCharacter
        case shortcutConflictsWithMacOS
        case shortcutNeedsMoreModifiers
        case unsupportedKey
        case translating
        case accessibilityPermissionRequired
        case accessibilityPermissionAlreadyEnabledHelp
        case currentAppPath
        case apiKeyMissing
        case clipboardTextMissing
        case invalidHotkey
        case responseMissing
        case alreadyTranslating
        case microphonePermissionDenied
        case microphoneUnavailable
        case systemAudioUnavailable
        case microphoneInput
        case systemAudioInput
        case microphoneAndSystemAudioInput
        case liveInterpreter
        case liveInterpreterTitle
        case liveInterpreterConnecting
        case liveInterpreterListening
        case liveInterpreterStopped
        case liveInterpreterError
        case liveInterpreterNoSource
        case liveInterpreterWaitingSubtitle
        case liveInterpreterBillingNote
    }

    private static let english: [Key: String] = [
        .quitR2Trans: "Quit R2Trans",
        .edit: "Edit",
        .cut: "Cut",
        .copy: "Copy",
        .paste: "Paste",
        .selectAll: "Select All",
        .translateSelection: "Translate Selection",
        .translationMode: "Translation Mode",
        .settings: "Settings...",
        .requestAccessibilityPermission: "Request Accessibility Permission",
        .hotkeyError: "Hotkey Error",
        .accessibilityPermission: "Accessibility Permission",
        .settingsTitle: "R2Trans Settings",
        .openAIAPIKey: "OpenAI API Key",
        .appLanguage: "App Language",
        .hotkey: "Hotkey",
        .model: "Model",
        .autoDetect: "Auto Detect",
        .autoDetectPair: "Auto Pair",
        .confirmBeforeReplace: "Confirm Before Replace",
        .translationStyle: "Translation Style",
        .launchAtLogin: "Launch at Login",
        .showStatusBarIcon: "Show Status Bar Icon",
        .inputSource: "Input Source",
        .audioApplication: "Audio App",
        .allSystemAudio: "All system audio",
        .loadingAudioApplications: "Loading apps...",
        .audioLevel: "Audio Level",
        .microphoneLevel: "Mic",
        .systemAudioLevel: "System",
        .keepInterpreterOnTop: "Keep on Top",
        .sourceTranscript: "Original",
        .translatedSubtitle: "Translation",
        .sourceLanguage: "Source Language",
        .targetLanguage: "Target Language",
        .createAPIKey: "Create OpenAI API Key",
        .openAIAPIKeyHelp: "Create or manage an OpenAI API key",
        .menuSectionTranslate: "Translate",
        .menuSectionMode: "Mode",
        .menuSectionOptions: "Options",
        .workMode: "Work Mode",
        .multilingualTranslationMode: "Multilingual Translation",
        .sameLanguageRewriteMode: "Rewrite Same Language",
        .currentMode: "Current Mode",
        .confirmTranslationTitle: "Confirm Translation",
        .confirmTranslationMessage: "Review the translated text before replacing the selection.",
        .replace: "Replace",
        .copyOnly: "Copy",
        .cancel: "Cancel",
        .clear: "Clear",
        .ok: "OK",
        .start: "Start",
        .stop: "Stop",
        .styleNatural: "Natural",
        .styleFormal: "Formal",
        .stylePolite: "Polite",
        .styleGroveling: "Overly Deferential",
        .styleNyang: "Nyang style (ko-KR only)",
        .networkError: "Network connection failed. Check your internet connection and try again.",
        .openAIUnauthorized: "OpenAI rejected the API key. Check that the key is correct and active.",
        .openAIRateLimited: "OpenAI rate limit or quota was reached. Check billing, usage limits, or try again later.",
        .openAITemporaryFailure: "OpenAI is temporarily unavailable. Try again in a moment.",
        .save: "Save",
        .close: "Close",
        .updateAvailableTitle: "R2Trans Update Available",
        .updateAvailableMessage: "Version %@ is available. You are currently using %@.",
        .downloadUpdate: "Download",
        .later: "Later",
        .settingsError: "Settings Error",
        .pressShortcut: "Press shortcut",
        .pressModifierAndCharacter: "Press a modifier and character key",
        .shortcutConflictsWithMacOS: "This shortcut is commonly used by macOS or apps. Choose another shortcut.",
        .shortcutNeedsMoreModifiers: "Use at least two modifiers, such as Control+Option, for a global shortcut.",
        .unsupportedKey: "Unsupported key.",
        .translating: "Translating...",
        .accessibilityPermissionRequired: "Accessibility permission is required so R2Trans can copy and paste selected text in other apps.",
        .accessibilityPermissionAlreadyEnabledHelp: "If R2Trans is already enabled, remove the old R2Trans entry in System Settings, add the app at the path above, then relaunch R2Trans.",
        .currentAppPath: "Current app",
        .apiKeyMissing: "OpenAI API key is missing. Open Settings and enter your API key.",
        .clipboardTextMissing: "No selected text was found. Select text in another app, then press the R2Trans hotkey.",
        .invalidHotkey: "Invalid hotkey",
        .responseMissing: "The OpenAI response did not include translated text.",
        .alreadyTranslating: "A translation is already in progress.",
        .microphonePermissionDenied: "Microphone permission is required for live interpretation.",
        .microphoneUnavailable: "The microphone could not be started.",
        .systemAudioUnavailable: "System audio capture could not be started. Allow R2Trans in System Settings > Privacy & Security > Screen & System Audio Recording, then try again.",
        .microphoneInput: "Microphone only",
        .systemAudioInput: "System audio only",
        .microphoneAndSystemAudioInput: "Microphone + system audio",
        .liveInterpreter: "Live Interpreter...",
        .liveInterpreterTitle: "Live Interpreter",
        .liveInterpreterConnecting: "Connecting...",
        .liveInterpreterListening: "Listening",
        .liveInterpreterStopped: "Stopped",
        .liveInterpreterError: "Live Interpreter Error",
        .liveInterpreterNoSource: "Source transcript will appear here.",
        .liveInterpreterWaitingSubtitle: "Translation subtitles will appear here.",
        .liveInterpreterBillingNote: "Realtime translation is billed by audio duration. Free tier may not support gpt-realtime-translate."
    ]

    private static let korean: [Key: String] = [
        .quitR2Trans: "R2Trans 종료",
        .edit: "편집",
        .cut: "오려두기",
        .copy: "복사",
        .paste: "붙여넣기",
        .selectAll: "전체 선택",
        .translateSelection: "선택 영역 번역",
        .translationMode: "번역 모드",
        .settings: "설정...",
        .requestAccessibilityPermission: "손쉬운 사용 권한 요청",
        .hotkeyError: "단축키 오류",
        .accessibilityPermission: "손쉬운 사용 권한",
        .settingsTitle: "R2Trans 설정",
        .openAIAPIKey: "OpenAI API 키",
        .appLanguage: "앱 언어",
        .hotkey: "단축키",
        .model: "모델",
        .autoDetect: "자동 감지",
        .autoDetectPair: "자동 감지 쌍",
        .confirmBeforeReplace: "바꾸기 전 확인",
        .translationStyle: "번역 스타일",
        .launchAtLogin: "로그인 시 실행",
        .showStatusBarIcon: "상태바 표시하기",
        .inputSource: "입력 소스",
        .audioApplication: "오디오 앱",
        .allSystemAudio: "전체 시스템 오디오",
        .loadingAudioApplications: "앱 불러오는 중...",
        .audioLevel: "오디오 레벨",
        .microphoneLevel: "마이크",
        .systemAudioLevel: "시스템",
        .keepInterpreterOnTop: "항상 위",
        .sourceTranscript: "원문 받아쓰기",
        .translatedSubtitle: "번역",
        .sourceLanguage: "원문 언어",
        .targetLanguage: "타겟 언어",
        .createAPIKey: "OpenAI API 키 생성",
        .openAIAPIKeyHelp: "OpenAI API 키 생성 또는 관리",
        .menuSectionTranslate: "번역",
        .menuSectionMode: "모드",
        .menuSectionOptions: "옵션",
        .workMode: "작업 모드",
        .multilingualTranslationMode: "다국어 번역",
        .sameLanguageRewriteMode: "원문 다듬기",
        .currentMode: "현재 모드",
        .confirmTranslationTitle: "번역 확인",
        .confirmTranslationMessage: "선택 영역을 바꾸기 전에 번역 결과를 확인하세요.",
        .replace: "바꾸기",
        .copyOnly: "복사",
        .cancel: "취소",
        .clear: "지우기",
        .ok: "확인",
        .start: "시작",
        .stop: "중지",
        .styleNatural: "자연스럽게",
        .styleFormal: "격식 있게",
        .stylePolite: "공손하게",
        .styleGroveling: "비굴하게",
        .styleNyang: "냥냥체(ko-KR 한정)",
        .networkError: "네트워크 연결에 실패했습니다. 인터넷 연결을 확인한 뒤 다시 시도해주세요.",
        .openAIUnauthorized: "OpenAI가 API 키를 거부했습니다. 키가 정확하고 활성 상태인지 확인해주세요.",
        .openAIRateLimited: "OpenAI 사용량 한도 또는 결제 한도에 도달했습니다. 결제/사용량 제한을 확인하거나 잠시 후 다시 시도해주세요.",
        .openAITemporaryFailure: "OpenAI 서비스가 일시적으로 응답하지 않습니다. 잠시 후 다시 시도해주세요.",
        .save: "저장",
        .close: "닫기",
        .updateAvailableTitle: "R2Trans 업데이트가 있습니다",
        .updateAvailableMessage: "%@ 버전을 사용할 수 있습니다. 현재 버전은 %@입니다.",
        .downloadUpdate: "다운로드",
        .later: "나중에",
        .settingsError: "설정 오류",
        .pressShortcut: "단축키를 입력하세요",
        .pressModifierAndCharacter: "보조키와 문자 키를 함께 눌러주세요",
        .shortcutConflictsWithMacOS: "이 단축키는 macOS 또는 다른 앱에서 자주 사용됩니다. 다른 단축키를 선택해주세요.",
        .shortcutNeedsMoreModifiers: "전역 단축키는 Control+Option처럼 보조키를 2개 이상 함께 사용해주세요.",
        .unsupportedKey: "지원하지 않는 키입니다.",
        .translating: "번역 진행중",
        .accessibilityPermissionRequired: "다른 앱에서 선택한 텍스트를 복사하고 붙여넣으려면 macOS 손쉬운 사용 권한이 필요합니다.",
        .accessibilityPermissionAlreadyEnabledHelp: "R2Trans가 이미 켜져 있다면 시스템 설정에서 예전 R2Trans 항목을 삭제하고, 위 경로의 앱을 다시 추가한 뒤 R2Trans를 재실행해주세요.",
        .currentAppPath: "현재 앱",
        .apiKeyMissing: "OpenAI API 키가 없습니다. 설정을 열고 API 키를 입력해주세요.",
        .clipboardTextMissing: "선택된 텍스트를 찾지 못했습니다. 다른 앱에서 텍스트를 선택한 뒤 R2Trans 단축키를 눌러주세요.",
        .invalidHotkey: "단축키 형식이 올바르지 않습니다",
        .responseMissing: "OpenAI 응답에서 번역된 텍스트를 찾지 못했습니다.",
        .alreadyTranslating: "이미 번역이 진행 중입니다.",
        .microphonePermissionDenied: "실시간 통역에는 마이크 권한이 필요합니다.",
        .microphoneUnavailable: "마이크를 시작하지 못했습니다.",
        .systemAudioUnavailable: "시스템 오디오 캡처를 시작하지 못했습니다. 시스템 설정 > 개인정보 보호 및 보안 > 화면 및 시스템 오디오 녹음에서 R2Trans를 허용한 뒤 다시 시도해주세요.",
        .microphoneInput: "마이크만",
        .systemAudioInput: "시스템 오디오만",
        .microphoneAndSystemAudioInput: "마이크 + 시스템 오디오",
        .liveInterpreter: "실시간 통역...",
        .liveInterpreterTitle: "실시간 통역",
        .liveInterpreterConnecting: "연결 중...",
        .liveInterpreterListening: "듣는 중",
        .liveInterpreterStopped: "중지됨",
        .liveInterpreterError: "실시간 통역 오류",
        .liveInterpreterNoSource: "원문 transcript가 여기에 표시됩니다.",
        .liveInterpreterWaitingSubtitle: "번역 자막이 여기에 표시됩니다.",
        .liveInterpreterBillingNote: "실시간 번역은 오디오 duration 기준으로 과금됩니다. Free tier에서는 gpt-realtime-translate가 지원되지 않을 수 있습니다."
    ]

    private static let japanese: [Key: String] = [
        .quitR2Trans: "R2Transを終了",
        .edit: "編集",
        .cut: "カット",
        .copy: "コピー",
        .paste: "ペースト",
        .selectAll: "すべて選択",
        .translateSelection: "選択範囲を翻訳",
        .translationMode: "翻訳モード",
        .settings: "設定...",
        .requestAccessibilityPermission: "アクセシビリティ権限を要求",
        .hotkeyError: "ホットキーエラー",
        .accessibilityPermission: "アクセシビリティ権限",
        .settingsTitle: "R2Trans 設定",
        .openAIAPIKey: "OpenAI APIキー",
        .appLanguage: "アプリの言語",
        .hotkey: "ホットキー",
        .model: "モデル",
        .autoDetect: "自動検出",
        .autoDetectPair: "自動ペア",
        .confirmBeforeReplace: "置換前に確認",
        .translationStyle: "翻訳スタイル",
        .launchAtLogin: "ログイン時に起動",
        .showStatusBarIcon: "ステータスバーに表示",
        .inputSource: "入力ソース",
        .audioApplication: "音声アプリ",
        .allSystemAudio: "すべてのシステム音声",
        .loadingAudioApplications: "アプリを読み込み中...",
        .audioLevel: "音声レベル",
        .microphoneLevel: "マイク",
        .systemAudioLevel: "システム",
        .keepInterpreterOnTop: "常に手前",
        .sourceTranscript: "原文文字起こし",
        .translatedSubtitle: "翻訳",
        .sourceLanguage: "元の言語",
        .targetLanguage: "翻訳先の言語",
        .createAPIKey: "OpenAI APIキーを作成",
        .openAIAPIKeyHelp: "OpenAI APIキーを作成または管理",
        .menuSectionTranslate: "翻訳",
        .menuSectionMode: "モード",
        .menuSectionOptions: "オプション",
        .workMode: "作業モード",
        .multilingualTranslationMode: "多言語翻訳",
        .sameLanguageRewriteMode: "同じ言語で書き直し",
        .currentMode: "現在のモード",
        .confirmTranslationTitle: "翻訳を確認",
        .confirmTranslationMessage: "選択範囲を置換する前に翻訳結果を確認してください。",
        .replace: "置換",
        .copyOnly: "コピー",
        .cancel: "キャンセル",
        .clear: "クリア",
        .ok: "OK",
        .start: "開始",
        .stop: "停止",
        .styleNatural: "自然",
        .styleFormal: "フォーマル",
        .stylePolite: "丁寧",
        .styleGroveling: "過度にへりくだる",
        .styleNyang: "にゃん風(ko-KRのみ)",
        .networkError: "ネットワーク接続に失敗しました。インターネット接続を確認して、もう一度お試しください。",
        .openAIUnauthorized: "OpenAIがAPIキーを拒否しました。キーが正しく有効か確認してください。",
        .openAIRateLimited: "OpenAIのレート制限または利用上限に達しました。請求設定や利用制限を確認するか、後でもう一度お試しください。",
        .openAITemporaryFailure: "OpenAIが一時的に利用できません。しばらくしてからもう一度お試しください。",
        .save: "保存",
        .close: "閉じる",
        .updateAvailableTitle: "R2Transのアップデートがあります",
        .updateAvailableMessage: "バージョン%@を利用できます。現在のバージョンは%@です。",
        .downloadUpdate: "ダウンロード",
        .later: "後で",
        .settingsError: "設定エラー",
        .pressShortcut: "ショートカットを押してください",
        .pressModifierAndCharacter: "修飾キーと文字キーを押してください",
        .shortcutConflictsWithMacOS: "このショートカットはmacOSまたは他のアプリでよく使用されます。別のショートカットを選んでください。",
        .shortcutNeedsMoreModifiers: "グローバルショートカットにはControl+Optionのように修飾キーを2つ以上使用してください。",
        .unsupportedKey: "対応していないキーです。",
        .translating: "翻訳中...",
        .accessibilityPermissionRequired: "他のアプリで選択したテキストをコピーして貼り付けるには、macOSのアクセシビリティ権限が必要です。",
        .accessibilityPermissionAlreadyEnabledHelp: "R2Transがすでに有効な場合は、システム設定で古いR2Trans項目を削除し、上記パスのアプリを追加してからR2Transを再起動してください。",
        .currentAppPath: "現在のアプリ",
        .apiKeyMissing: "OpenAI APIキーがありません。設定を開いてAPIキーを入力してください。",
        .clipboardTextMissing: "選択されたテキストが見つかりませんでした。他のアプリでテキストを選択してからR2Transのホットキーを押してください。",
        .invalidHotkey: "無効なホットキーです",
        .responseMissing: "OpenAIの応答に翻訳テキストが含まれていませんでした。",
        .alreadyTranslating: "翻訳はすでに実行中です。",
        .microphonePermissionDenied: "ライブ通訳にはマイクの権限が必要です。",
        .microphoneUnavailable: "マイクを開始できませんでした。",
        .systemAudioUnavailable: "システム音声キャプチャを開始できませんでした。システム設定 > プライバシーとセキュリティ > 画面とシステムオーディオ録音でR2Transを許可してから再試行してください。",
        .microphoneInput: "マイクのみ",
        .systemAudioInput: "システム音声のみ",
        .microphoneAndSystemAudioInput: "マイク + システム音声",
        .liveInterpreter: "ライブ通訳...",
        .liveInterpreterTitle: "ライブ通訳",
        .liveInterpreterConnecting: "接続中...",
        .liveInterpreterListening: "リスニング中",
        .liveInterpreterStopped: "停止中",
        .liveInterpreterError: "ライブ通訳エラー",
        .liveInterpreterNoSource: "原文の文字起こしがここに表示されます。",
        .liveInterpreterWaitingSubtitle: "翻訳字幕がここに表示されます。",
        .liveInterpreterBillingNote: "リアルタイム翻訳は音声時間に基づいて課金されます。Free tierではgpt-realtime-translateが利用できない場合があります。"
    ]

    private static let chinese: [Key: String] = [
        .quitR2Trans: "退出 R2Trans",
        .edit: "编辑",
        .cut: "剪切",
        .copy: "复制",
        .paste: "粘贴",
        .selectAll: "全选",
        .translateSelection: "翻译所选内容",
        .translationMode: "翻译模式",
        .settings: "设置...",
        .requestAccessibilityPermission: "请求辅助功能权限",
        .hotkeyError: "快捷键错误",
        .accessibilityPermission: "辅助功能权限",
        .settingsTitle: "R2Trans 设置",
        .openAIAPIKey: "OpenAI API 密钥",
        .appLanguage: "应用语言",
        .hotkey: "快捷键",
        .model: "模型",
        .autoDetect: "自动检测",
        .autoDetectPair: "自动语言对",
        .confirmBeforeReplace: "替换前确认",
        .translationStyle: "翻译风格",
        .launchAtLogin: "登录时启动",
        .showStatusBarIcon: "显示状态栏图标",
        .inputSource: "输入来源",
        .audioApplication: "音频应用",
        .allSystemAudio: "所有系统音频",
        .loadingAudioApplications: "正在加载应用...",
        .audioLevel: "音频电平",
        .microphoneLevel: "麦克风",
        .systemAudioLevel: "系统",
        .keepInterpreterOnTop: "置顶",
        .sourceTranscript: "原文转录",
        .translatedSubtitle: "翻译",
        .sourceLanguage: "源语言",
        .targetLanguage: "目标语言",
        .createAPIKey: "创建 OpenAI API 密钥",
        .openAIAPIKeyHelp: "创建或管理 OpenAI API 密钥",
        .menuSectionTranslate: "翻译",
        .menuSectionMode: "模式",
        .menuSectionOptions: "选项",
        .workMode: "工作模式",
        .multilingualTranslationMode: "多语言翻译",
        .sameLanguageRewriteMode: "同语言润色",
        .currentMode: "当前模式",
        .confirmTranslationTitle: "确认翻译",
        .confirmTranslationMessage: "替换所选内容前请检查翻译结果。",
        .replace: "替换",
        .copyOnly: "复制",
        .cancel: "取消",
        .clear: "清除",
        .ok: "确定",
        .start: "开始",
        .stop: "停止",
        .styleNatural: "自然",
        .styleFormal: "正式",
        .stylePolite: "礼貌",
        .styleGroveling: "过度谦卑",
        .styleNyang: "喵喵体(仅 ko-KR)",
        .networkError: "网络连接失败。请检查互联网连接后重试。",
        .openAIUnauthorized: "OpenAI 拒绝了 API 密钥。请检查密钥是否正确且处于启用状态。",
        .openAIRateLimited: "已达到 OpenAI 速率限制或配额。请检查账单、使用限制，或稍后重试。",
        .openAITemporaryFailure: "OpenAI 暂时不可用。请稍后重试。",
        .save: "保存",
        .close: "关闭",
        .updateAvailableTitle: "R2Trans 有可用更新",
        .updateAvailableMessage: "版本 %@ 可用。当前版本是 %@。",
        .downloadUpdate: "下载",
        .later: "稍后",
        .settingsError: "设置错误",
        .pressShortcut: "按下快捷键",
        .pressModifierAndCharacter: "请同时按下修饰键和字符键",
        .shortcutConflictsWithMacOS: "此快捷键常被 macOS 或其他应用使用。请选择其他快捷键。",
        .shortcutNeedsMoreModifiers: "全局快捷键请使用至少两个修饰键，例如 Control+Option。",
        .unsupportedKey: "不支持的按键。",
        .translating: "正在翻译...",
        .accessibilityPermissionRequired: "R2Trans 需要辅助功能权限，才能在其他应用中复制和粘贴所选文本。",
        .accessibilityPermissionAlreadyEnabledHelp: "如果 R2Trans 已启用，请在系统设置中移除旧的 R2Trans 项目，添加上方路径的应用，然后重新启动 R2Trans。",
        .currentAppPath: "当前应用",
        .apiKeyMissing: "缺少 OpenAI API 密钥。请打开设置并输入 API 密钥。",
        .clipboardTextMissing: "未找到所选文本。请在其他应用中选择文本，然后按下 R2Trans 快捷键。",
        .invalidHotkey: "无效的快捷键",
        .responseMissing: "OpenAI 响应中没有包含翻译文本。",
        .alreadyTranslating: "翻译已在进行中。",
        .microphonePermissionDenied: "实时口译需要麦克风权限。",
        .microphoneUnavailable: "无法启动麦克风。",
        .systemAudioUnavailable: "无法启动系统音频捕获。请在系统设置 > 隐私与安全性 > 屏幕与系统音频录制中允许 R2Trans，然后重试。",
        .microphoneInput: "仅麦克风",
        .systemAudioInput: "仅系统音频",
        .microphoneAndSystemAudioInput: "麦克风 + 系统音频",
        .liveInterpreter: "实时口译...",
        .liveInterpreterTitle: "实时口译",
        .liveInterpreterConnecting: "正在连接...",
        .liveInterpreterListening: "正在聆听",
        .liveInterpreterStopped: "已停止",
        .liveInterpreterError: "实时口译错误",
        .liveInterpreterNoSource: "源文本转录将显示在这里。",
        .liveInterpreterWaitingSubtitle: "翻译字幕将显示在这里。",
        .liveInterpreterBillingNote: "实时翻译按音频时长计费。Free tier 可能不支持 gpt-realtime-translate。"
    ]
}
