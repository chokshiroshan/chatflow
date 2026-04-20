import Foundation
import AppKit
import CoreGraphics
import ApplicationServices

/// Injects text into the currently focused text field.
///
/// Three-tier fallback chain (same architecture as Wispr Flow):
/// 1. Accessibility API (AXUIElement) — fast but doesn't work everywhere
/// 2. CGEvent keystroke simulation — universal but slow for long text
/// 3. Clipboard paste (NSPasteboard + Cmd+V) — most reliable, default choice
///
/// Requires: Accessibility permission (System Settings → Privacy → Accessibility)
struct TextInjector {

    /// Inject text using the most reliable method.
    static func inject(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }

        // Try clipboard paste first (most reliable across all apps)
        return clipboardPaste(text)
    }

    // MARK: - Tier 3: Clipboard Paste (Primary — Most Reliable)

    @discardableResult
    static func clipboardPaste(_ text: String) -> Bool {
        let pb = NSPasteboard.general

        // Save current clipboard
        let saved = pb.string(forType: .string)
        let savedCount = pb.changeCount

        // Write our text
        pb.clearContents()
        pb.setString(text, forType: .string)

        // Brief delay for pasteboard to register
        Thread.sleep(forTimeInterval: 0.02)

        // Simulate Cmd+V
        let src = CGEventSource(stateID: .hidSystemState)
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 55, keyDown: true)
        let vDown   = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
        let vUp     = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        let cmdUp   = CGEvent(keyboardEventSource: src, virtualKey: 55, keyDown: false)

        for event in [cmdDown, vDown, vUp, cmdUp] {
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }

        // Restore clipboard after paste completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let current = NSPasteboard.general
            if current.changeCount != savedCount {
                current.clearContents()
                if let saved { current.setString(saved, forType: .string) }
            }
        }

        return true
    }

    // MARK: - Tier 1: Accessibility API

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

    // MARK: - Tier 2: Keystroke Simulation

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
