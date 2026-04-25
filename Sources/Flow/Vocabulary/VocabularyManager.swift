import Foundation

/// A single vocabulary entry — maps a misrecognized word to the user's correction.
struct VocabEntry: Codable, Equatable {
    /// What the STT model produced (the "wrong" word)
    let original: String
    /// What the user corrected it to (the "right" word)
    let correction: String
    /// When this entry was created
    let createdAt: Date
    /// How many times this correction has been applied/suggested
    var hitCount: Int

    init(original: String, correction: String, createdAt: Date = Date(), hitCount: Int = 0) {
        self.original = original.lowercased()
        self.correction = correction
        self.createdAt = createdAt
        self.hitCount = hitCount
    }

    /// For matching purposes — case-insensitive comparison on original
    func matchesOriginal(_ word: String) -> Bool {
        original == word.lowercased()
    }
}

/// Manages a persistent vocabulary of word corrections.
///
/// Stores entries in `~/.flow/vocabulary.json`. These corrections serve two purposes:
/// 1. Injected into the transcription prompt so the STT model learns the correct words
/// 2. Used as auto-correction hints when the same misrecognition happens again
///
/// File format (JSON):
/// ```json
/// {
///   "entries": [
///     { "original": "wispr", "correction": "Wispr", "createdAt": "...", "hitCount": 3 }
///   ]
/// }
/// ```
final class VocabularyManager {
    static let shared = VocabularyManager()

    private let fileURL: URL
    private(set) var entries: [VocabEntry] = []

    struct Store: Codable {
        var entries: [VocabEntry]
    }

    // MARK: - Init & Load

    private init() {
        fileURL = FlowConfig.configDir.appendingPathComponent("vocabulary.json")
        load()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let store = try? JSONDecoder().decode(Store.self, from: data) else {
            entries = []
            return
        }
        entries = store.entries
        if !entries.isEmpty {
            print("📖 Loaded \(entries.count) vocabulary entries")
        }
    }

    func save() {
        try? FileManager.default.createDirectory(
            at: FlowConfig.configDir,
            withIntermediateDirectories: true
        )
        let store = Store(entries: entries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(store) {
            try? data.write(to: fileURL)
        }
    }

    // MARK: - CRUD

    /// Add a new vocabulary entry. If the original word already exists, update the correction.
    @discardableResult
    func addEntry(original: String, correction: String) -> VocabEntry {
        let normalizedOriginal = original.lowercased()

        // Update existing entry if it exists
        if let idx = entries.firstIndex(where: { $0.original == normalizedOriginal }) {
            entries[idx].correction = correction
            entries[idx].hitCount += 1
            save()
            print("📖 Updated vocabulary: \(normalizedOriginal) → \(correction) (hits: \(entries[idx].hitCount))")
            return entries[idx]
        }

        // New entry
        let entry = VocabEntry(original: normalizedOriginal, correction: correction)
        entries.append(entry)
        save()
        print("📖 Added vocabulary: \(normalizedOriginal) → \(correction)")
        return entry
    }

    /// Remove an entry by its original word.
    func removeEntry(original: String) {
        let normalizedOriginal = original.lowercased()
        entries.removeAll { $0.original == normalizedOriginal }
        save()
    }

    /// Look up a correction for a given word. Returns nil if not in vocabulary.
    func lookup(_ word: String) -> VocabEntry? {
        entries.first { $0.matchesOriginal(word) }
    }

    /// Build a prompt snippet for STT context injection.
    /// Returns something like: "The user prefers: 'wispr' should be written as 'Wispr', ..."
    func buildPromptSnippet() -> String? {
        guard !entries.isEmpty else { return nil }

        let hints = entries.prefix(50).map { entry in
            "'\(entry.original)' should be written as '\(entry.correction)'"
        }
        return "The user prefers these spellings: " + hints.joined(separator: ", ") + "."
    }

    /// Check if a correction is meaningful enough to suggest saving.
    ///
    /// Filters out trivial changes like case-only differences, punctuation,
    /// very short words, and words that are too similar.
    func isSignificantCorrection(original: String, corrected: String) -> Bool {
        let orig = original.trimmingCharacters(in: .whitespacesAndPunctuation)
        let corr = corrected.trimmingCharacters(in: .whitespacesAndPunctuation)

        // Skip empty
        guard !orig.isEmpty, !corr.isEmpty else { return false }

        // Skip if they're the same (case-insensitive)
        guard orig.lowercased() != corr.lowercased() else { return false }

        // Skip very short words (< 3 chars) — too likely to be noise
        guard orig.count >= 3, corr.count >= 3 else { return false }

        // Skip if edit distance is too small relative to word length
        // (e.g., "cats" → "cat's" is not a meaningful vocabulary correction)
        let distance = Self.levenshtein(orig.lowercased(), corr.lowercased())
        let maxLen = max(orig.count, corr.count)
        let normalizedDistance = Double(distance) / Double(maxLen)

        // Skip if > 80% of the word changed — probably a full rewrite, not a correction
        guard normalizedDistance < 0.8 else { return false }

        // Skip if edit distance is 0 (case-only change) — already handled above but safety check
        guard distance > 0 else { return false }

        return true
    }

    // MARK: - Levenshtein Distance

    /// Compute the Levenshtein edit distance between two strings.
    static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a)
        let b = Array(b)
        let aCount = a.count
        let bCount = b.count

        if aCount == 0 { return bCount }
        if bCount == 0 { return aCount }

        var matrix = [[Int]](
            repeating: [Int](repeating: 0, count: bCount + 1),
            count: aCount + 1
        )

        for i in 0...aCount { matrix[i][0] = i }
        for j in 0...bCount { matrix[0][j] = j }

        for i in 1...aCount {
            for j in 1...bCount {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }

        return matrix[aCount][bCount]
    }
}
