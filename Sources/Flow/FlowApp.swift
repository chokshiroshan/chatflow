import SwiftUI

@main
struct FlowApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        // Menu bar presence — no dock icon
        MenuBarExtra("Flow", systemImage: "mic.fill") {
            MenuView(coordinator: coordinator)
        }
        .menuBarExtraStyle(.window)

        // Voice chat window
        Window("Voice Chat", id: "voice-chat") {
            VoiceChatView(coordinator: coordinator)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

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
}
