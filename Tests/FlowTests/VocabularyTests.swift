import XCTest
@testable import Flow

// MARK: - VocabularyManager Tests

final class VocabularyManagerTests: XCTestCase {

    private var tempDir: URL!
    private var vocabURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("flow_test_vocab_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        vocabURL = tempDir.appendingPathComponent("vocabulary.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Entry Management

    func testAddEntry() {
        let mgr = VocabularyManager()
        mgr.entries = []
        let entry = mgr.addEntry(original: "wispr", correction: "Wispr")
        XCTAssertEqual(entry.original, "wispr")
        XCTAssertEqual(entry.correction, "Wispr")
        XCTAssertEqual(mgr.entries.count, 1)
    }

    func testAddEntryNormalizesToLowercase() {
        let mgr = VocabularyManager()
        mgr.entries = []
        let entry = mgr.addEntry(original: "WISPR", correction: "WisprFlow")
        XCTAssertEqual(entry.original, "wispr")  // Stored lowercase
        XCTAssertEqual(entry.correction, "WisprFlow")
    }

    func testUpdateExistingEntry() {
        let mgr = VocabularyManager()
        mgr.entries = []
        _ = mgr.addEntry(original: "wispr", correction: "Wispr")
        let updated = mgr.addEntry(original: "wispr", correction: "WisprFlow")
        XCTAssertEqual(updated.correction, "WisprFlow")
        XCTAssertEqual(updated.hitCount, 1)  // Incremented on update
        XCTAssertEqual(mgr.entries.count, 1)  // Not duplicated
    }

    func testRemoveEntry() {
        let mgr = VocabularyManager()
        mgr.entries = []
        _ = mgr.addEntry(original: "wispr", correction: "Wispr")
        XCTAssertEqual(mgr.entries.count, 1)
        mgr.removeEntry(original: "wispr")
        XCTAssertTrue(mgr.entries.isEmpty)
    }

    func testRemoveEntryCaseInsensitive() {
        let mgr = VocabularyManager()
        mgr.entries = []
        _ = mgr.addEntry(original: "wispr", correction: "Wispr")
        mgr.removeEntry(original: "WISPR")
        XCTAssertTrue(mgr.entries.isEmpty)
    }

    func testLookup() {
        let mgr = VocabularyManager()
        mgr.entries = []
        _ = mgr.addEntry(original: "kubernetes", correction: "Kubernetes")
        let found = mgr.lookup("kubernetes")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.correction, "Kubernetes")
    }

