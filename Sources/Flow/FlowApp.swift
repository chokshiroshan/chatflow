import SwiftUI

@main
struct FlowApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        // Menu bar presence — icon only, no dock icon
        MenuBarExtra {
            MenuView(coordinator: coordinator)
        } label: {
            Image(systemName: menuBarSymbol)
                .help(menuBarTooltip)
        }
        .menuBarExtraStyle(.window)

        // Settings
        Settings {
            SettingsView(coordinator: coordinator)
        }

        // Onboarding (shown on first launch or missing permissions)
        Window("Welcome to Flow", id: "onboarding") {
            OnboardingView(onComplete: { coordinator.completeOnboarding() })
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultSize(width: 420, height: 440)
    }

    private var menuBarSymbol: String {
        switch coordinator.state {
        case .idle: return "waveform"
        case .connecting: return "dot.radiowaves.left.and.right"
        case .recording: return "record.circle.fill"
        case .processing: return "ellipsis.circle"
        case .injecting: return "checkmark.circle"
        case .error: return "exclamationmark.circle"
        case .speaking: return "speaker.wave.2"
        }
    }

    private var menuBarTooltip: String {
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
