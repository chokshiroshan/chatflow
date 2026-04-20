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

        // Voice chat window (hidden by default, shown when voice chat active)
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
    }
}
