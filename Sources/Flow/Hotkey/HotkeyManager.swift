import ApplicationServices
import Foundation
import CoreGraphics

/// Global hotkey detection via CGEventTap.
///
/// Supports key combos (e.g. "ctrl+space", "cmd+shift+d") and single keys.
/// Two modes: hold-to-talk and toggle.
/// Requires: Input Monitoring permission.
final class HotkeyManager {
    var onStart: (@Sendable () -> Void)?
    var onStop: (@Sendable () -> Void)?

    private let keyCombo: KeyCombo
    private let mode: FlowConfig.HotkeyMode
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyIsDown = false
    private var isRecording = false

    struct KeyCombo: Equatable {
        let keyCode: CGKeyCode
        let modifiers: Set<ModifierFlag>
        let displayName: String

        /// Modifier flags that can be stored as Codable
        enum ModifierFlag: String, Codable, CaseIterable {
            case control
            case command
            case option
            case shift

            var cgFlag: CGEventFlags {
                switch self {
                case .control: return .maskControl
                case .command: return .maskCommand
                case .option:  return .maskAlternate
                case .shift:   return .maskShift
                }
            }

            var displayName: String {
                switch self {
                case .control: return "Ctrl"
                case .command: return "⌘"
                case .option:  return "⌥"
                case .shift:   return "⇧"
                }
            }
        }

        var cgModifiers: CGEventFlags {
            var flags: CGEventFlags = []
            for mod in modifiers { flags.insert(mod.cgFlag) }
            return flags
        }

        // Codable conformance
        enum CodingKeys: String, CodingKey { case keyCode, modifiers, displayName }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(keyCode, forKey: .keyCode)
            try c.encode(modifiers.map { $0.rawValue }, forKey: .modifiers)
            try c.encode(displayName, forKey: .displayName)
        }

        init(keyCode: CGKeyCode, modifiers: Set<ModifierFlag>, displayName: String) {
            self.keyCode = keyCode
            self.modifiers = modifiers
            self.displayName = displayName
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            keyCode = try c.decode(CGKeyCode.self, forKey: .keyCode)
            let modStrings = try c.decode([String].self, forKey: .modifiers)
            modifiers = Set(modStrings.compactMap { ModifierFlag(rawValue: $0) })
            displayName = try c.decode(String.self, forKey: .displayName)
        }

        /// Parse a combo string like "ctrl+space", "cmd+shift+d", "f5"
        static func parse(_ string: String) -> KeyCombo {
            var mods = Set<ModifierFlag>()
            var keyPart = string.lowercased().trimmingCharacters(in: .whitespaces)

            if keyPart.contains("ctrl+") || keyPart.contains("control+") {
                mods.insert(.control)
                keyPart = keyPart.replacingOccurrences(of: "ctrl+", with: "")
                keyPart = keyPart.replacingOccurrences(of: "control+", with: "")
            }
            if keyPart.contains("cmd+") || keyPart.contains("command+") {
                mods.insert(.command)
                keyPart = keyPart.replacingOccurrences(of: "cmd+", with: "")
                keyPart = keyPart.replacingOccurrences(of: "command+", with: "")
            }
            if keyPart.contains("opt+") || keyPart.contains("alt+") || keyPart.contains("option+") {
                mods.insert(.option)
                keyPart = keyPart.replacingOccurrences(of: "opt+", with: "")
                keyPart = keyPart.replacingOccurrences(of: "alt+", with: "")
                keyPart = keyPart.replacingOccurrences(of: "option+", with: "")
            }
            if keyPart.contains("shift+") {
                mods.insert(.shift)
                keyPart = keyPart.replacingOccurrences(of: "shift+", with: "")
            }

            let (kc, dn) = resolveKey(keyPart)
            let fullDisplayName = mods.sorted { $0.displayName < $1.displayName }.map { $0.displayName }.joined() + dn
            return KeyCombo(keyCode: kc, modifiers: mods, displayName: fullDisplayName)
        }