    func testLookupCaseInsensitive() {
        let mgr = VocabularyManager()
        mgr.entries = []
        _ = mgr.addEntry(original: "Kubernetes", correction: "K8s")
        let found = mgr.lookup("KUBERNETES")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.correction, "K8s")
    }

    func testLookupNotFound() {
        let mgr = VocabularyManager()
        mgr.entries = []
        XCTAssertNil(mgr.lookup("nonexistent"))
    }

    // MARK: - Significance Filtering

    func testSignificantCorrection() {
        let mgr = VocabularyManager()
        XCTAssertTrue(mgr.isSignificantCorrection(original: "wispr", corrected: "WisprFlow"))
        XCTAssertTrue(mgr.isSignificantCorrection(original: "kuber netes", corrected: "Kubernetes"))
        XCTAssertTrue(mgr.isSignificantCorrection(original: "openclaw", corrected: "OpenClaw"))
    }

    func testTrivialCaseOnly() {
        let mgr = VocabularyManager()
        // Case-only change should be filtered
        XCTAssertFalse(mgr.isSignificantCorrection(original: "hello", corrected: "Hello"))
        XCTAssertFalse(mgr.isSignificantCorrection(original: "WISPR", corrected: "wispr"))
    }

    func testTrivialShortWords() {
        let mgr = VocabularyManager()
        XCTAssertFalse(mgr.isSignificantCorrection(original: "a", corrected: "the"))
        XCTAssertFalse(mgr.isSignificantCorrection(original: "an", corrected: "and"))
    }

    func testTrivialPunctuationOnly() {
        let mgr = VocabularyManager()
        // Just punctuation — trimming makes them empty
        XCTAssertFalse(mgr.isSignificantCorrection(original: "!", corrected: "."))
        XCTAssertFalse(mgr.isSignificantCorrection(original: "", corrected: "hello"))
    }

    func testTrivialCompleteRewrite() {
        let mgr = VocabularyManager()
        // Completely different words — too far apart
        XCTAssertFalse(mgr.isSignificantCorrection(original: "hello", corrected: "goodbye"))
        XCTAssertFalse(mgr.isSignificantCorrection(original: "cat", corrected: "dog"))
    }

    func testEdgeCaseSameWord() {
        let mgr = VocabularyManager()
        XCTAssertFalse(mgr.isSignificantCorrection(original: "hello", corrected: "hello"))
    }

    // MARK: - Levenshtein Distance

    func testLevenshteinIdentical() {
        XCTAssertEqual(VocabularyManager.levenshtein("hello", "hello"), 0)
    }

    func testLevenshteinEmpty() {
        XCTAssertEqual(VocabularyManager.levenshtein("", "abc"), 3)
        XCTAssertEqual(VocabularyManager.levenshtein("abc", ""), 3)
    }

    func testLevenshteinSingleEdit() {
        XCTAssertEqual(VocabularyManager.levenshtein("cat", "cats"), 1)  // insertion
        XCTAssertEqual(VocabularyManager.levenshtein("cats", "cat"), 1)  // deletion
        XCTAssertEqual(VocabularyManager.levenshtein("cat", "bat"), 1)  // substitution
    }

    func testLevenshteinMultipleEdits() {
        XCTAssertEqual(VocabularyManager.levenshtein("kitten", "sitting"), 3)
        XCTAssertEqual(VocabularyManager.levenshtein("saturday", "sunday"), 3)
    }

    // MARK: - Prompt Snippet

    func testBuildPromptSnippet() {
        let mgr = VocabularyManager()
        mgr.entries = []
        XCTAssertNil(mgr.buildPromptSnippet())  // Empty

        _ = mgr.addEntry(original: "wispr", correction: "WisprFlow")
        _ = mgr.addEntry(original: "kuber netes", correction: "Kubernetes")

        let snippet = mgr.buildPromptSnippet()
        XCTAssertNotNil(snippet)
        XCTAssertTrue(snippet!.contains("wispr"))
        XCTAssertTrue(snippet!.contains("WisprFlow"))
    }

    func testBuildPromptSnippetLimit50() {
        let mgr = VocabularyManager()
        mgr.entries = []
        for i in 0..<60 {
            mgr.entries.append(VocabEntry(original: "word\(i)", correction: "Word\(i)"))
        }
        let snippet = mgr.buildPromptSnippet()
        XCTAssertNotNil(snippet)
        // Should only include first 50
        // Count occurrences of "should be written as"
        let count = snippet!.components(separatedBy: "should be written as").count - 1
        XCTAssertEqual(count, 50)
    }
}

// MARK: - DictatedTextEditWatcher Tests

final class DictatedTextEditWatcherTests: XCTestCase {

    private var watcher: DictatedTextEditWatcher!

    override func setUp() {
        super.setUp()
        watcher = DictatedTextEditWatcher()
        watcher.watchDuration = 5  // Short for tests
        watcher.pollInterval = 0.1  // Fast polling for tests
    }

    override func tearDown() {
        watcher.stopWatching()
        super.tearDown()
    }

    // MARK: - Word Change Computation

