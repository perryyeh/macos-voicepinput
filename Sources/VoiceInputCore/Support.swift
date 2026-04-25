import AppKit
import Foundation
import Security
import Speech

public final class SettingsStore {
    public static let shared = SettingsStore()
    private let defaults = UserDefaults.standard
    private let settingsKey = "AppSettings.v1"
    private let llmConfigKey = "LLMConfiguration.v1"
    private let apiKeyAccount = "llm-api-key"

    public init() {}

    public var settings: AppSettings {
        get {
            guard let data = defaults.data(forKey: settingsKey),
                  let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
                return .defaultSettings
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: settingsKey)
            }
        }
    }

    public var llmConfiguration: LLMConfiguration {
        get {
            var config: LLMConfiguration
            if let data = defaults.data(forKey: llmConfigKey),
               let decoded = try? JSONDecoder().decode(LLMConfiguration.self, from: data) {
                config = decoded
            } else {
                config = LLMConfiguration()
            }
            config.apiKey = KeychainStore.read(account: apiKeyAccount) ?? ""
            return config
        }
        set {
            let apiKey = newValue.apiKey
            var stored = newValue
            stored.apiKey = ""
            if let data = try? JSONEncoder().encode(stored) {
                defaults.set(data, forKey: llmConfigKey)
            }
            if apiKey.isEmpty {
                KeychainStore.delete(account: apiKeyAccount)
            } else {
                KeychainStore.save(apiKey, account: apiKeyAccount)
            }
        }
    }
}

public enum KeychainStore {
    static let service = "local.voiceinput.app"

    @discardableResult
    public static func save(_ value: String, account: String) -> Bool {
        delete(account: account)
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    public static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

public enum Logger {
    public static var transcriptLoggingEnabled = false

    public static var logDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/VoiceInput", isDirectory: true)
    }

    public static var logFileURL: URL {
        logDirectoryURL.appendingPathComponent("voiceinput.log")
    }

    public static func log(_ message: String) {
        try? FileManager.default.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
        let thread = Thread.isMainThread ? "main" : "background"
        let line = "\(ISO8601DateFormatter().string(from: Date())) pid=\(ProcessInfo.processInfo.processIdentifier) thread=\(thread) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logFileURL.path),
           let handle = try? FileHandle(forWritingTo: logFileURL) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: logFileURL)
        }
    }

    public static func installCrashLogging() {
        NSSetUncaughtExceptionHandler { exception in
            Logger.log("Uncaught NSException name=\(exception.name.rawValue) reason=\(exception.reason ?? "nil") callStack=\(exception.callStackSymbols.joined(separator: " | "))")
        }
    }

    public static func diagnosticsSummary() -> String {
        let bundle = Bundle.main
        let appPath = bundle.bundlePath
        let bundleID = bundle.bundleIdentifier ?? "unknown"
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let trusted = PermissionsHelper.accessibilityTrusted()
        let speechStatus = SFSpeechRecognizer.authorizationStatus().debugDescription
        let frontmost = NSWorkspace.shared.frontmostApplication.map { appDescription($0) } ?? "nil"
        return "appPath=\(appPath) bundleID=\(bundleID) version=\(version) build=\(build) accessibilityTrusted=\(trusted) speechStatus=\(speechStatus) frontmost=\(frontmost) log=\(logFileURL.path)"
    }

    public static func appDescription(_ app: NSRunningApplication) -> String {
        let name = app.localizedName ?? "unknown"
        let bundleID = app.bundleIdentifier ?? "unknown"
        return "name=\(name) bundleID=\(bundleID) pid=\(app.processIdentifier) terminated=\(app.isTerminated) active=\(app.isActive)"
    }
}

private extension SFSpeechRecognizerAuthorizationStatus {
    var debugDescription: String {
        switch self {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .authorized: return "authorized"
        @unknown default: return "unknown(\(rawValue))"
        }
    }
}

public enum PermissionsHelper {
    public static func accessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    public static func requestAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
