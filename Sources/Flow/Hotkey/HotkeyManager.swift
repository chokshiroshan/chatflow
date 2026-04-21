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

    struct KeyCombo: Codable, Equatable {
        let keyCode: CGKeyCode
        let modifiers: CGEventFlags
        let displayName: String

        /// Parse a combo string like "ctrl+space", "cmd+shift+d", "f5"
        static func parse(_ string: String) -> KeyCombo {
            var modifiers: CGEventFlags = []
            var keyPart = string.lowercased().trimmingCharacters(in: .whitespaces)

            // Extract modifiers
            if keyPart.contains("ctrl+") || keyPart.contains("control+") {
                modifiers.insert(.maskControl)
                keyPart = keyPart.replacingOccurrences(of: "ctrl+", with: "")
                keyPart = keyPart.replacingOccurrences(of: "control+", with: "")
            }
            if keyPart.contains("cmd+") || keyPart.contains("command+") {
                modifiers.insert(.maskCommand)
                keyPart = keyPart.replacingOccurrences(of: "cmd+", with: "")
                keyPart = keyPart.replacingOccurrences(of: "command+", with: "")
            }
            if keyPart.contains("opt+") || keyPart.contains("alt+") || keyPart.contains("option+") {
                modifiers.insert(.maskAlternate)
                keyPart = keyPart.replacingOccurrences(of: "opt+", with: "")
                keyPart = keyPart.replacingOccurrences(of: "alt+", with: "")
                keyPart = keyPart.replacingOccurrences(of: "option+", with: "")
            }
            if keyPart.contains("shift+") {
                modifiers.insert(.maskShift)
                keyPart = keyPart.replacingOccurrences(of: "shift+", with: "")
            }

            let (keyCode, displayName) = resolveKey(keyPart)
            return KeyCombo(keyCode: keyCode, modifiers: modifiers, displayName: displayName)
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
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return mgr.handle(type: type, event: event)
            },
            userInfo: userInfo
        ) else {
            print("⚠️ CGEventTap failed. Grant Input Monitoring in System Settings → Privacy & Security → Input Monitoring.")
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

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent> {
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
            let requiredFlags = keyCombo.modifiers
            let modifierFlags: CGEventFlags = [.maskControl, .maskCommand, .maskAlternate, .maskShift]

            // Check that ALL required modifiers are present
            let requiredSet = flags.intersection(requiredFlags)
            if requiredSet != requiredFlags {
                return Unmanaged.passUnretained(event)
            }

            // For combos, also check no extra modifiers are held (optional — remove for more flexibility)
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
                if !isRecording { isRecording = true; onStart?() }
            } else if !down && keyIsDown {
                keyIsDown = false
                if isRecording { isRecording = false; onStop?() }
            }
        case .toggle:
            if down && !keyIsDown {
                keyIsDown = true
                isRecording.toggle()
                if isRecording { onStart?() } else { onStop?() }
            } else if !down {
                keyIsDown = false
            }
        }

        return Unmanaged.passUnretained(event)
    }
}
