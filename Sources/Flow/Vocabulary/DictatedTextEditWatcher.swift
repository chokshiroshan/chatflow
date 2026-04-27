import Foundation
import ApplicationServices

/// Result of comparing original dictated text against the edited version.
struct EditDiff: Equatable {
    /// Individual word-level changes detected
    let changes: [WordChange]

    /// Whether any significant changes were detected
    var hasSignificantChanges: Bool { !changes.isEmpty }

    struct WordChange: Equatable {
        /// The word as dictated (original)
        let original: String
        /// The word as edited (correction)
        let corrected: String
        /// Position in the original text (word index)
        let position: Int
    }
}

/// Watches the text field after dictation to detect user edits.
///
/// Inspired by WisprFlow's EditAnalysis / BoundaryEdit detection:
/// 1. After text is pasted, we snapshot the text field content
/// 2. We poll the text field periodically (for ~30 seconds)
/// 3. When the content changes, we diff the original transcript against the current content
/// 4. We extract word-level changes (not character-level — too noisy)
/// 5. We filter trivial changes (whitespace, punctuation, case)
/// 6. We surface significant corrections for the user to save to vocabulary
///
/// Thread safety: All AX calls happen on the main thread.
@MainActor
final class DictatedTextEditWatcher {
    static let shared = DictatedTextEditWatcher()

    /// Callback when significant edits are detected. Returns word-level diffs.
    var onEditsDetected: (([EditDiff.WordChange], String) -> Void)?

    /// Callback when watching starts/stops
    var onStateChanged: ((Bool) -> Void)?

    /// How long to watch for edits after dictation (seconds)
    var watchDuration: TimeInterval = 30.0

    /// How often to poll the text field (seconds)
    var pollInterval: TimeInterval = 1.0

    private var timer: Timer?
    private var isWatching = false
    private var originalTranscript: String = ""
    private var originalBeforeCursor: String = ""
    private var originalAfterCursor: String = ""
    private var startTime: Date = .distantPast
    private var lastSeenContent: String = ""
    private var firedForCurrentContent = false  // Prevent duplicate fires

    private init() {}

    // MARK: - Public API

