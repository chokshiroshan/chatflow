import Foundation

/// Manages launching Flow at login via a LaunchAgent plist.
///
/// Uses the modern ServiceManagement framework approach (macOS 13+).
/// Falls back to manual LaunchAgent plist creation.
final class AutoStartManager {
    static let shared = AutoStartManager()

    private let launcherIdentifier = "ai.flow.app.launcher"
    private let launchAgentPath: URL

    private init() {
        launchAgentPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(launcherIdentifier).plist")
    }

    var isEnabled: Bool {
        FileManager.default.fileExists(atPath: launchAgentPath.path)
    }

    /// Enable auto-start at login.
    func enable() throws {
        guard let executablePath = Bundle.main.executablePath else {
            throw AutoStartError.noBundle
        }

        let plist: [String: Any] = [
            "Label": launcherIdentifier,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false,
            "StandardOutPath": "/tmp/flow-launchd.log",
            "StandardErrorPath": "/tmp/flow-launchd-err.log",
        ]

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: launchAgentPath)
        print("✅ Auto-start enabled")
    }

    /// Disable auto-start at login.
    func disable() throws {
        if FileManager.default.fileExists(atPath: launchAgentPath.path) {
            try FileManager.default.removeItem(at: launchAgentPath)
        }
        print("✅ Auto-start disabled")
    }

    /// Toggle auto-start.
    func toggle() throws {
        if isEnabled {
            try disable()
        } else {
            try enable()
        }
    }
}

enum AutoStartError: LocalizedError {
    case noBundle

    var errorDescription: String? {
        switch self {
        case .noBundle: return "Could not find app bundle path"
        }
    }
}
