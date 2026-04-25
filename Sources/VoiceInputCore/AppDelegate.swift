import AppKit
import Speech

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotkeyMonitor = HotkeyMonitor()
    private let coordinator = RecognitionCoordinator()

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        requestInitialPermissions()
        setupStatusItem()
        hotkeyMonitor.onPressed = { [weak self] in self?.coordinator.startRecording() }
        hotkeyMonitor.onReleased = { [weak self] in self?.coordinator.stopRecording() }
        hotkeyMonitor.start()
        NotificationCenter.default.addObserver(forName: .voiceInputHotkeySettingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.hotkeyMonitor.restart()
        }
        Logger.log("VoiceInput launched")
    }

    public func applicationWillTerminate(_ notification: Notification) {
        hotkeyMonitor.stop()
    }

    private func requestInitialPermissions() {
        PermissionsHelper.requestAccessibilityIfNeeded()
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { _ in }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "🎙"
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let status = NSMenuItem(title: "Hold Fn to dictate", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(NSMenuItem.separator())

        let langMenu = NSMenu()
        for lang in RecognitionLanguage.allCases {
            let item = NSMenuItem(title: lang.displayName, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = lang.rawValue
            item.state = SettingsStore.shared.settings.language == lang ? .on : .off
            langMenu.addItem(item)
        }
        let langRoot = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        menu.setSubmenu(langMenu, for: langRoot)
        menu.addItem(langRoot)

        let engineMenu = NSMenu()
        for engine in RecognitionEngine.allCases {
            let item = NSMenuItem(title: engine.displayName, action: #selector(selectRecognitionEngine(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = engine.rawValue
            item.state = SettingsStore.shared.settings.recognitionEngine == engine ? .on : .off
            engineMenu.addItem(item)
        }
        let engineRoot = NSMenuItem(title: "Recognition Engine", action: nil, keyEquivalent: "")
        menu.setSubmenu(engineMenu, for: engineRoot)
        menu.addItem(engineRoot)

        let llmSettings = NSMenuItem(title: "LLM Settings…", action: #selector(openLLMSettings), keyEquivalent: ",")
        llmSettings.target = self
        menu.addItem(llmSettings)

        let hotkeySettings = NSMenuItem(title: "Hotkey Settings…", action: #selector(openHotkeySettings), keyEquivalent: "")
        hotkeySettings.target = self
        menu.addItem(hotkeySettings)

        let permissions = NSMenuItem(title: "Check Permissions", action: #selector(showPermissions), keyEquivalent: "")
        permissions.target = self
        menu.addItem(permissions)

        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let lang = RecognitionLanguage(rawValue: raw) else { return }
        var settings = SettingsStore.shared.settings
        settings.language = lang
        SettingsStore.shared.settings = settings
        rebuildMenu()
    }

    @objc private func selectRecognitionEngine(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let engine = RecognitionEngine(rawValue: raw) else { return }
        var settings = SettingsStore.shared.settings
        settings.recognitionEngine = engine
        SettingsStore.shared.settings = settings
        rebuildMenu()
    }

    @objc private func openLLMSettings() {
        LLMSettingsWindowController.shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openHotkeySettings() {
        HotkeySettingsWindowController.shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showPermissions() {
        let alert = NSAlert()
        alert.messageText = "VoiceInput Permissions"
        let access = PermissionsHelper.accessibilityTrusted() ? "✅" : "⚠️"
        let speech = SFSpeechRecognizer.authorizationStatus() == .authorized ? "✅" : "⚠️"
        alert.informativeText = "\(access) Accessibility\n\(speech) Speech Recognition\n\nVoiceInput needs Accessibility for the global hotkey and simulated paste. Input Monitoring is not required by this build, so it is normal if VoiceInput does not appear there."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

public final class HotkeySettingsWindowController: NSWindowController {
    public static let shared = HotkeySettingsWindowController()
    private let popup = NSPopUpButton()
    private let status = NSTextField(labelWithString: "")

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 170), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Hotkey Settings"
        super.init(window: window)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func showWindow(_ sender: Any?) {
        popup.removeAllItems()
        for trigger in HotkeyTrigger.allCases {
            popup.addItem(withTitle: trigger.displayName)
            popup.lastItem?.representedObject = trigger.rawValue
        }
        let current = SettingsStore.shared.settings.hotkeySettings.trigger.rawValue
        if let item = popup.itemArray.first(where: { $0.representedObject as? String == current }) {
            popup.select(item)
        }
        status.stringValue = "Default is Fn. If Fn conflicts with macOS, choose another shortcut."
        super.showWindow(sender)
        window?.center()
    }

    private func setup() {
        guard let content = window?.contentView else { return }
        let label = NSTextField(labelWithString: "Push-to-talk hotkey")
        let save = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        label.translatesAutoresizingMaskIntoConstraints = false
        popup.translatesAutoresizingMaskIntoConstraints = false
        save.translatesAutoresizingMaskIntoConstraints = false
        status.translatesAutoresizingMaskIntoConstraints = false
        status.textColor = .secondaryLabelColor
        content.addSubview(label)
        content.addSubview(popup)
        content.addSubview(save)
        content.addSubview(status)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            label.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            popup.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 16),
            popup.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            popup.widthAnchor.constraint(equalToConstant: 190),
            save.topAnchor.constraint(equalTo: popup.bottomAnchor, constant: 24),
            save.trailingAnchor.constraint(equalTo: popup.trailingAnchor),
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            status.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            status.topAnchor.constraint(equalTo: save.bottomAnchor, constant: 18)
        ])
    }

    @objc private func saveSettings() {
        guard let raw = popup.selectedItem?.representedObject as? String,
              let trigger = HotkeyTrigger(rawValue: raw) else { return }
        var settings = SettingsStore.shared.settings
        settings.hotkeySettings = HotkeySettings(trigger: trigger)
        SettingsStore.shared.settings = settings
        NotificationCenter.default.post(name: .voiceInputHotkeySettingsChanged, object: nil)
        status.stringValue = "Saved: \(trigger.displayName)"
    }
}

public final class LLMSettingsWindowController: NSWindowController {
    public static let shared = LLMSettingsWindowController()
    private let apiBase = NSTextField()
    private let apiKey = NSSecureTextField()
    private let model = NSTextField()
    private let status = NSTextField(labelWithString: "")

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 240), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "LLM Settings"
        super.init(window: window)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func showWindow(_ sender: Any?) {
        let config = SettingsStore.shared.llmConfiguration
        apiBase.stringValue = config.apiBaseURL
        apiKey.stringValue = config.apiKey
        model.stringValue = config.model
        status.stringValue = "API Key is stored in macOS Keychain. Clearing this field deletes it."
        super.showWindow(sender)
        window?.center()
    }

    private func setup() {
        guard let content = window?.contentView else { return }
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "API Base URL"), apiBase],
            [NSTextField(labelWithString: "API Key"), apiKey],
            [NSTextField(labelWithString: "Model"), model]
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 350
        grid.rowSpacing = 12
        grid.columnSpacing = 12

        let test = NSButton(title: "Test", target: self, action: #selector(testConfig))
        let save = NSButton(title: "Save", target: self, action: #selector(saveConfig))
        let buttons = NSStackView(views: [test, save])
        buttons.orientation = .horizontal
        buttons.spacing = 12
        buttons.translatesAutoresizingMaskIntoConstraints = false
        status.translatesAutoresizingMaskIntoConstraints = false
        status.textColor = .secondaryLabelColor

        content.addSubview(grid)
        content.addSubview(buttons)
        content.addSubview(status)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            grid.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            buttons.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 24),
            buttons.trailingAnchor.constraint(equalTo: grid.trailingAnchor),
            status.leadingAnchor.constraint(equalTo: grid.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: grid.trailingAnchor),
            status.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 18)
        ])
    }

    @objc private func saveConfig() {
        SettingsStore.shared.llmConfiguration = LLMConfiguration(apiBaseURL: apiBase.stringValue, apiKey: apiKey.stringValue, model: model.stringValue)
        status.stringValue = apiKey.stringValue.isEmpty ? "Saved. API Key cleared from Keychain." : "Saved. API Key stored in Keychain."
    }

    @objc private func testConfig() {
        let config = LLMConfiguration(apiBaseURL: apiBase.stringValue, apiKey: apiKey.stringValue, model: model.stringValue)
        status.stringValue = "Testing…"
        LLMRefiner().test(config: config) { [weak self] ok, result in
            self?.status.stringValue = ok ? "OK: \(result)" : "Failed or unexpected response: \(result)"
        }
    }
}
