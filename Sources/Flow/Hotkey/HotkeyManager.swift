import ApplicationServices
import Foundation
import CoreGraphics

/// Global hotkey detection via CGEventTap — inspired by WisprFlow's KeyboardService.
///
/// Tracks ALL currently held keys (`curKeysDown`) and modifiers (`modifierKeysDown`)
/// for reliable key state management. Supports multiple configurable hotkey combos
/// with runtime updates. Includes stale key cleanup and tap resilience.
///
/// Requires: Input Monitoring permission.
final class HotkeyManager {
    var onStart: (@Sendable () -> Void)?
    var onStop: (@Sendable () -> Void)?
    /// Set to true when the enhanced modifier (Shift) was held alongside the hotkey.
    private(set) var isEnhancedTrigger: Bool = false

    // MARK: - Key State Tracking (WisprFlow pattern)

    /// All keys currently held down (keycode → true).
    /// Unlike a single `keyIsDown` bool, this properly handles:
    /// - Multiple keys held simultaneously
    /// - Keys held before app start (stale keys)
    /// - Key state during paste operations
    private var curKeysDown: Set<CGKeyCode> = []

    /// Currently held modifier keys — tracked separately for combo matching.
    private var modifierKeysDown: Set<CGKeyCode> = []

    /// Keys that were already held when the event tap started.
    /// Cleaned up on first event to prevent ghost states.
    private var staleKeysCleaned = false

    /// Whether a recording session is active.
    private var isRecording = false

    // MARK: - Tap Resilience

    /// Auto-restart the event tap when it gets disabled (up to maxRetries).
    private var tapRetryCount = 0
    private let maxTapRetries = 5

    // MARK: - Configuration

    /// The active key combo (can be updated at runtime via updateCombo).
    private var keyCombo: KeyCombo
    private let mode: FlowConfig.HotkeyMode
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

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

            /// CGKeyCode for the modifier itself (for curKeysDown tracking)
            var keyCode: CGKeyCode? {
                switch self {
                case .control: return 59   // Left Control
                case .command: return 55   // Left Command
                case .option:  return 58   // Left Option
                case .shift:   return 56   // Left Shift
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

    // MARK: - Modifier keycodes (for tracking in curKeysDown)

    /// Set of keycodes that represent modifier keys
    private static let modifierKeycodes: Set<CGKeyCode> = [
        55, 54,   // Left/Right Command
        56, 60,   // Left/Right Shift
        58, 61,   // Left/Right Option
        59, 62,   // Left/Right Control
        63,       // Fn
    ]

    init(key: String, mode: FlowConfig.HotkeyMode) {
        self.mode = mode
        self.keyCombo = KeyCombo.parse(key)
    }

    deinit { stop() }

    // MARK: - Runtime Hotkey Update (WisprFlow's UpdateShortcuts pattern)

    /// Update the hotkey combo at runtime without restarting the event tap.
    func updateCombo(_ newKey: String) {
        let newCombo = KeyCombo.parse(newKey)
        guard newCombo != keyCombo else { return }

        // If recording with old combo, stop first
        if isRecording {
            isRecording = false
            onStop?()
        }
        curKeysDown.removeAll()
        modifierKeysDown.removeAll()
        keyCombo = newCombo
        print("⌨️ Hotkey updated to: \(newCombo.displayName)")
    }

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
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return mgr.handle(type: type, event: event)
            },
            userInfo: userInfo
        ) else {
            print("⚠️ CGEventTap failed. Grant Input Monitoring in System Settings → Privacy & Security → Input Monitoring.")
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
        curKeysDown.removeAll()
        modifierKeysDown.removeAll()
        tapRetryCount = 0
    }

    // MARK: - Event Handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // MARK: Tap resilience (WisprFlow pattern)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if tapRetryCount < maxTapRetries, let eventTap {
                tapRetryCount += 1
                CGEvent.tapEnable(tap: eventTap, enable: true)
                print("⌨️ Event tap re-enabled (retry \(tapRetryCount)/\(maxTapRetries))")
            } else if tapRetryCount >= maxTapRetries {
                print("⚠️ Hit max event tap retries (\(maxTapRetries)), shutting down tap")
            }
            return Unmanaged.passUnretained(event)
        }

        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        // MARK: Stale key cleanup (WisprFlow pattern)
        // On the very first keyboard event, assume any "down" state from before
        // the tap started is stale. We can't know what was held, so we just
        // note that cleanup happened. If a key is "down" but we never saw its
        // keyDown event, it won't be in curKeysDown — which is correct.
        if !staleKeysCleaned {
            staleKeysCleaned = true
            print("⌨️ First keyboard event received — stale key state cleared")
        }

        // MARK: Update curKeysDown tracking
        switch type {
        case .keyDown:
            curKeysDown.insert(code)
            if Self.modifierKeycodes.contains(code) {
                modifierKeysDown.insert(code)
            }
        case .keyUp:
            curKeysDown.remove(code)
            if Self.modifierKeycodes.contains(code) {
                modifierKeysDown.remove(code)
            }
        case .flagsChanged:
            // Fn key and modifier keys fire as flagsChanged
            // Track them in curKeysDown based on flag state
            if code == 63 { // Fn key
                if event.flags.contains(.maskSecondaryFn) {
                    curKeysDown.insert(code)
                    modifierKeysDown.insert(code)
                } else {
                    curKeysDown.remove(code)
                    modifierKeysDown.remove(code)
                }
            }
        default:
            break
        }

        // MARK: Check if the event matches our hotkey
        let isHotkeyKey = code == keyCombo.keyCode

        // For modifier-based combos, check modifier flags
        let modifiersMatch: Bool
        if !keyCombo.modifiers.isEmpty {
            let flags = event.flags
            let requiredFlags = keyCombo.cgModifiers
            modifiersMatch = flags.contains(requiredFlags)
        } else {
            modifiersMatch = true
        }

        guard isHotkeyKey && modifiersMatch else {
            return Unmanaged.passUnretained(event)
        }

        // MARK: Determine key down/up
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

        // Reset tap retry count on successful event
        tapRetryCount = 0

        // MARK: Trigger logic
        switch mode {
        case .hold:
            if down && !isRecording {
                // Check if Shift is held (enhanced mode) — only if Shift is NOT part of the base combo
                isEnhancedTrigger = !keyCombo.modifiers.contains(.shift) && event.flags.contains(.maskShift)
                isRecording = true
                print("⌨️ Hotkey DOWN — starting dictation\(isEnhancedTrigger ? " (ENHANCED — screen context)" : "")")
                print("⌨️ curKeysDown: \(curKeysDown) | modifierKeysDown: \(modifierKeysDown)")
                onStart?()
            } else if !down && isRecording {
                isRecording = false
                print("⌨️ Hotkey UP — stopping dictation (curKeysDown: \(curKeysDown))")
                onStop?()
            }
        case .toggle:
            if down {
                // Toggle mode: each keyDown press toggles recording state
                isRecording.toggle()
                isEnhancedTrigger = !keyCombo.modifiers.contains(.shift) && event.flags.contains(.maskShift)
                print("⌨️ Hotkey TOGGLE — \(isRecording ? "starting" : "stopping") dictation")
                if isRecording { onStart?() } else { onStop?() }
            }
        }

        // Swallow the hotkey event so it doesn't pass through to the focused app
        return nil
    }
}
