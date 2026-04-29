import SwiftUI

@main
struct FlowApp: App {
    @StateObject private var coordinator = AppCoordinator()

    init() {
        // Single-instance guard — prevent duplicate processes
        let lockPath = NSTemporaryDirectory() + "chatflow.singleton.lock"
        let distributedLock = NSDistributedLock(path: lockPath)
        if distributedLock?.try() == false {
            print("⚠️ Another instance of ChatFlow is already running. Exiting.")
            // Force exit — can't use NSApp.terminate here since app hasn't launched yet
            exit(1)
        }
        // Never unlock — lock released when process exits
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
                .onAppear {
                    // Move settings window to the active screen (not always main display)
                    if let window = NSApp.windows.first(where: { $0.title == "ChatFlow Settings" || String(describing: $0.contentView).contains("SettingsView") }) {
                        let mouseScreen = NSScreen.screenWithMouse ?? NSScreen.main!
                        window.setFrameOrigin(NSPoint(
                            x: mouseScreen.visibleFrame.midX - window.frame.width / 2,
                            y: mouseScreen.visibleFrame.midY + window.frame.height / 2
                        ))
                    }
                }
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
        case .speaking: return "speaker.wave.2.fill"
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
        case .speaking: return "ChatFlow — Active"
        }
    }
}
