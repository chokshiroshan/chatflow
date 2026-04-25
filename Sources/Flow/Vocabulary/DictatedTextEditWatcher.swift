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
        lastSeenContent = currentContents

        // First poll — just record the current state (paste might not have propagated yet)
        if lastSeenContent.isEmpty {
            lastSeenContent = currentContents
            return
        }

        // Extract just the dictated portion from the current content
        // The full content = beforeCursor + transcript + afterCursor
        // We need to find and isolate the transcript portion
        guard let editedTranscript = extractDictatedPortion(from: currentContents) else {
            // Can't locate the dictated text — probably user switched fields
            return
        }

        // Skip if it's identical to original
        let normalizedOriginal = normalizeForComparison(originalTranscript)
        let normalizedEdited = normalizeForComparison(editedTranscript)

        guard normalizedEdited != normalizedOriginal else { return }

        // Already fired for this content? Skip
        if firedForCurrentContent { return }

        // Diff the words
        let changes = computeWordChanges(original: originalTranscript, edited: editedTranscript)
        guard !changes.isEmpty else { return }

        firedForCurrentContent = true
        print("📖 Detected \(changes.count) word edit(s): \(changes.map { "\($0.original)→\($0.corrected)" })")

        // Fire callback
        onEditsDetected?(changes, originalTranscript)

        // Don't stop watching — user might make more edits
        // But we do stop if they already saw the popup
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
        // Strategy 1: Exact match with before/after anchors
        if !originalBeforeCursor.isEmpty && currentContents.hasPrefix(originalBeforeCursor) {
            let afterDictated = currentContents.dropFirst(originalBeforeCursor.count)
            if originalAfterCursor.isEmpty {
                return String(afterDictated)
            } else if let afterRange = afterDictated.range(of: originalAfterCursor) {
                return String(afterDictated[..<afterRange.lowerBound])
            }
        }

        // Strategy 2: Just afterCursor anchor
        if !originalAfterCursor.isEmpty, let afterRange = currentContents.range(of: originalAfterCursor) {
            let beforeAfter = String(currentContents[..<afterRange.lowerBound])
            if !originalBeforeCursor.isEmpty && beforeAfter.hasSuffix(originalBeforeCursor) {
                return String(beforeAfter.dropFirst(originalBeforeCursor.count))
            }
            // No beforeCursor anchor — return everything before afterCursor
            // This might include non-dictated text, but it's the best we can do
            return beforeAfter
        }

        // Strategy 3: No anchors — look for the original transcript in the current content
        // If we find a partial match, the text has been edited but partially remains
        let normalizedCurrent = currentContents.lowercased()
        let normalizedOriginal = originalTranscript.lowercased()
        let searchLength = max(normalizedOriginal.count / 2, 1)
        let searchStr = String(normalizedOriginal.prefix(searchLength))
        if normalizedCurrent.contains(searchStr) {
            // Found a partial match — the text has been edited but partially remains
            // Return the whole content as the edited version
            return currentContents
        }

        // Strategy 4: Fallback — if before/after are both empty, the entire content IS the transcript
        if originalBeforeCursor.isEmpty && originalAfterCursor.isEmpty {
            return currentContents
        }

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
        let (origAligned, editAligned) = alignWords(originalWords, editedWords)

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
