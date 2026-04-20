import Foundation
import CoreGraphics

/// Global hotkey detection via CGEventTap.
///
/// Supports hold-to-talk (Fn default) and toggle modes.
/// Requires: Input Monitoring permission.
final class HotkeyManager {
    var onStart: (@Sendable () -> Void)?
    var onStop: (@Sendable () -> Void)?

    private let keyCode: CGKeyCode
    private let mode: FlowConfig.HotkeyMode
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyIsDown = false
    private var isRecording = false

    init(key: String, mode: FlowConfig.HotkeyMode) {
        self.mode = mode
        self.keyCode = Self.keyCode(for: key)
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
            print("⚠️ CGEventTap failed. Grant Input Monitoring in System Settings → Privacy.")
            return
        }

        self.eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("⌨️ Hotkey registered: \(mode.rawValue) mode, keyCode \(keyCode)")
    }

    func stop() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - Event Handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent> {
        // Re-enable if disabled (screen lock etc.)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard code == keyCode else { return Unmanaged.passUnretained(event) }

        let down: Bool
        switch type {
        case .keyDown: down = true
        case .keyUp: down = false
        case .flagsChanged:
            // Fn key fires as flagsChanged
            down = event.flags.contains(.maskSecondaryFn)
        default: return Unmanaged.passUnretained(event)
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

    // MARK: - Key Code Lookup

    static func keyCode(for name: String) -> CGKeyCode {
        switch name.lowercased() {
        case "fn", "globe":     return 63
        case "rightcmd", "rcmd": return 54
        case "rightopt", "ropt": return 62
        case "f5":  return 96
        case "f6":  return 97
        case "f7":  return 98
        case "f8":  return 99
        default:    return 63 // Default to Fn
        }
    }
}
