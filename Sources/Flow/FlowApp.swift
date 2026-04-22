import SwiftUI

@main
struct FlowApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        // Menu bar presence — stateful compact label, no dock icon
        MenuBarExtra {
            MenuView(coordinator: coordinator)
        } label: {
            MenuBarLabel(coordinator: coordinator)
        }
        .menuBarExtraStyle(.window)

        // Settings
        Settings {
            SettingsView(coordinator: coordinator)
        }

        // ChatFlow landing (matches web design)
        Window("ChatFlow", id: "chatflow") {
            ChatFlowLandingView(onStart: { coordinator.completeOnboarding() })
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultSize(width: 520, height: 480)
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
        case .idle: return "Flow — Ready"
        case .connecting: return "Flow — Connecting"
        case .recording: return "Flow — Recording"
        case .processing: return "Flow — Transcribing"
        case .injecting: return "Flow — Injecting text"
        case .error(let msg): return "Flow — Error: \(msg)"
        case .speaking: return "Flow — Active"
        }
    }
}