    func testComputeWordChangesSingleSubstitution() {
        let changes = watcher.computeWordChanges(
            original: "I love using wispr flow for dictation",
            edited: "I love using WisprFlow for dictation"
        )
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].original, "wispr")
        XCTAssertEqual(changes[0].corrected, "WisprFlow")
    }

    func testComputeWordChangesMultipleSubstitutions() {
        let changes = watcher.computeWordChanges(
            original: "deploy to kuber netes using teraform",
            edited: "deploy to Kubernetes using Terraform"
        )
        // "kuber" -> "Kubernetes", "netes" -> ??? (might be absorbed), "teraform" -> "Terraform"
        XCTAssertTrue(changes.count >= 1, "Should detect at least 1 change")

        // Check that teraform -> Terraform is detected
        let terraformChange = changes.first { $0.original.lowercased() == "teraform" }
        XCTAssertNotNil(terraformChange, "Should detect teraform → Terraform")
    }

    func testComputeWordChangesNoChange() {
        let changes = watcher.computeWordChanges(
            original: "hello world this is a test",
            edited: "hello world this is a test"
        )
        XCTAssertTrue(changes.isEmpty)
    }

    func testComputeWordChangesCaseOnly() {
        // Case-only changes should be filtered out as insignificant
        let changes = watcher.computeWordChanges(
            original: "hello world",
            edited: "Hello World"
        )
        XCTAssertTrue(changes.isEmpty, "Case-only changes should not be suggested")
    }

    func testComputeWordChangesInsertion() {
        let changes = watcher.computeWordChanges(
            original: "I went to the store",
            edited: "I went to the grocery store"
        )
        // "grocery" was inserted — not a correction, should not be suggested
        // because there's no original word to correct from
        XCTAssertTrue(changes.isEmpty, "Pure insertions should not generate suggestions")
    }

    func testComputeWordChangesDeletion() {
        let changes = watcher.computeWordChanges(
            original: "I went to the big store",
            edited: "I went to the store"
        )
        // "big" was deleted — not a correction
        XCTAssertTrue(changes.isEmpty, "Pure deletions should not generate suggestions")
    }

    func testComputeWordChangesComplexEdit() {
        let changes = watcher.computeWordChanges(
            original: "openclaw is a great platform for agents",
            edited: "OpenClaw is a great platform for AI agents"
        )
        // "openclaw" -> "OpenClaw" is case-only (filtered)
        // "AI" was inserted — not a correction
        XCTAssertTrue(changes.isEmpty, "Case-only and insertions should be filtered")
    }

    // MARK: - Alignment

    func testAlignWordsIdentical() {
        let (orig, edit) = watcher.alignWords(
            ["hello", "world"],
            ["hello", "world"]
        )
        XCTAssertEqual(orig.count, edit.count)
        XCTAssertEqual(orig.count, 2)
        XCTAssertEqual(orig[0]!, "hello")
        XCTAssertEqual(edit[0]!, "hello")
    }

    func testAlignWordsWithInsertion() {
        let (orig, edit) = watcher.alignWords(
            ["hello", "world"],
            ["hello", "beautiful", "world"]
        )
        XCTAssertEqual(orig.count, edit.count)
        // Should have a nil for the inserted "beautiful"
        let inserted = zip(orig, edit).first { $0.0 == nil && $0.1 == "beautiful" }
        XCTAssertNotNil(inserted, "Should detect 'beautiful' as an insertion")
    }

    func testAlignWordsWithDeletion() {
        let (orig, edit) = watcher.alignWords(
            ["hello", "beautiful", "world"],
            ["hello", "world"]
        )
        XCTAssertEqual(orig.count, edit.count)
        let deleted = zip(orig, edit).first { $0.0 == "beautiful" && $0.1 == nil }
        XCTAssertNotNil(deleted, "Should detect 'beautiful' as a deletion")
    }

    func testAlignWordsWithSubstitution() {
        let (orig, edit) = watcher.alignWords(
            ["use", "wispr", "flow"],
            ["use", "WisprFlow", "now"]
        )
        XCTAssertEqual(orig.count, edit.count)
        // "wispr" -> "WisprFlow" should be aligned as a substitution
        let subIdx = orig.firstIndex { $0 == "wispr" }
        XCTAssertNotNil(subIdx)
        XCTAssertEqual(edit[subIdx!], "WisprFlow")
    }

    // MARK: - Text Extraction

    func testExtractDictatedPortionWithAnchors() {
        watcher.originalTranscript = "hello world"
        watcher.originalBeforeCursor = "prefix "
        watcher.originalAfterCursor = " suffix"

        let result = watcher.extractDictatedPortion(from: "prefix hello world suffix")
        XCTAssertEqual(result, "hello world")
    }

    func testExtractDictatedPortionWithEditedMiddle() {
        watcher.originalTranscript = "hello world"
        watcher.originalBeforeCursor = "prefix "
        watcher.originalAfterCursor = " suffix"

        let result = watcher.extractDictatedPortion(from: "prefix hello earth suffix")
        XCTAssertEqual(result, "hello earth")
    }

    func testExtractDictatedPortionNoAnchors() {
        watcher.originalTranscript = "hello world"
        watcher.originalBeforeCursor = ""
        watcher.originalAfterCursor = ""

        let result = watcher.extractDictatedPortion(from: "hello earth")
        XCTAssertEqual(result, "hello earth")
    }

    func testExtractDictatedPortionOnlyBeforeAnchor() {
        watcher.originalTranscript = "hello world"
        watcher.originalBeforeCursor = "prefix "
        watcher.originalAfterCursor = ""

        let result = watcher.extractDictatedPortion(from: "prefix hello earth")
        XCTAssertEqual(result, "hello earth")
    }

    func testExtractDictatedPortionOnlyAfterAnchor() {
        watcher.originalTranscript = "hello world"
        watcher.originalBeforeCursor = ""
        watcher.originalAfterCursor = " suffix"

        let result = watcher.extractDictatedPortion(from: "hello earth suffix")
        XCTAssertEqual(result, "hello earth")
    }

    // MARK: - Normalization

    func testNormalizeForComparison() {
        let result = watcher.normalizeForComparison("Hello,  World! This is a TEST. ")
        XCTAssertEqual(result, "hello world this is a test")
    }

    func testTokenize() {
        let tokens = watcher.tokenize("hello world  this is\ta test")
        XCTAssertEqual(tokens, ["hello", "world", "this", "is", "a", "test"])
    }

    func testNormalizeWord() {
        XCTAssertEqual(watcher.normalizeWord("\"Hello!\""), "hello")
        XCTAssertEqual(watcher.normalizeWord("...World..."), "world")
        XCTAssertEqual(watcher.normalizeWord("TEST"), "test")
    }

    // MARK: - Lifecycle

    func testStartStopWatching() {
        // Can't fully test without AX, but verify no crash
        watcher.startWatching(transcript: "hello world")
        // Watcher is active but won't find a text field in test
        watcher.stopWatching()
        // No crash = pass
    }

    func testStopWhenNotWatching() {
        // Should not crash
        watcher.stopWatching()
    }

    func testStartWatchingEmptyTranscript() {
        // Should not start watching for empty transcript
        watcher.startWatching(transcript: "")
        // No crash = pass
    }
}

