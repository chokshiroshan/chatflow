import Foundation
import ApplicationServices
import Carbon
import AppKit

// MARK: - Types

/// How the selected text was obtained.
enum ExtractionMethod: String, Sendable {
    /// Direct Accessibility API query (preferred — no clipboard side-effects).
    case ax
    /// Clipboard-based fallback (save → Cmd+C → read → restore).
    case clipboard
}

/// The result of extracting the user's currently-selected text.
struct SelectedTextInfo: Sendable {
    /// The selected text content.
    let text: String
    /// The character range of the selection within the focused UI element, if available.
    let range: NSRange?
    /// Which extraction method was used.
    let method: ExtractionMethod
}

// MARK: - SelectedTextExtractor

/// Grabs whatever text the user has selected/highlighted in the focused app.
///
/// Enables workflows like "select text → trigger dictation → say 'rewrite this'".
///
/// Two extraction strategies:
/// 1. **AX (preferred)**: Reads `kAXSelectedTextAttribute` directly from the focused
///    accessibility element. No clipboard involvement, zero side-effects.
/// 2. **Clipboard fallback**: Saves the current clipboard, simulates ⌘C via CGEvent,
///    reads the new clipboard content, then restores the original clipboard after
///    a short delay. Used when AX returns nothing (some apps don't expose selections).
///
/// Usage:
/// ```swift
/// if let info = await SelectedTextExtractor.extract() {
///     print("Selected: \(info.text) via \(info.method)")
/// }
/// ```
final class SelectedTextExtractor {

    // MARK: - Public API

    /// Extract the currently-selected text from whatever app has focus.
    ///
    /// Tries the Accessibility API first; falls back to clipboard-based extraction
    /// if AX returns nothing. Returns `nil` when no text is selected or extraction
    /// fails entirely (graceful degradation).
    @MainActor
    static func extract() async -> SelectedTextInfo? {
        // Strategy 1: AX (no side-effects)
        if let result = extractViaAX() {
            return result
        }

        // Strategy 2: Clipboard fallback
        return await extractViaClipboard()
    }

    // MARK: - AX Extraction

    /// Read selected text directly from the focused accessibility element.
    @MainActor
    private static func extractViaAX() -> SelectedTextInfo? {
        let systemWide = AXUIElementCreateSystemWide()

        // Get the focused UI element
        var focusedElement: AnyObject?
        let err = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard err == .success else {
            print("📝 AX: no focused element (\(err.rawValue))")
            return nil
        }

        let element = focusedElement as! AXUIElement

        // Read selected text
        var selectedText: AnyObject?
        let textErr = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedText
        )
        guard textErr == .success,
              let text = selectedText as? String,
              !text.isEmpty else {
            print("📝 AX: no selected text (\(textErr.rawValue))")
            return nil
        }

        // Read selected range (best-effort)
        var rangeValue: AnyObject?
        let range: NSRange? = {
            let rangeErr = AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                &rangeValue
            )
            guard rangeErr == .success,
                  let axValue = rangeValue else { return nil }

            // AXSelectedTextRange is returned as an AXValue containing an CFRange
            var cfRange = CFRange()
            guard AXValueGetValue(axValue as! AXValue, .cfRange, &cfRange) else { return nil }
            return NSRange(location: cfRange.location, length: cfRange.length)
        }()

        print("📝 AX: extracted \(text.count) chars")
        return SelectedTextInfo(text: text, range: range, method: .ax)
    }

    // MARK: - Clipboard Fallback

    /// Extract selected text by saving the clipboard, simulating ⌘C, reading the result,
    /// then restoring the original clipboard content.
    ///
    /// Total operation should complete in under 200 ms.
    @MainActor
    private static func extractViaClipboard() async -> SelectedTextInfo? {
        let pasteboard = NSPasteboard.general

        // Snapshot current clipboard contents for restoration
        let savedContents = pasteboard.data(forType: .string)
        let savedChangeCount = pasteboard.changeCount

        // Clear pasteboard so we can detect when new content arrives
        pasteboard.clearContents()

        // Simulate Cmd+C
        simulateCopy()

        // Wait briefly for the copy to complete
        try? await Task.sleep(for: .milliseconds(100))

        // Read new clipboard
        guard let copiedText = pasteboard.string(forType: .string),
              !copiedText.isEmpty else {
            print("📝 Clipboard: no text after Cmd+C")
            restoreClipboard(savedContents: savedContents, savedChangeCount: savedChangeCount)
            return nil
        }

        // Schedule clipboard restoration after a short delay (non-blocking)
        scheduleClipboardRestore(savedContents: savedContents, savedChangeCount: savedChangeCount)

        print("📝 Clipboard: extracted \(copiedText.count) chars")
        return SelectedTextInfo(text: copiedText, range: nil, method: .clipboard)
    }

    // MARK: - Clipboard Helpers

    /// Simulate ⌘C (copy) via CGEvent key events.
    private static func simulateCopy() {
        let source = CGEventSource(stateID: .hidSystemState)

        // Key down: Cmd + C
        let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_ANSI_C),
            keyDown: true
        )
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        // Key up: Cmd + C
        let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_ANSI_C),
            keyDown: false
        )
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }

    /// Restore the clipboard to its previous state.
    private static func restoreClipboard(savedContents: Data?, savedChangeCount: Int) {
        let pasteboard = NSPasteboard.general

        // Only restore if the clipboard hasn't been changed by something else
        guard pasteboard.changeCount != savedChangeCount else { return }

        pasteboard.clearContents()
        if let data = savedContents {
            pasteboard.setData(data, forType: .string)
        }
        print("📝 Clipboard: restored original content")
    }

    /// Schedule clipboard restoration after a delay so the user doesn't
    /// see their clipboard wiped after a copy-based extraction.
    private static func scheduleClipboardRestore(savedContents: Data?, savedChangeCount: Int) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            restoreClipboard(savedContents: savedContents, savedChangeCount: savedChangeCount)
        }
    }
}
