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
    /// Wispr Flow-inspired: rich context-aware instructions that adapt output per app.
    func buildInstructions(config: FlowConfig = FlowConfig.load()) -> String {
        var parts = [config.systemInstructions]

        // Add user context (survives template switches)
        if !config.userContext.isEmpty {
            parts.append("User context — always use these spellings: \(config.userContext)")
        }

        // Add vocabulary corrections
        if config.includeVocabulary, let vocabSnippet = VocabularyManager.shared.buildPromptSnippet() {
            parts.append(vocabSnippet)
        }

        // Add rich app-specific context with formatting rules
        if config.includeAppContext, let app = Self.frontmostApp() {
            let appRules = Self.appFormattingRules(app)
            parts.append(appRules)
        }

        // NOTE: text field context now goes into input_audio_transcription.prompt
        //       NOT here in instructions — it's more effective in the dedicated STT field
        //       screen context goes into conversation.item.create system messages

        return parts.joined(separator: " ")
    }

    // MARK: - App-Specific Formatting

    /// Return formatting instructions tailored to the active app.
    private static func appFormattingRules(_ app: String) -> String {
        let lower = app.lowercased()

        // Chat/messaging apps — casual, minimal punctuation
        if ["discord", "slack", "telegram", "messages", "imessage", "whatsapp", "signal", "messenger", "teams", "irc"].contains(where: { lower.contains($0) }) {
            return "Active app: \(app). This is a chat app — keep output casual and conversational. Light punctuation (mostly just periods at sentence end). No capitalization enforcement unless it's a proper noun. Preserve abbreviations (lol, omg, tbh, idk). Keep it natural — like texting a friend."
        }

        // Code editors — technical, preserve syntax
        if ["xcode", "vscode", "code", "vim", "nvim", "emacs", "sublime", "cursor", "windsurf", "zed", "fleet", "intellij", "android studio"].contains(where: { lower.contains($0) }) {
            return "Active app: \(app). This is a code editor — output should be technical and precise. Preserve code syntax keywords literally (def, function, class, return, import, const, let, var). Keep variable names in camelCase or snake_case as spoken. If the user dictates code, format it as valid code. Don't add periods at the end of code lines."
        }

        // Terminal/shell — raw, technical
        if ["terminal", "iterm", "warp", "hyper", "kitty", "alacritty", "ghostty"].contains(where: { lower.contains($0) }) {
            return "Active app: \(app). This is a terminal — output should be raw and technical. Preserve command syntax (flags like -a, --verbose). Keep paths and URLs literal. No trailing punctuation. Output exactly what would be typed."
        }

        // Email — formal, proper grammar
        if ["mail", "gmail", "outlook", "spark", "airmail", "thunderbird", "protonmail"].contains(where: { lower.contains($0) }) {
            return "Active app: \(app). This is an email client — use proper formal English. Complete sentences, proper grammar, correct punctuation. Capitalize appropriately. Format as readable prose."
        }

        // Document/note editors — clean prose
        if ["pages", "word", "docs", "notion", "obsidian", "bear", "ulysses", "ia writer", "typora", "markor"].contains(where: { lower.contains($0) }) {
            return "Active app: \(app). This is a document editor — output clean, well-formatted prose. Proper grammar and punctuation. Natural sentence structure. Preserve markdown formatting if the user dictates it (headers, lists, bold)."
        }

        // Default — balanced
        return "Active app: \(app). Use this to interpret ambiguous words and adjust output style."
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
