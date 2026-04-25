import AppKit
import Foundation
import Security

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

    public static func log(_ message: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/VoiceInput", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("voiceinput.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: file.path),
               let handle = try? FileHandle(forWritingTo: file) {
                handle.seekToEndOfFile()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: file)
            }
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
