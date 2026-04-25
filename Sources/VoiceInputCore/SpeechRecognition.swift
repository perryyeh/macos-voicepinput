import AppKit
import AVFoundation
import Speech

public protocol SpeechRecognitionManaging: AnyObject {
    var onPartialTranscript: ((String) -> Void)? { get set }
    var onRMS: ((Float) -> Void)? { get set }
    func start(language: RecognitionLanguage) throws
    func stop(completion: @escaping (String) -> Void)
    func cancel()
}

public enum RecognitionError: Error {
    case recognizerUnavailable
    case authorizationDenied
    case noAudioFile
}

public final class AppleSpeechRecognizerManager: NSObject, SpeechRecognitionManaging {
    public var onPartialTranscript: ((String) -> Void)?
    public var onRMS: ((Float) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var finalTranscript = ""
    private var audioFile: AVAudioFile?
    private var audioFileURL: URL?

    public private(set) var lastAudioFileURL: URL?

    public override init() {}

    public func start(language: RecognitionLanguage) throws {
        finalTranscript = ""
        task?.cancel()
        task = nil
        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.rawValue))

        guard let recognizer, recognizer.isAvailable else { throw RecognitionError.recognizerUnavailable }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { throw RecognitionError.authorizationDenied }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("voiceinput-\(UUID().uuidString).caf")
        audioFileURL = tmp
        lastAudioFileURL = tmp
        audioFile = try? AVAudioFile(forWriting: tmp, settings: format.settings)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.request?.append(buffer)
            try? self.audioFile?.write(from: buffer)
            self.onRMS?(Self.rms(buffer: buffer))
        }

        task = recognizer.recognitionTask(with: request!) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.finalTranscript = result.bestTranscription.formattedString
                self.onPartialTranscript?(self.finalTranscript)
            }
            if error != nil {
                Logger.log("Apple Speech task ended with error: \(String(describing: error))")
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    public func stop(completion: @escaping (String) -> Void) {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        audioFile = nil
        let transcript = finalTranscript
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            completion(self?.finalTranscript.isEmpty == false ? self!.finalTranscript : transcript)
        }
    }

    public func cancel() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        task?.cancel()
        request?.endAudio()
        audioFile = nil
    }

    private static func rms(buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count { sum += channel[i] * channel[i] }
        return min(1.0, sqrt(sum / Float(count)) * 8.0)
    }
}

public final class AudioFileRecorder {
    public var onRMS: ((Float) -> Void)?
    public private(set) var lastAudioFileURL: URL?

    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?

    public init() {}

    public func start() throws {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("voiceinput-\(UUID().uuidString).caf")
        lastAudioFileURL = tmp
        audioFile = try AVAudioFile(forWriting: tmp, settings: format.settings)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            try? self.audioFile?.write(from: buffer)
            self.onRMS?(Self.rms(buffer: buffer))
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    public func stop(completion: @escaping (URL?) -> Void) {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        audioFile = nil
        completion(lastAudioFileURL)
    }

    public func cancel() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        audioFile = nil
    }

    private static func rms(buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count { sum += channel[i] * channel[i] }
        return min(1.0, sqrt(sum / Float(count)) * 8.0)
    }
}

public final class MLXWhisperTranscriber {
    public var executablePath: String = NSHomeDirectory() + "/.local/bin/local-transcribe"

    public init() {}

    public func isAvailable() -> Bool {
        FileManager.default.isExecutableFile(atPath: executablePath)
    }

    public func transcribe(audioFileURL: URL, model: String = "mlx-community/whisper-medium", completion: @escaping (String?) -> Void) {
        guard isAvailable() else {
            completion(nil)
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = [audioFileURL.path, model]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        process.terminationHandler = { proc in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                completion(proc.terminationStatus == 0 && !(text?.isEmpty ?? true) ? text : nil)
            }
        }
        do { try process.run() } catch {
            Logger.log("mlx-whisper run failed: \(error)")
            completion(nil)
        }
    }
}

public final class ExternalSpeechAPITranscriber {
    public init() {}

    public func transcribe(audioFileURL: URL, completion: @escaping (String?) -> Void) {
        // Intentionally conservative placeholder: external STT is the last fallback and is disabled
        // until a concrete OpenAI-compatible audio transcription endpoint is configured explicitly.
        Logger.log("External STT fallback requested but not configured; skipping network transcription")
        completion(nil)
    }
}
