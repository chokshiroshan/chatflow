import Foundation
import ApplicationServices
import CoreGraphics

/// Structured context about what's in the currently focused text field.
///
/// When the user triggers dictation, we snapshot the text field contents
/// around the cursor so the transcription model can:
/// - Match tone/style of existing text
/// - Know what "this" or "that" refers to
/// - Support "continue from cursor" by knowing what's already written
struct TextContext {
    /// Text before the cursor position
    let beforeCursor: String
    /// Text after the cursor position
    let afterCursor: String
    /// Currently selected/highlighted text (if any)
    let selectedText: String
    /// Full contents of the text field
    let fullContents: String

    /// Whether there's any meaningful context to use
    var isEmpty: Bool {
        fullContents.isEmpty && selectedText.isEmpty
    }

    /// A compact summary suitable for injection into session instructions
    var summary: String {
        var parts: [String] = []
        if !beforeCursor.isEmpty {
            // Only include last ~200 chars of beforeCursor for relevance + token efficiency
            let snippet = beforeCursor.suffix(200)
            parts.append("Text before cursor: \"\(snippet)\"")
        }
        if !afterCursor.isEmpty {
            let snippet = String(afterCursor.prefix(200))
            parts.append("Text after cursor: \"\(snippet)\"")
        }
        if !selectedText.isEmpty {
            parts.append("Selected text: \"\(selectedText)\"")
        }
        return parts.joined(separator: ". ")
    }
}

/// Monitors the currently focused text field to capture context before dictation.
///
/// Unlike WisprFlow's continuous monitoring approach (which watches text changes
/// in real-time with AX observers), we take a simpler snapshot approach:
/// - Only reads the text field when dictation starts
/// - No background observers or timers
/// - Gracefully degrades when AX access is unavailable
///
/// This gives us the "what text is already there" context for smarter transcription
/// without the complexity and resource cost of continuous monitoring.
///
/// Requires: Accessibility permission (System Settings → Privacy → Accessibility)
@MainActor
final class EditedTextManager {
    static let shared = EditedTextManager()

    /// The most recently captured text context (nil if never captured or failed)
    private(set) var lastContext: TextContext?

    /// Whether accessibility access appears to be available
    private var axAvailable: Bool {
        AXIsProcessTrusted()
    }

    private init() {}

    // MARK: - Public API

    /// Snapshot the currently focused text field and return structured context.
    ///
    /// Call this when dictation starts to capture what the user was already typing.
    /// Returns nil if:
    /// - Accessibility permission not granted
    /// - No text field is focused
    /// - The focused element doesn't support text access
    func getTextContext() -> TextContext? {
        guard axAvailable else {
            print("📝 AX not available — skipping text context capture")
            return nil
        }

        let systemWide = AXUIElementCreateSystemWide()

        // Get the focused UI element
        var focusedElement: AnyObject?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard focusedResult == .success else {
            print("📝 No focused element — skipping text context")
            return nil
        }

        let element = focusedElement as! AXUIElement

        // Read the text field value
        guard let fullContents = getTextFieldValue(element) else {
            print("📝 Focused element has no text value — skipping text context")
            return nil
        }

        // Get cursor position / selection
        let (before, after, selected) = getCursorContext(element: element, fullText: fullContents)

        let context = TextContext(
            beforeCursor: before,
            afterCursor: after,
            selectedText: selected,
            fullContents: fullContents
        )

        lastContext = context

        if !context.isEmpty {
            print("📝 Text context captured: \(fullContents.count) chars, selected: \(selected.count), before: \(before.count), after: \(after.count)")
        } else {
            print("📝 Text field is empty — no context to use")
        }

        return context
    }

    /// Build an instruction snippet from current text context for injection.
    ///
    /// Returns a string suitable for appending to session instructions,
    /// or nil if there's no useful context.
    func buildContextInstructions() -> String? {
        guard let ctx = getTextContext(), !ctx.isEmpty else {
            return nil
        }

        var instructions = "The user is dictating into a text field that already has content. "

        if !ctx.selectedText.isEmpty {
            instructions += "The user has selected \"\(ctx.selectedText)\" — they may want to replace it. "
        }

        if !ctx.beforeCursor.isEmpty {
            let snippet = String(ctx.beforeCursor.suffix(150))
            instructions += "Text before cursor: \"\(snippet)\". "
        }

        if !ctx.afterCursor.isEmpty {
            let snippet = String(ctx.afterCursor.prefix(150))
            instructions += "Text after cursor: \"\(snippet)\". "
        }

        instructions += "Match the style and tone of existing text. If the user says something like \"continue\" or \"keep going\", append naturally to what's already there."

        return instructions
    }

    /// Check if the text at the cursor position has changed since we captured context.
    ///
    /// Used after dictation to detect if the user manually edited the text
    /// (e.g., deleted the inserted text) — similar to WisprFlow's
    /// "Text no longer starts/ends with before/after text" detection.
    func detectManualEdit(originalContext: TextContext, insertedText: String) -> Bool {
        guard axAvailable else { return false }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        ) == .success else { return false }

