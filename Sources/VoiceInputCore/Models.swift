import Foundation

public enum RecognitionBackend: String, Codable, CaseIterable, Sendable {
    case appleSpeech
    case mlxWhisper
    case externalAPI
}

public enum RecognitionEngine: String, Codable, CaseIterable, Sendable {
    case auto
    case appleSpeech
    case mlxWhisper
    case externalAPI

    public var displayName: String {
        switch self {
        case .auto: "Auto"
        case .appleSpeech: "Apple Speech"
        case .mlxWhisper: "Local mlx-whisper"
        case .externalAPI: "External LLM"
        }
    }

    public var orderedBackends: [RecognitionBackend] {
        switch self {
        case .auto: [.appleSpeech, .mlxWhisper, .externalAPI]
        case .appleSpeech: [.appleSpeech]
        case .mlxWhisper: [.mlxWhisper]
        case .externalAPI: [.externalAPI]
        }
    }
}

public enum RecognitionLanguage: String, Codable, CaseIterable, Sendable {
    case english = "en-US"
    case simplifiedChinese = "zh-CN"
    case traditionalChinese = "zh-TW"
    case japanese = "ja-JP"
    case korean = "ko-KR"

    public var displayName: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .japanese: "日本語"
        case .korean: "한국어"
        }
    }
}

public enum HotkeyTrigger: String, Codable, CaseIterable, Sendable {
    case functionKey
    case rightOption
    case controlSpace
    case commandShiftSpace

    public var displayName: String {
        switch self {
        case .functionKey: "Fn"
        case .rightOption: "Right Option"
        case .controlSpace: "Control + Space"
        case .commandShiftSpace: "Command + Shift + Space"
        }
    }
}

public struct HotkeySettings: Codable, Equatable, Sendable {
    public var trigger: HotkeyTrigger

    public static let defaultSettings = HotkeySettings(trigger: .functionKey)

    public init(trigger: HotkeyTrigger) {
        self.trigger = trigger
    }

    public var displayName: String { trigger.displayName }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var language: RecognitionLanguage
    public var recognitionEngine: RecognitionEngine
    public var llmTimeoutSeconds: Double
    public var hotkeySettings: HotkeySettings

    public static let defaultSettings = AppSettings(
        language: .simplifiedChinese,
        recognitionEngine: .appleSpeech,
        llmTimeoutSeconds: 2.5,
        hotkeySettings: .defaultSettings
    )

    public init(
        language: RecognitionLanguage,
        recognitionEngine: RecognitionEngine,
        llmTimeoutSeconds: Double,
        hotkeySettings: HotkeySettings
    ) {
        self.language = language
        self.recognitionEngine = recognitionEngine
        self.llmTimeoutSeconds = llmTimeoutSeconds
        self.hotkeySettings = hotkeySettings
    }

    enum CodingKeys: String, CodingKey {
        case language
        case recognitionEngine
        case recognitionBackends
        case llmRefinementEnabled
        case localOnlyMode
        case llmTimeoutSeconds
        case fallbackHotkeyEnabled
        case hotkeySettings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        language = try container.decodeIfPresent(RecognitionLanguage.self, forKey: .language) ?? .simplifiedChinese
        if let engine = try container.decodeIfPresent(RecognitionEngine.self, forKey: .recognitionEngine) {
            recognitionEngine = engine
        } else if let backends = try container.decodeIfPresent([RecognitionBackend].self, forKey: .recognitionBackends) {
            recognitionEngine = Self.engineForLegacyBackends(backends)
        } else {
            recognitionEngine = .appleSpeech
        }
        llmTimeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .llmTimeoutSeconds) ?? 2.5
        hotkeySettings = try container.decodeIfPresent(HotkeySettings.self, forKey: .hotkeySettings) ?? .defaultSettings
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(language, forKey: .language)
        try container.encode(recognitionEngine, forKey: .recognitionEngine)
        try container.encode(llmTimeoutSeconds, forKey: .llmTimeoutSeconds)
        try container.encode(hotkeySettings, forKey: .hotkeySettings)
    }

    private static func engineForLegacyBackends(_ backends: [RecognitionBackend]) -> RecognitionEngine {
        switch backends {
        case [.appleSpeech, .mlxWhisper, .externalAPI]: .auto
        case [.appleSpeech]: .appleSpeech
        case [.mlxWhisper]: .mlxWhisper
        case [.externalAPI]: .externalAPI
        default: .auto
        }
    }

    public var effectiveRecognitionBackends: [RecognitionBackend] {
        recognitionEngine.orderedBackends
    }
}

public struct LLMConfiguration: Codable, Equatable, Sendable {
    public var apiBaseURL: String
    public var apiKey: String
    public var model: String

    public init(apiBaseURL: String = "", apiKey: String = "", model: String = "") {
        self.apiBaseURL = apiBaseURL
        self.apiKey = apiKey
        self.model = model
    }

    public var isComplete: Bool {
        !apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum LLMRefinementPrompt {
    public static let systemPrompt = """
    You are a conservative speech-recognition correction engine.
    Your job is to only fix obvious speech recognition errors, such as Chinese homophone mistakes and English technical terms mistakenly converted to Chinese phonetics (for example: 配森 -> Python, 杰森 -> JSON, 杰森文件 -> JSON file).
    Never rewrite, polish, summarize, expand, shorten, remove content, add content, change tone, or change wording that appears correct.
    Preserve the user's language mix, punctuation style, code terms, names, and intent.
    If the input looks correct, return it as-is.
    Return only the corrected text, with no explanation.
    """
}

public enum InputSourcePolicy {
    public static func isCJKInputSource(identifier: String) -> Bool {
        let lower = identifier.lowercased()
        let markers = [
            "scim", "tcim", "kotoeri", "japanese", "korean", "hangul", "pinyin", "shuangpin", "wubi", "zhuyin", "cangjie", "cjk"
        ]
        if lower.contains("keylayout.abc") || lower.contains("keylayout.us") {
            return false
        }
        return markers.contains { lower.contains($0) }
    }
}
