import Foundation
import Testing
@testable import VoiceInputCore

@Test func conservativeRefinementPromptRejectsRewriting() {
    let prompt = LLMRefinementPrompt.systemPrompt
    #expect(prompt.contains("only fix obvious speech recognition errors"))
    #expect(prompt.contains("Never rewrite"))
    #expect(prompt.contains("return it as-is"))
}

@Test func cjkInputSourceDetectionRecognizesCommonIds() {
    #expect(InputSourcePolicy.isCJKInputSource(identifier: "com.apple.inputmethod.SCIM.ITABC"))
    #expect(InputSourcePolicy.isCJKInputSource(identifier: "com.apple.inputmethod.TCIM.Zhuyin"))
    #expect(InputSourcePolicy.isCJKInputSource(identifier: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"))
    #expect(!InputSourcePolicy.isCJKInputSource(identifier: "com.apple.keylayout.ABC"))
    #expect(!InputSourcePolicy.isCJKInputSource(identifier: "com.apple.keylayout.US"))
}

@Test func recognitionEngineOptionsIncludeAutoAppleMLXAndExternalLLM() {
    #expect(RecognitionEngine.allCases == [.auto, .appleSpeech, .mlxWhisper, .externalAPI])
    #expect(RecognitionEngine.auto.displayName == "Auto")
    #expect(RecognitionEngine.appleSpeech.displayName == "Apple Speech")
    #expect(RecognitionEngine.mlxWhisper.displayName == "Local mlx-whisper")
    #expect(RecognitionEngine.externalAPI.displayName == "External LLM")
}

@Test func defaultRecognitionEngineUsesAppleSpeechNotAuto() {
    let settings = AppSettings.defaultSettings
    #expect(settings.recognitionEngine == .appleSpeech)
    #expect(settings.language == .simplifiedChinese)
}

@Test func autoEngineFallsBackFromMacOSToMLXThenExternalLLM() {
    var settings = AppSettings.defaultSettings
    settings.recognitionEngine = .auto
    #expect(settings.effectiveRecognitionBackends == [.appleSpeech, .mlxWhisper, .externalAPI])
}

@Test func explicitAppleEngineUsesOnlyAppleSpeech() {
    var settings = AppSettings.defaultSettings
    settings.recognitionEngine = .appleSpeech
    #expect(settings.effectiveRecognitionBackends == [.appleSpeech])
}

@Test func explicitMLXEngineUsesOnlyMLXWhisper() {
    var settings = AppSettings.defaultSettings
    settings.recognitionEngine = .mlxWhisper
    #expect(settings.effectiveRecognitionBackends == [.mlxWhisper])
}

@Test func explicitExternalEngineUsesOnlyExternalLLM() {
    var settings = AppSettings.defaultSettings
    settings.recognitionEngine = .externalAPI
    #expect(settings.effectiveRecognitionBackends == [.externalAPI])
}

@Test func settingsNoLongerHaveLocalOnlyMode() {
    let encoded = try! JSONEncoder().encode(AppSettings.defaultSettings)
    let json = String(data: encoded, encoding: .utf8)!
    #expect(!json.contains("localOnlyMode"))
}

@Test func hotkeySettingsDefaultToFunctionKey() {
    let hotkey = HotkeySettings.defaultSettings
    #expect(hotkey.trigger == .functionKey)
    #expect(hotkey.displayName == "Fn")
}

@Test func hotkeySettingsSupportCommonShortcutChoices() {
    #expect(HotkeyTrigger.allCases.map(\.displayName) == ["Fn", "Right Option", "Control + Space", "Command + Shift + Space"])
}

@Test func llmConfigRequiresBaseKeyAndModel() {
    var config = LLMConfiguration(apiBaseURL: "https://api.example.com/v1", apiKey: "", model: "gpt-test")
    #expect(!config.isComplete)
    config.apiKey = "sk-test"
    #expect(config.isComplete)
}

@Test func textInjectorAppendsTrailingSpaceToRecognizedText() {
    #expect(TextInjector.textForInsertion("你好") == "你好 ")
    #expect(TextInjector.textForInsertion("hello ") == "hello ")
}
