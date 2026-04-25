import AppKit
import Foundation
import Speech

public final class LLMRefiner {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func refine(text: String, config: LLMConfiguration, timeout: Double, completion: @escaping (String) -> Void) {
        guard config.isComplete, let url = URL(string: config.apiBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions") else {
            completion(text)
            return
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": config.model,
            "temperature": 0,
            "messages": [
                ["role": "system", "content": LLMRefinementPrompt.systemPrompt],
                ["role": "user", "content": text]
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let task = session.dataTask(with: request) { data, _, error in
            guard error == nil, let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                Logger.log("LLM refinement failed or timed out: \(String(describing: error))")
                DispatchQueue.main.async { completion(text) }
                return
            }
            let refined = content.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async { completion(refined.isEmpty ? text : refined) }
        }
        task.resume()
    }

    public func test(config: LLMConfiguration, completion: @escaping (Bool, String) -> Void) {
        refine(text: "我在写配森和杰森文件", config: config, timeout: 8) { result in
            completion(result.contains("Python") || result.contains("JSON"), result)
        }
    }
}

public final class RecognitionCoordinator {
    private let appleSpeech: AppleSpeechRecognizerManager
    private let audioRecorder: AudioFileRecorder
    private let mlxWhisper: MLXWhisperTranscriber
    private let external: ExternalSpeechAPITranscriber
    private let llm: LLMRefiner
    private let injector: TextInjector
    private let panel: FloatingTranscriptionPanel
    private var activeBackends: [RecognitionBackend] = []
    private var injectionTargetApplication: NSRunningApplication?
    private var settings: AppSettings { SettingsStore.shared.settings }

    public init(
        appleSpeech: AppleSpeechRecognizerManager = AppleSpeechRecognizerManager(),
        audioRecorder: AudioFileRecorder = AudioFileRecorder(),
        mlxWhisper: MLXWhisperTranscriber = MLXWhisperTranscriber(),
        external: ExternalSpeechAPITranscriber = ExternalSpeechAPITranscriber(),
        llm: LLMRefiner = LLMRefiner(),
        injector: TextInjector = TextInjector(),
        panel: FloatingTranscriptionPanel = FloatingTranscriptionPanel()
    ) {
        self.appleSpeech = appleSpeech
        self.audioRecorder = audioRecorder
        self.mlxWhisper = mlxWhisper
        self.external = external
        self.llm = llm
        self.injector = injector
        self.panel = panel
        self.appleSpeech.onPartialTranscript = { [weak panel] text in
            DispatchQueue.main.async { panel?.updateText(text) }
        }
        self.appleSpeech.onRMS = { [weak panel] rms in
            DispatchQueue.main.async { panel?.updateRMS(rms) }
        }
        self.audioRecorder.onRMS = { [weak panel] rms in
            DispatchQueue.main.async { panel?.updateRMS(rms) }
        }
    }

    public func startRecording() {
        injectionTargetApplication = NSWorkspace.shared.frontmostApplication
        Logger.log("Recording start target=\(injectionTargetApplication.map { Logger.appDescription($0) } ?? "nil") settingsEngine=\(settings.recognitionEngine.rawValue) language=\(settings.language.rawValue) accessibilityTrusted=\(PermissionsHelper.accessibilityTrusted())")
        panel.show(text: "Listening…")
        let backends = settings.effectiveRecognitionBackends
        Logger.log("Recording backends=\(backends.map(\.rawValue).joined(separator: ","))")
        activeBackends = backends
        guard let first = backends.first else {
            Logger.log("Recording start aborted: no recognition backends")
            panel.updateText("No local engine available")
            return
        }
        switch first {
        case .appleSpeech:
            requestSpeechAuthorizationIfNeeded { [weak self] ok in
                guard let self else { return }
                Logger.log("Speech authorization checked ok=\(ok)")
                guard ok else {
                    self.panel.updateText("Speech permission needed")
                    return
                }
                do {
                    try self.appleSpeech.start(language: self.settings.language)
                    Logger.log("Apple Speech started")
                } catch {
                    Logger.log("Apple Speech start failed: \(error)")
                    self.panel.updateText("Apple Speech unavailable")
                    if self.settings.recognitionEngine == .auto {
                        self.activeBackends = Array(backends.dropFirst())
                        self.tryRecorderFallbackStart()
                    }
                }
            }
        case .mlxWhisper, .externalAPI:
            tryRecorderFallbackStart()
        }
    }