    /// Start watching for edits after dictation completes.
    ///
    /// - Parameters:
    ///   - transcript: The text that was dictated and pasted
    ///   - beforeCursor: Text that was in the field before the cursor (before dictation)
    ///   - afterCursor: Text that was after the cursor (before dictation)
    func startWatching(transcript: String, beforeCursor: String = "", afterCursor: String = "") {
        guard !transcript.isEmpty else { return }
        guard AXIsProcessTrusted() else {
            print("📖 AX not trusted — skipping edit watch")
            return
        }

        stopWatching()  // Cancel any existing watch

        originalTranscript = transcript
        originalBeforeCursor = beforeCursor
        originalAfterCursor = afterCursor
        lastSeenContent = ""
        firedForCurrentContent = false
        startTime = Date()
        isWatching = true
        onStateChanged?(true)

        print("📖 Started watching for edits (\(Int(watchDuration))s window)")

        // Poll periodically
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollForEdits()
            }
        }
    }

    /// Stop watching (e.g., when new dictation starts).
    func stopWatching() {
        timer?.invalidate()
        timer = nil
        if isWatching {
            isWatching = false
            onStateChanged?(false)
            print("📖 Stopped watching for edits")
        }
    }

    // MARK: - Private

    private func pollForEdits() {
        guard isWatching else { return }

        // Check timeout
        let elapsed = Date().timeIntervalSince(startTime)
        guard elapsed < watchDuration else {
            print("📖 Edit watch timed out (\(Int(elapsed))s)")
            stopWatching()
            return
        }

        // Read current text field
        guard let currentContents = readCurrentTextField() else {
            // Lost focus — keep watching, user might click back
            return
        }

        // Skip if unchanged since last poll
        guard currentContents != lastSeenContent else { return }

        // First poll — just record the current state (paste might not have propagated yet)
        if lastSeenContent.isEmpty {
            print("📖 First poll: recording initial content (\(currentContents.count) chars)")
            lastSeenContent = currentContents
            return
        }

        print("📖 Content changed: \(currentContents.count) chars")
        lastSeenContent = currentContents

        // Extract just the dictated portion from the current content
        guard let editedTranscript = extractDictatedPortion(from: currentContents) else {
            print("📖 Could not locate dictated portion in current content")
            return
        }

        print("📖 Extracted dictated portion: '\(editedTranscript)'")

        // Skip if it's identical to original
        let normalizedOriginal = normalizeForComparison(originalTranscript)
        let normalizedEdited = normalizeForComparison(editedTranscript)

        guard normalizedEdited != normalizedOriginal else {
            print("📖 No significant changes detected")
            return
        }

        // Already fired for this content? Skip
        if firedForCurrentContent { return }

        // Diff the words
        let changes = computeWordChanges(original: originalTranscript, edited: editedTranscript)
        guard !changes.isEmpty else {
            print("📖 Word diff found no significant changes")
            return
        }

        firedForCurrentContent = true
        print("📖 Detected \(changes.count) word edit(s): \(changes.map { "\($0.original)→\($0.corrected)" })")

        // Fire callback
        onEditsDetected?(changes, originalTranscript)
    }

    /// Read the current focused text field contents via AX.
    private func readCurrentTextField() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        ) == .success else {
            return nil
        }

        let element = focusedElement as! AXUIElement
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        ) == .success else {
            return nil
        }

        if let str = value as? String { return str }
        if let attr = value as? NSAttributedString { return attr.string }
        return nil
    }

    /// Extract the dictated portion from the current text field content.
    ///
    /// The content is: beforeCursor + [DICTATED TEXT] + afterCursor
    /// We need to find and return just the [DICTATED TEXT] part.
    private func extractDictatedPortion(from currentContents: String) -> String? {
        let contentLen = currentContents.count
        print("📖 extractDictated: content=\(contentLen) chars, before='\(originalBeforeCursor.debugDescription)' (\(originalBeforeCursor.count)), after='\(originalAfterCursor.debugDescription)' (\(originalAfterCursor.count)), transcript=\(originalTranscript.count) chars")

        // Guard against reading a completely wrong field (terminal, huge document)
        // If content is way longer than expected, we're probably reading the wrong element
        let expectedMaxLen = originalBeforeCursor.count + originalTranscript.count + originalAfterCursor.count + 50
        if contentLen > expectedMaxLen * 3 {
            print("📖 extractDictated: content too large (\(contentLen) > \(expectedMaxLen * 3)), likely wrong field")
            return nil
        }

        // Strategy 1: Exact match with before/after anchors
        if !originalBeforeCursor.isEmpty && currentContents.hasPrefix(originalBeforeCursor) {
            let afterDictated = currentContents.dropFirst(originalBeforeCursor.count)
            if originalAfterCursor.isEmpty {
                let result = String(afterDictated)
                print("📖 Strategy 1a (before anchor only): '\(result)'")
                return result
            } else if let afterRange = afterDictated.range(of: originalAfterCursor) {
                let result = String(afterDictated[..<afterRange.lowerBound])
                print("📖 Strategy 1b (both anchors): '\(result)'")
                return result
            }
        }

        // Strategy 2: Just afterCursor anchor
        if !originalAfterCursor.isEmpty, let afterRange = currentContents.range(of: originalAfterCursor) {
            let beforeAfter = String(currentContents[..<afterRange.lowerBound])
            if !originalBeforeCursor.isEmpty && beforeAfter.hasSuffix(originalBeforeCursor) {
                let result = String(beforeAfter.dropFirst(originalBeforeCursor.count))
                print("📖 Strategy 2 (after anchor, suffix match): '\(result)'")
                return result
            }
            // No beforeCursor anchor — return everything before afterCursor
            let result = beforeAfter
            print("📖 Strategy 2 (after anchor only): '\(result)'")
            return result
        }

        // Strategy 3: Search for longest common substring between original and current
        // This handles cases where anchors shifted or were removed during editing
        let normalizedCurrent = currentContents.lowercased()
        let normalizedOriginal = originalTranscript.lowercased()

        // Try multiple search windows from the original
        let searchWindows = [
            normalizedOriginal.suffix(max(normalizedOriginal.count / 2, 3)),
            normalizedOriginal.prefix(max(normalizedOriginal.count / 2, 3))
        ]
        for window in searchWindows {
            let searchStr = String(window)
            if !searchStr.isEmpty && normalizedCurrent.contains(searchStr) {
                print("📖 Strategy 3 (substring match: '\(searchStr.prefix(20))...'): returning full content")
                // Found a partial match — extract the best guess
                // For chat inputs, the whole content minus leading/trailing whitespace is close enough
                let trimmed = currentContents.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed
            }
        }

        // Strategy 4: Short field with trivial anchors (whitespace only)
        // In a chat input, the whole field IS essentially the transcript
        let beforeIsTrivial = originalBeforeCursor.allSatisfy { $0.isWhitespace }
        let afterIsTrivial = originalAfterCursor.allSatisfy { $0.isWhitespace }
        if beforeIsTrivial && afterIsTrivial && contentLen <= expectedMaxLen * 2 {
            let trimmed = currentContents.trimmingCharacters(in: .whitespacesAndNewlines)
            print("📖 Strategy 4 (trivial anchors, short field): '\(trimmed)'")
            return trimmed
        }

        // Strategy 5: Both anchors empty
        if originalBeforeCursor.isEmpty && originalAfterCursor.isEmpty {
            print("📖 Strategy 5 (no anchors): returning full content")
            return currentContents
        }

        print("📖 All strategies failed")
        return nil
    }

    /// Compute word-level changes between original and edited transcript.
    ///
    /// Uses a word-level diff that handles insertions, deletions, and substitutions.
    /// Filters out trivial changes (case-only, punctuation).
    func computeWordChanges(original: String, edited: String) -> [EditDiff.WordChange] {
        let originalWords = tokenize(original)
        let editedWords = tokenize(edited)

        // Guard against empty arrays — LCS would crash on 1...0 range
        guard !originalWords.isEmpty, !editedWords.isEmpty else {
            return []
        }

        var changes: [EditDiff.WordChange] = []

        // Use LCS (Longest Common Subsequence) to align words
        let (rawOrigAligned, rawEditAligned) = alignWords(originalWords, editedWords)

        // Post-process: merge adjacent (word, nil) + (nil, word) into (word, word) substitutions.
        // LCS treats a word change as deletion + insertion — we need to pair them for comparison.
        var origAligned: [String?] = []
        var editAligned: [String?] = []
        var i = 0
        while i < rawOrigAligned.count {
            let o = rawOrigAligned[i]
            let e = rawEditAligned[i]

            if o != nil && e == nil && i + 1 < rawOrigAligned.count {
                let nextO = rawOrigAligned[i + 1]
                let nextE = rawEditAligned[i + 1]
                // Pattern: (word, nil) followed by (nil, word) → merge into (word, word)
                if nextO == nil && nextE != nil {
                    origAligned.append(o)
                    editAligned.append(nextE)
                    i += 2
                    continue
                }
            } else if o == nil && e != nil && i + 1 < rawOrigAligned.count {
                let nextO = rawOrigAligned[i + 1]
                let nextE = rawEditAligned[i + 1]
                // Pattern: (nil, word) followed by (word, nil) → merge into (word, word)
                if nextO != nil && nextE == nil {
                    origAligned.append(nextO)
                    editAligned.append(e)
                    i += 2
                    continue
                }
            }

            origAligned.append(o)
            editAligned.append(e)
            i += 1
        }

        for (i, (orig, edit)) in zip(origAligned, editAligned).enumerated() {
            guard let o = orig, let e = edit else { continue }

            // Skip if normalized versions are the same
            let oNorm = normalizeWord(o)
            let eNorm = normalizeWord(e)
            if oNorm == eNorm { continue }

            // Check if this is a significant correction
            if VocabularyManager.shared.isSignificantCorrection(original: o, corrected: e) {
                changes.append(EditDiff.WordChange(
                    original: o,
                    corrected: e,
                    position: i
                ))
            }
        }

        return changes
    }

    // MARK: - Tokenization & Normalization

    /// Tokenize a string into words, preserving enough structure for alignment.
    private func tokenize(_ text: String) -> [String] {
        // Split on whitespace, keeping punctuation attached to words
        return text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }

    /// Normalize a word for comparison (lowercase, strip punctuation).
    private func normalizeWord(_ word: String) -> String {
        word.lowercased()
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Normalize full text for comparison.
    private func normalizeForComparison(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Word Alignment (LCS-based)

    /// Align two word sequences using LCS, producing paired optional words.
    ///
    /// Returns two arrays of equal length. Each position has either:
    /// - (Some(orig), Some(edit)) — matched or substituted
    /// - (Some(orig), None) — deleted word
    /// - (None, Some(edit)) — inserted word
    private func alignWords(_ original: [String], _ edited: [String]) -> ([String?], [String?]) {
        let m = original.count
        let n = edited.count

        // Defensive: handle edge cases
        if m == 0 {
            return ([String?](repeating: nil, count: n), edited.map { Optional($0) })
        }
        if n == 0 {
            return (original.map { Optional($0) }, [String?](repeating: nil, count: m))
        }

        // LCS DP table
        var dp = [[Int]](
            repeating: [Int](repeating: 0, count: n + 1),
            count: m + 1
        )

        for i in 1...m {
            for j in 1...n {
                if normalizeWord(original[i - 1]) == normalizeWord(edited[j - 1]) {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to produce alignment
        var origAligned: [String?] = []
        var editAligned: [String?] = []
        var i = m
        var j = n

        while i > 0 || j > 0 {
            if i > 0 && j > 0 && normalizeWord(original[i - 1]) == normalizeWord(edited[j - 1]) {
                origAligned.append(original[i - 1])
                editAligned.append(edited[j - 1])
                i -= 1
                j -= 1
            } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                origAligned.append(nil)
                editAligned.append(edited[j - 1])
                j -= 1
            } else {
                origAligned.append(original[i - 1])
                editAligned.append(nil)
                i -= 1
            }
        }

        return (origAligned.reversed(), editAligned.reversed())
    }
}
