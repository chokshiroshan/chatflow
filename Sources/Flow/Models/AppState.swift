import Foundation

// MARK: - App Mode

/// The two main modes of Flow.
enum AppMode: String, CaseIterable, Codable {
    case dictation = "Dictation"
    case voiceChat = "Voice Chat"
}

// MARK: - App State

/// The current operational state of the app.
enum FlowState: Equatable {
    case idle
    case connecting
    case recording
    case processing
    case injecting
    case speaking
    case error(String)

    var isRecording: Bool { self == .recording }
    var isActive: Bool { self != .idle && !isError }
    var isError: Bool { if case .error = self { return true }; return false }

    var icon: String {
        switch self {
        case .idle: return "🎤"
        case .connecting: return "🔄"
        case .recording: return "🔴"
        case .processing: return "⏳"
        case .injecting: return "📝"
        case .speaking: return "🔊"
        case .error: return "❌"
        }
    }
}

// MARK: - Auth State

enum AuthState: Equatable {
    case signedOut
    case signingIn
    case signedIn(email: String, plan: String)
    case error(String)
}

// MARK: - Configuration

struct FlowConfig: Codable {
    var hotkey: String = "ctrl+space"
    var hotkeyMode: HotkeyMode = .hold
    var language: String = "en"
    var realtimeModel: String = "gpt-realtime"
    var preferredMode: AppMode = .dictation
    var injectMethod: InjectMethod = .clipboard
    var voiceChatVoice: String = "alloy"

    enum HotkeyMode: String, Codable, CaseIterable {
        case hold
        case toggle
    }

    enum InjectMethod: String, Codable, CaseIterable {
        case clipboard
        case accessibility
        case keystrokes
    }

    static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".flow")
    static let configPath = configDir.appendingPathComponent("config.json")

    static func load() -> FlowConfig {
        guard let data = try? Data(contentsOf: configPath),
              let config = try? JSONDecoder().decode(FlowConfig.self, from: data) else {
            return FlowConfig()
        }
        return config
    }

    func save() {
        try? FileManager.default.createDirectory(at: Self.configDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(self) {
            try? data.write(to: Self.configPath)
        }
    }
}