    public func stopRecording() {
        Logger.log("Recording stop requested activeBackends=\(activeBackends.map(\.rawValue).joined(separator: ",")) target=\(injectionTargetApplication.map { Logger.appDescription($0) } ?? "nil")")
        panel.updateText("Transcribing…")
        let backends = activeBackends
        guard let first = backends.first else {
            finish("")
            return
        }
        switch first {
        case .appleSpeech:
            appleSpeech.stop { [weak self] transcript in
                guard let self else { return }
                if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.finish(transcript)
                    return
                }
                if self.settings.recognitionEngine == .auto {
                    self.tryFallbacks(audioURL: self.appleSpeech.lastAudioFileURL, remainingBackends: Array(backends.dropFirst()))
                } else {
                    self.finish("")
                }
            }
        case .mlxWhisper, .externalAPI:
            audioRecorder.stop { [weak self] audioURL in
                self?.tryFallbacks(audioURL: audioURL, remainingBackends: backends)
            }
        }
    }

    public func cancel() {
        Logger.log("Recording cancelled")
        appleSpeech.cancel()
        audioRecorder.cancel()
        panel.hideAnimated()
    }

    private func tryRecorderFallbackStart() {
        do {
            Logger.log("Recorder fallback start requested")
            try audioRecorder.start()
            Logger.log("Recorder fallback started audioURL=\(audioRecorder.lastAudioFileURL?.path ?? "nil")")
        } catch {
            Logger.log("Audio recorder start failed: \(error)")
            panel.updateText("Microphone unavailable")
        }
    }

    private func tryFallbacks(audioURL: URL?, remainingBackends: [RecognitionBackend]) {
        Logger.log("Trying fallbacks audioURL=\(audioURL?.path ?? "nil") remaining=\(remainingBackends.map(\.rawValue).joined(separator: ","))")
        guard let audioURL else {
            finish("")
            return
        }
        guard let backend = remainingBackends.first else {
            finish("")
            return
        }
        switch backend {
        case .appleSpeech:
            finish("")
        case .mlxWhisper:
            guard mlxWhisper.isAvailable() else {
                tryFallbacks(audioURL: audioURL, remainingBackends: Array(remainingBackends.dropFirst()))
                return
            }
            panel.updateText("Using local mlx-whisper…")
            mlxWhisper.transcribe(audioFileURL: audioURL) { [weak self] text in
                guard let self else { return }
                if let text, !text.isEmpty { self.finish(text) }
                else { self.tryFallbacks(audioURL: audioURL, remainingBackends: Array(remainingBackends.dropFirst())) }
            }
        case .externalAPI:
            panel.updateText("Trying External LLM…")
            external.transcribe(audioFileURL: audioURL) { [weak self] text in
                self?.finish(text ?? "")
            }
        }
    }

    private func finish(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        Logger.log("Finish recognition rawLength=\(raw.count) trimmedLength=\(text.count) hasText=\(!text.isEmpty)")
        guard !text.isEmpty else {
            panel.updateText("No speech detected")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.panel.hideAnimated() }
            return
        }
        let current = SettingsStore.shared.settings
        let config = SettingsStore.shared.llmConfiguration
        if config.isComplete {
            Logger.log("LLM refinement enabled timeout=\(current.llmTimeoutSeconds) model=\(config.model) baseURL=\(config.apiBaseURL)")
            panel.updateText("Refining…")
            llm.refine(text: text, config: config, timeout: current.llmTimeoutSeconds) { [weak self] refined in
                self?.injectAndHide(refined)
            }
        } else {
            Logger.log("LLM refinement skipped; config incomplete")
            injectAndHide(text)
        }
    }

    private func injectAndHide(_ text: String) {
        Logger.log("Inject and hide textLength=\(text.count) target=\(injectionTargetApplication.map { Logger.appDescription($0) } ?? "nil")")
        panel.updateText(text)
        injector.inject(text, targetApplication: injectionTargetApplication)
        injectionTargetApplication = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.panel.hideAnimated() }
    }

    private func requestSpeechAuthorizationIfNeeded(completion: @escaping (Bool) -> Void) {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            completion(true)
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async { completion(status == .authorized) }
            }
        default:
            completion(false)
        }
    }
}
