import Foundation

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
}

// MARK: - Auth State

enum AuthState: Equatable {
    case signedOut
    case signingIn
    case signedIn(email: String, plan: String)
    case error(String)
}

// MARK: - Usage Tracking

/// Tracks dictation usage stats, persisted to ~/.flow/usage.json
final class UsageTracker {
    static let shared = UsageTracker()
    private let url = FlowConfig.configDir.appendingPathComponent("usage.json")

    struct Stats: Codable {
        var totalSessions: Int = 0
        var totalSeconds: Double = 0
        var monthSessions: Int = 0
        var monthSeconds: Double = 0
        var monthKey: String = ""  // "2026-04" format

        var monthMinutesDisplay: String {
            let mins = Int(monthSeconds / 60)
            if mins < 1 { return "< 1 min transcribed" }
            return "~\(mins) min transcribed"
        }
    }

    private(set) var stats = Stats()

    private init() { load() }

    func recordSession(durationSeconds: Double) {
        stats.totalSessions += 1
        stats.totalSeconds += durationSeconds

        let now = Calendar.current.component(.year, from: Date()) * 100 + Calendar.current.component(.month, from: Date())
        let key = String(now)
        if stats.monthKey != key {
            stats.monthKey = key
            stats.monthSessions = 0
            stats.monthSeconds = 0
        }
        stats.monthSessions += 1
        stats.monthSeconds += durationSeconds
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Stats.self, from: data) else { return }
        stats = decoded
    }

    private func save() {
        try? FileManager.default.createDirectory(at: FlowConfig.configDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(stats) {
            try? data.write(to: url)
        }
    }
}

// MARK: - Configuration

struct FlowConfig: Codable {
    var hotkey: String = "ctrl+space"
    var hotkeyMode: HotkeyMode = .hold
    var language: String = "en"
    var realtimeModel: String = "gpt-realtime"
    var injectMethod: InjectMethod = .clipboard
    var soundEffectsEnabled: Bool = true
    var autoPasteEnabled: Bool = true
    var appearance: String = "system"
    var selectedMicDeviceUID: String? = nil

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
