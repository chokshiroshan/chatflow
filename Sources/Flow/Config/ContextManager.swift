import Foundation
import AppKit

/// Manages user context for improving transcription accuracy.
///
/// Loads from `~/.flow/context.md` — a markdown file the user edits with
/// personal context like names, technical terms, project names, etc.
/// This gets injected into the Realtime API session instructions so the
/// transcription model knows the user's vocabulary.
///
/// Caches the file content with a 5-second staleness window to avoid
/// re-reading from disk on every instruction build.
final class ContextManager {
    static let shared = ContextManager()

    private let contextFilePath: URL
    private(set) var context: String = ""
    private var lastLoadTime: Date = .distantPast
    private let cacheTTL: TimeInterval = 5.0  // Reload at most every 5s

    private init() {
        contextFilePath = FlowConfig.configDir.appendingPathComponent("context.md")
    }

    /// Load context from file. Returns the raw context string.
    /// Uses a 5-second cache to avoid hitting disk on every call.
    @discardableResult
    func load() -> String {
        // Skip reload if cached recently
        if Date().timeIntervalSince(lastLoadTime) < cacheTTL && !context.isEmpty {
            return context
        }
        lastLoadTime = Date()
        guard FileManager.default.fileExists(atPath: contextFilePath.path),
              let data = try? Data(contentsOf: contextFilePath),
              let text = String(data: data, encoding: .utf8) else {
            // Create default context file if it doesn't exist
            if !FileManager.default.fileExists(atPath: contextFilePath.path) {
                createDefault()
            }
            context = ""
            return ""
        }

        // Strip markdown headers and comments, keep content lines
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                // Skip empty lines, headers (we'll format ourselves), and comments
                !line.isEmpty && !line.hasPrefix("#") && !line.hasPrefix("<!--")
            }
            .map { line in
                // Clean up bullet points
                var cleaned = line
                if cleaned.hasPrefix("- ") { cleaned = String(cleaned.dropFirst(2)) }
                if cleaned.hasPrefix("* ") { cleaned = String(cleaned.dropFirst(2)) }
                return cleaned
            }

        context = lines.joined(separator: ". ")
        if !context.isEmpty {
            print("📋 Loaded \(lines.count) context entries from ~/.flow/context.md")
        }
        return context
    }

    /// Build the full instructions string with context injected.
    /// Reloads context from file at most every 5 seconds (cached).
    func buildInstructions(basePrompt: String? = nil, screenContext: String? = nil, textContext: String? = nil, config: FlowConfig = FlowConfig.load()) -> String {
        load() // Cached — only hits disk if >5s since last read

        let prompt = basePrompt ?? config.systemInstructions
        var parts = [prompt]

        // Add user context if available
        if config.includeUserContext && !context.isEmpty {
            parts.append("User context (use this to correctly transcribe names, terms, and abbreviations):\(context)")
        }

        // Add vocabulary corrections
        if config.includeVocabulary, let vocabSnippet = VocabularyManager.shared.buildPromptSnippet() {
            parts.append(vocabSnippet)
        }

        // Add active app context (what the user is currently looking at)
        if config.includeAppContext, let app = Self.frontmostApp() {
            parts.append("The user is currently in \(app). Use this to interpret ambiguous words.")
        }

        // NOTE: text field context now goes into input_audio_transcription.prompt
        //       NOT here in instructions — it's more effective in the dedicated STT field
        //       screen context goes into conversation.item.create system messages

        return parts.joined(separator: " ")
    }

    // MARK: - Active App Detection

    /// Get the name of the frontmost macOS application.
    private static func frontmostApp() -> String? {
        // Use NSWorkspace directly — fast, no subprocess
        guard let app = NSWorkspace.shared.frontmostApplication?.localizedName else {
            return nil
        }
        return app
    }

    /// Save new content to the context file.
    func save(_ newContext: String) throws {
        try? FileManager.default.createDirectory(
            at: FlowConfig.configDir,
            withIntermediateDirectories: true
        )
        try newContext.write(to: contextFilePath, atomically: true, encoding: .utf8)
        load()
    }

    /// Append a line to the context file.
    func append(_ line: String) throws {
        let current = (try? String(contentsOf: contextFilePath, encoding: .utf8)) ?? ""
        let updated = current.hasSuffix("\n") ? "\(current)\(line)\n" : "\(current)\n\(line)\n"
        try save(updated)
    }

    // MARK: - Default Context

    private func createDefault() {
        let defaultContent = """
        # Flow Context
        # 
        # Add your personal context below to improve transcription accuracy.
        # Names, technical terms, project names, abbreviations — anything you say often.
        # Lines starting with # are comments and won't be used.
        #
        # Examples:
        # - My name is Roshan, I work on OpenClaw and Flow
        # - Coworkers: Alice, Bob, Charlie
        # - Projects: ChatFlow, OpenClaw, Wispr
        # - Tech: Kubernetes, Terraform, WebSocket, PCM16
        # - Apps I mention: Discord, VS Code, Figma, Notion
        # - I say "omw" for "on my way"
        #
        # Add yours below:
        
        """
        try? defaultContent.write(to: contextFilePath, atomically: true, encoding: .utf8)
        print("📋 Created default context file at ~/.flow/context.md")
    }
}