// MARK: - VocabEntry Tests

final class VocabEntryTests: XCTestCase {

    func testMatchesOriginalCaseInsensitive() {
        let entry = VocabEntry(original: "Wispr", correction: "WisprFlow")
        XCTAssertTrue(entry.matchesOriginal("wispr"))
        XCTAssertTrue(entry.matchesOriginal("WISPR"))
        XCTAssertTrue(entry.matchesOriginal("Wispr"))
    }

    func testMatchesOriginalNoMatch() {
        let entry = VocabEntry(original: "wispr", correction: "WisprFlow")
        XCTAssertFalse(entry.matchesOriginal("other"))
    }

    func testEntryEquality() {
        let entry1 = VocabEntry(original: "test", correction: "Test")
        let entry2 = VocabEntry(original: "test", correction: "Test")
        // Same content but different createdAt — still equal via Equatable
        XCTAssertEqual(entry1, entry2)
    }
}

// MARK: - EditDiff Tests

final class EditDiffTests: XCTestCase {

    func testEmptyDiffHasNoSignificantChanges() {
        let diff = EditDiff(changes: [])
        XCTAssertFalse(diff.hasSignificantChanges)
    }

    func testNonEmptyDiffHasSignificantChanges() {
        let diff = EditDiff(changes: [
            EditDiff.WordChange(original: "wispr", corrected: "WisprFlow", position: 0)
        ])
        XCTAssertTrue(diff.hasSignificantChanges)
    }
}
