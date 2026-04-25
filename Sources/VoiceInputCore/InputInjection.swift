import AppKit
import Carbon.HIToolbox

public final class TextInjector {
    public init() {}

    public static func textForInsertion(_ text: String) -> String {
        text.hasSuffix(" ") ? text : text + " "
    }

    public func inject(_ text: String, targetApplication: NSRunningApplication? = nil) {
        guard !text.isEmpty else {
            Logger.log("Text injection skipped: empty text")
            return
        }
        let insertionText = Self.textForInsertion(text)
        let originalItems = NSPasteboard.general.pasteboardItems ?? []
        let originalInput = InputSourceManager.currentInputSourceID()
        let shouldSwitch = originalInput.map { InputSourcePolicy.isCJKInputSource(identifier: $0) } ?? false
        Logger.log("Text injection begin textLength=\(text.count) insertionLength=\(insertionText.count) target=\(targetApplication.map { Logger.appDescription($0) } ?? "nil") frontmost=\(NSWorkspace.shared.frontmostApplication.map { Logger.appDescription($0) } ?? "nil") pasteboardItems=\(originalItems.count) originalInput=\(originalInput ?? "nil") shouldSwitchInput=\(shouldSwitch)")

        if shouldSwitch {
            Logger.log("Switching input source to ASCII before paste")
            InputSourceManager.selectASCIIInputSource()
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(insertionText, forType: .string)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let targetApplication, !targetApplication.isTerminated {
                Logger.log("Activating paste target before Cmd+V target=\(Logger.appDescription(targetApplication))")
                targetApplication.activate(options: [])
            } else {
                Logger.log("Paste target missing or terminated; using current frontmost=\(NSWorkspace.shared.frontmostApplication.map { Logger.appDescription($0) } ?? "nil")")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                Logger.log("Posting Cmd+V frontmost=\(NSWorkspace.shared.frontmostApplication.map { Logger.appDescription($0) } ?? "nil")")
                Self.sendCommandV()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                if shouldSwitch, let originalInput {
                    Logger.log("Restoring input source originalInput=\(originalInput)")
                    InputSourceManager.selectInputSource(identifier: originalInput)
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects(originalItems)
                Logger.log("Text injection cleanup completed restoredPasteboardItems=\(originalItems.count)")
            }
        }
    }

    private static func sendCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        guard let keyDown, let keyUp else {
            Logger.log("Failed to create Cmd+V CGEvents")
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

public enum InputSourceManager {
    public static func currentInputSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let cfID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(cfID).takeUnretainedValue() as String
    }

    public static func selectASCIIInputSource() {
        if !selectInputSource(identifier: "com.apple.keylayout.ABC") {
            _ = selectInputSource(identifier: "com.apple.keylayout.US")
        }
    }

    @discardableResult
    public static func selectInputSource(identifier: String) -> Bool {
        let sources = TISCreateInputSourceList(nil, false).takeRetainedValue() as NSArray
        for item in sources {
            let source = item as! TISInputSource
            guard let cfID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
            let id = Unmanaged<CFString>.fromOpaque(cfID).takeUnretainedValue() as String
            if id == identifier {
                return TISSelectInputSource(source) == noErr
            }
        }
        return false
    }
}

public extension Notification.Name {
    static let voiceInputHotkeySettingsChanged = Notification.Name("VoiceInputHotkeySettingsChanged")
}

public final class HotkeyMonitor {
    public var onPressed: (() -> Void)?
    public var onReleased: (() -> Void)?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isDown = false

    public init() {}

    public func start() {
        stop()
        let mask = (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handle(proxy: proxy, type: type, event: event)
        }
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let eventTap else {
            Logger.log("Failed to create event tap; check Accessibility permission")
            return
        }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource { CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        Logger.log("Hotkey monitor started with trigger: \(SettingsStore.shared.settings.hotkeySettings.displayName)")
    }

    public func stop() {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let eventTap { CFMachPortInvalidate(eventTap) }
        self.eventTap = nil
        self.runLoopSource = nil
        self.isDown = false
    }

    public func restart() {
        stop()
        start()
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        switch SettingsStore.shared.settings.hotkeySettings.trigger {
        case .functionKey:
            handleModifierKey(type: type, keyCode: keyCode, targetKeyCode: 63, requiredFlag: .maskSecondaryFn, flags: flags)
        case .rightOption:
            handleModifierKey(type: type, keyCode: keyCode, targetKeyCode: 61, requiredFlag: .maskAlternate, flags: flags)
        case .controlSpace:
            handleShortcut(type: type, keyCode: keyCode, requiredFlags: [.maskControl], flags: flags)
        case .commandShiftSpace:
            handleShortcut(type: type, keyCode: keyCode, requiredFlags: [.maskCommand, .maskShift], flags: flags)
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleModifierKey(type: CGEventType, keyCode: Int, targetKeyCode: Int, requiredFlag: CGEventFlags, flags: CGEventFlags) {
        guard type == .flagsChanged, keyCode == targetKeyCode else { return }
        setPressed(flags.contains(requiredFlag))
    }

    private func handleShortcut(type: CGEventType, keyCode: Int, requiredFlags: CGEventFlags, flags: CGEventFlags) {
        guard keyCode == 49 else { return } // Space
        let modifiersMatch = flags.contains(requiredFlags)
        if type == .keyDown, modifiersMatch {
            setPressed(true)
        } else if type == .keyUp {
            setPressed(false)
        }
    }

    private func setPressed(_ pressed: Bool) {
        guard pressed != isDown else { return }
        isDown = pressed
        if pressed {
            DispatchQueue.main.async { self.onPressed?() }
        } else {
            DispatchQueue.main.async { self.onReleased?() }
        }
    }
}