        let element = focusedElement as! AXUIElement
        guard let currentContents = getTextFieldValue(element) else { return false }

        let originalBefore = originalContext.beforeCursor
        let originalAfter = originalContext.afterCursor

        // Check if the text before cursor is still intact
        let beforeIntact = originalBefore.isEmpty || currentContents.hasPrefix(originalBefore)

        // Check if the text after cursor (after inserted text) is still intact
        let expectedAfterInsertion = originalBefore + insertedText + originalAfter
        let afterIntact = originalAfter.isEmpty || currentContents.hasSuffix(originalAfter)

        // If either part changed, the user likely made a manual edit
        if !beforeIntact || !afterIntact {
            print("📝 Manual edit detected: beforeIntact=\(beforeIntact), afterIntact=\(afterIntact)")
            return true
        }

        return false
    }

    // MARK: - AXUIElement Helpers

    /// Read the value (text contents) of a UI element.
    ///
    /// Handles both standard text fields and special cases like:
    /// - Elements that return NSAttributedString
    /// - Composite elements with nested text areas
    /// - Static text elements (read-only display)
    private func getTextFieldValue(_ element: AXUIElement) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        )

        guard result == .success else { return nil }

        // Standard string value
        if let stringValue = value as? String {
            return stringValue
        }

        // Attributed string — extract the plain text
        if let attrString = value as? NSAttributedString {
            return attrString.string
        }

        // Some apps use a nested text area (e.g., Slack, Electron apps)
        // Try to get the value from a child AXTextArea or AXTextField
        var children: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
           let childArray = children as? [AXUIElement] {
            for child in childArray {
                // Check role of the child
                var role: AnyObject?
                if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role) == .success,
                   let roleStr = role as? String {
                    // Look for text-editable roles
                    if roleStr == "AXTextArea" || roleStr == "AXTextField" || roleStr == "AXComboBox" {
                        var childValue: AnyObject?
                        if AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &childValue) == .success,
                           let text = childValue as? String {
                            return text
                        }
                    }
                }
            }
        }

        return nil
    }

    /// Get the cursor position and any selected text from the focused element.
    ///
    /// Returns a tuple of (beforeCursor, afterCursor, selectedText).
    /// Falls back to the Cmd+A → Cmd+C approach if AXSelectedTextRange isn't available.
    private func getCursorContext(element: AXUIElement, fullText: String) -> (before: String, after: String, selected: String) {
        // Strategy 1: Use AXSelectedTextRange (most accurate)
        let rangeResult = getSelectedRange(element: element)
        if let range = rangeResult {
            return splitTextAroundRange(fullText: fullText, range: range, element: element)
        }

        // Strategy 2: Try AXSelectedText directly
        var selectedTextObj: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextObj) == .success,
           let selectedText = selectedTextObj as? String, !selectedText.isEmpty {
            // We know what's selected but not where — search for it
            if let range = fullText.range(of: selectedText) {
                let nsRange = NSRange(range, in: fullText)
                return (
                    String(fullText[..<range.lowerBound]),
                    String(fullText[range.upperBound...]),
                    selectedText
                )
            }
            // Can't locate it — just return the selected text
            return ("", fullText, selectedText)
        }

        // Strategy 3: Cursor might be at the end (no selection)
        // Try AXInsertionPointLineNumber as a hint, or default to end of text
        var insertionPoint: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXInsertionPointLineNumberAttribute as CFString, &insertionPoint) == .success {
            // There is a cursor — we just don't know where exactly
            // Default to end of text as most common dictation position
            return (fullText, "", "")
        }

        // Strategy 4: Fallback — assume cursor at end
        // (Most common dictation scenario: user is appending)
        return (fullText, "", "")
    }

    /// Get the selected text range as a CFRange.
    private func getSelectedRange(element: AXUIElement) -> CFRange? {
        var selection: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selection
        ) == .success else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(selection as! AXValue, .cfRange, &range) else {
            return nil
        }

        return range
    }

    /// Split text around a CFRange, returning (before, after, selected).
    private func splitTextAroundRange(fullText: String, range: CFRange, element: AXUIElement) -> (before: String, after: String, selected: String) {
        let nsString = fullText as NSString

        // Clamp range to valid bounds
        let loc = max(0, min(range.location, nsString.length))
        let end = min(loc + range.length, nsString.length)
        let safeRange = NSRange(location: loc, length: end - loc)

        let before = nsString.substring(with: NSRange(location: 0, length: safeRange.location))
        let selected = nsString.substring(with: safeRange)
        let after = nsString.substring(with: NSRange(location: safeRange.location + safeRange.length, length: nsString.length - safeRange.location - safeRange.length))

        return (before, after, selected)
    }
}
