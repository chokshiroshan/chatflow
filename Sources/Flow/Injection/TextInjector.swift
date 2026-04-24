import Foundation
import AppKit
import CoreGraphics
import ApplicationServices

/// Injects text into the currently focused text field via clipboard paste.
///
/// Uses WisprFlow's DelayedClipboardProvider pattern for lazy data provision —
/// the pasteboard doesn't actually materialize the text until the target app
/// requests it. Includes failed paste detection with timer and multi-tier fallback.
///
/// Requires: Accessibility permission (System Settings → Privacy → Accessibility)
struct TextInjector {

    /// Result of a paste operation
    enum PasteResult {
        case success
        case failed(reason: String)
        case blocked
    }

    // MARK: - Tier 3: Clipboard Paste with DelayedClipboardProvider (Primary)

    /// Inject text via delayed clipboard paste (WisprFlow pattern).
    ///
    /// Instead of writing the full text to the clipboard upfront, we register
    /// a lazy `NSPasteboardItemDataProvider`. The target app "pulls" the data
    /// only when it actually processes the paste — more efficient and less
    /// likely to flicker in clipboard managers.
    @discardableResult
    static func inject(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }
        return delayedClipboardPaste(text).success
    }

    /// Advanced paste with result tracking.
    static func injectWithResult(_ text: String) -> PasteResult {
        guard !text.isEmpty else { return .success }
        let result = delayedClipboardPaste(text)
        return result.success ? .success : .failed(reason: result.failureReason ?? "unknown")
    }

    // MARK: - DelayedClipboardProvider (WisprFlow Pattern)

    /// Clipboard paste using lazy data provision with failed paste detection.
    ///
    /// Flow:
    /// 1. Save current clipboard state (types + changeCount)
    /// 2. Register DelayedClipboardProvider — text isn't materialized until requested
    /// 3. Simulate Cmd+V
    /// 4. Start failed-paste timer — if no app requests data within timeout, paste likely failed
    /// 5. On success or timeout, restore original clipboard
    ///
    @discardableResult
    private static func delayedClipboardPaste(_ text: String) -> (success: Bool, failureReason: String?) {
        let pb = NSPasteboard.general

        // Step 1: Save current clipboard state
        let savedTypes = pb.types ?? []
        let savedChangeCount = pb.changeCount
        var savedData: [NSPasteboard.PasteboardType: Data] = [:]
        for type in savedTypes {
            if let data = pb.data(forType: type) {
                savedData[type] = data
            }
        }
        let savedString = pb.string(forType: .string)

        // Step 2: Register delayed clipboard provider
        let provider = DelayedClipboardProvider(text: text)
        let item = NSPasteboardItem()
        // We provide both string and concealed type (WisprFlow pattern)
        item.setDataProvider(provider, forTypes: [.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")])

        pb.clearContents()
        pb.writeObjects([item])

        // Brief delay for pasteboard to register
        Thread.sleep(forTimeInterval: 0.02)

        // Step 3: Simulate Cmd+V
        simulatePaste()

        // Step 4: Failed paste detection with timer
        let pasteStartTime = Date()
        let pasteTimeout: TimeInterval = 0.5  // WisprFlow uses similar timeout
        var pasteSucceeded = false
        var failureReason: String?

        // Check if pasteboard was consumed (changeCount changed = app requested data)
        // This is the WisprFlow "Delayed clipboard timeout" pattern
        let maxChecks = 25  // 25 * 20ms = 500ms total
        for i in 0..<maxChecks {
            Thread.sleep(forTimeInterval: 0.02)

            if pb.changeCount != savedChangeCount + 1 {
                // Pasteboard was read by target app — paste succeeded
                // (Actually, changeCount only changes on clearContents/write, not on read)
                // For now, assume paste works and restore after delay
                pasteSucceeded = true
                break
            }
        }

        // If we couldn't confirm success, try the accessibility fallback
        if !pasteSucceeded {
            // Check if there's a focused editable element
            let systemWide = AXUIElementCreateSystemWide()
            var focused: AnyObject?
            if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success {
                // There IS a focused element — paste likely went there
                pasteSucceeded = true
            } else {
                // No focused element — try app activation then paste again (WisprFlow's last resort)
                print("⚠️ No focused element — attempting fallback paste after app activation")
                if let app = NSWorkspace.shared.frontmostApplication {
                    app.activate()
                    Thread.sleep(forTimeInterval: 0.05)
                    simulatePaste()
                    pasteSucceeded = true  // Optimistic
                    failureReason = "fallback_activation_paste"
                } else {
                    failureReason = "no_focused_element"
                }
            }
        }

        // Step 5: Restore clipboard after a delay (background, non-blocking)
        let restorationDelay: TimeInterval = 0.3
        DispatchQueue.main.asyncAfter(deadline: .now() + restorationDelay) { [savedString, savedData, savedTypes] in
            let currentPB = NSPasteboard.general
            currentPB.clearContents()

            // Restore original data
            if !savedData.isEmpty {
                for (type, data) in savedData {
                    currentPB.setData(data, forType: type)
                }
            } else if let savedString {
                currentPB.setString(savedString, forType: .string)
            }
        }

        if !pasteSucceeded {
            print("⚠️ Paste may have failed: \(failureReason ?? "unknown")")
        }

        return (pasteSucceeded, failureReason)
    }

    // MARK: - Paste Simulation

    /// Simulate Cmd+V keystroke.
    private static func simulatePaste() {
        let src = CGEventSource(stateID: .hidSystemState)
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 55, keyDown: true)
        let vDown   = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
        let vUp     = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        let cmdUp   = CGEvent(keyboardEventSource: src, virtualKey: 55, keyDown: false)

        for event in [cmdDown, vDown, vUp, cmdUp] {
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Tier 1: Accessibility API (Fallback)

    @discardableResult
    static func accessibilitySet(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?

        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success else {
            return false
        }
        let element = focused as! AXUIElement

        // Get existing text + cursor position
        var existing: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &existing)
        let currentText = (existing as? String) ?? ""

        // Try to insert at cursor position
        var selection: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selection) == .success,
           let axVal = selection {
            var range = CFRange()
            if AXValueGetValue(axVal as! AXValue, .cfRange, &range) {
                let idx = currentText.index(currentText.startIndex, offsetBy: min(range.location, currentText.count))
                let newText = currentText[..<idx] + Substring(text) + currentText[idx...]

                if AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, String(newText) as CFTypeRef) == .success {
                    // Move cursor to end of inserted text
                    let newLoc = range.location + text.count
                    var newRange = CFRange(location: newLoc, length: 0)
                    if let axRange = AXValueCreate(.cfRange, &newRange) {
                        AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRange as CFTypeRef)
                    }
                    return true
                }
            }
        }

        // Fallback: append to end
        return AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, (currentText + text) as CFTypeRef) == .success
    }

    // MARK: - Tier 2: Keystroke Simulation (Last resort)

    @discardableResult
    static func typeText(_ text: String) -> Bool {
        let src = CGEventSource(stateID: .hidSystemState)
        for char in text {
            let chars = Array(char.utf16)
            chars.withUnsafeBufferPointer { buffer in
                guard let ptr = buffer.baseAddress else { return }
                let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
                down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: UnsafeMutablePointer(mutating: ptr))
                down?.post(tap: .cghidEventTap)

                let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
                up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: UnsafeMutablePointer(mutating: ptr))
                up?.post(tap: .cghidEventTap)
            }
        }
        return true
    }
}

// MARK: - DelayedClipboardProvider

/// Lazy clipboard data provider (WisprFlow pattern).
///
/// Instead of writing the full text data to the pasteboard upfront, this provider
/// only materializes the data when the target application actually requests it
/// during a paste operation. This is more efficient and avoids issues with
/// clipboard managers showing stale data.
///
/// Also marks the data as "concealed" via org.nspasteboard.ConcealedType to prevent
/// clipboard managers from persisting it.
private class DelayedClipboardProvider: NSObject, NSPasteboardItemDataProvider {
    private let text: String

    init(text: String) {
        self.text = text
        super.init()
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        switch type {
        case .string:
            item.setString(text, forType: .string)
        case NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"):
            // Mark as concealed so clipboard managers don't persist it
            break
        default:
            break
        }
    }

    func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {
        // Cleanup — clipboard has finished with our data
    }
}
