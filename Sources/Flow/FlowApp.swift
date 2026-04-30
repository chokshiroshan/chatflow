import SwiftUI
import Darwin

@main
struct FlowApp: App {
    @StateObject private var coordinator = AppCoordinator()

    init() {
        // Start log collection (rotates daily, keeps 7 days)
        _ = LogCollector.shared

        // Single-instance guard using file lock
        // Uses flock via FileHandle for reliable release on process exit
        let lockPath = NSTemporaryDirectory() + "chatflow.singleton.lock"
        let lockFD = open(lockPath, O_RDWR | O_CREAT, 0o644)
        if lockFD >= 0 {
            // flock is automatically released when the process exits (even on crash/force-quit)
            if flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
                print("⚠️ Another instance of ChatFlow is already running. Exiting.")
                close(lockFD)
                exit(1)
            }
            // Keep FD open — lock holds as long as process is alive
        }
    }

    var body: some Scene {
        // Menu bar presence — stateful compact label, no dock icon
        MenuBarExtra {
            MenuView(coordinator: coordinator)
                .preferredColorScheme(.dark)
        } label: {
            MenuBarLabel(coordinator: coordinator)
        }
        .menuBarExtraStyle(.window)

        // Settings
        Settings {
            SettingsView(coordinator: coordinator)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            if shortText != nil {
                Text(shortText!)
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .help(tooltip)
    }

    private var symbol: String {
        switch coordinator.state {
        case .idle: return "waveform"
        case .connecting: return "bolt.horizontal.circle"
        case .recording: return "record.circle.fill"
        case .processing: return "ellipsis.circle.fill"
        case .injecting: return "checkmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }

    private var shortText: String? {
        switch coordinator.state {
        case .recording: return "REC"
        case .processing: return "…"
        case .injecting: return "OK"
        case .error: return "ERR"
        default: return nil
        }
    }

    private var tooltip: String {
        switch coordinator.state {
        case .idle: return "ChatFlow — Ready"
        case .connecting: return "ChatFlow — Connecting"
        case .recording: return "ChatFlow — Recording"
        case .processing: return "ChatFlow — Transcribing"
        case .injecting: return "ChatFlow — Injecting text"
        case .error(let msg): return "ChatFlow — Error: \(msg)"
        }
    }
}