        private static func resolveKey(_ name: String) -> (CGKeyCode, String) {
            switch name {
            case "space":       return (49, "Space")
            case "d":           return (2, "D")
            case "f":           return (3, "F")
            case "j":           return (38, "J")
            case "k":           return (40, "K")
            case "escape", "esc": return (53, "Esc")
            case "return", "enter": return (36, "Enter")
            case "tab":         return (48, "Tab")
            case "fn", "globe": return (63, "Fn")
            case "rightcmd", "rcmd": return (54, "Right ⌘")
            case "rightopt", "ropt": return (62, "Right ⌥")
            case "f5":          return (96, "F5")
            case "f6":          return (97, "F6")
            case "f7":          return (98, "F7")
            case "f8":          return (99, "F8")
            case "f9":          return (100, "F9")
            default:            return (63, "Fn")
            }
        }
    }

    init(key: String, mode: FlowConfig.HotkeyMode) {
        self.mode = mode
        self.keyCombo = KeyCombo.parse(key)
    }

    deinit { stop() }

    // MARK: - Public

    func start() {
        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap, // NOT listenOnly — we need to suppress the hotkey event
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return mgr.handle(type: type, event: event)
            },
            userInfo: userInfo
        ) else {
            print("⚠️ CGEventTap failed. Grant Input Monitoring in System Settings → Privacy & Security → Input Monitoring.")
            print("⚠️ Also ensure Flow is not sandboxed. Try: open System Settings → Privacy & Security → Input Monitoring → add Flow")
            // Try alternative: Accessibility permission
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            let trusted = AXIsProcessTrustedWithOptions(options)
            print("⚠️ Accessibility trusted: \(trusted)")
            return
        }

        self.eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("⌨️ Hotkey registered: \(keyCombo.displayName) (\(mode.rawValue) mode)")
    }

    func stop() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - Event Handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable if disabled
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        // Check if the key matches
        guard code == keyCombo.keyCode else { return Unmanaged.passUnretained(event) }

        // Check modifiers if combo requires them
        if !keyCombo.modifiers.isEmpty {
            let flags = event.flags
            let requiredFlags = keyCombo.cgModifiers

            // Check that ALL required modifiers are present
            if !flags.contains(requiredFlags) {
                return Unmanaged.passUnretained(event)
            }
        }

        let down: Bool
        switch type {
        case .keyDown:
            down = true
        case .keyUp:
            down = false
        case .flagsChanged:
            // Fn key fires as flagsChanged (keyCode 63)
            if keyCombo.keyCode == 63 {
                down = event.flags.contains(.maskSecondaryFn)
            } else {
                return Unmanaged.passUnretained(event)
            }
        default:
            return Unmanaged.passUnretained(event)
        }

        switch mode {
        case .hold:
            if down && !keyIsDown {
                keyIsDown = true
                if isRecording {
                    // Stuck state — previous key-up was missed, stop first
                    print("⌨️ Hotkey DOWN while still recording — forcing stop first")
                    isRecording = false
                    onStop?()
                }
                isRecording = true
                print("⌨️ Hotkey DOWN — starting dictation")
                onStart?()
            } else if !down && keyIsDown {
                keyIsDown = false
                if isRecording {
                    isRecording = false
                    print("⌨️ Hotkey UP — stopping dictation")
                    onStop?()
                }
            }
        case .toggle:
            if down && !keyIsDown {
                keyIsDown = true
                isRecording.toggle()
                print("⌨️ Hotkey TOGGLE — \(isRecording ? "starting" : "stopping") dictation")
                if isRecording { onStart?() } else { onStop?() }
            } else if !down {
                keyIsDown = false
            }
        }

        // Swallow the hotkey event so it doesn't pass through to the focused app
        // (prevents the "toot" system beep in apps like Notes)
        return nil
    }
}
