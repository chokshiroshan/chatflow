import SwiftUI

struct SettingsView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        TabView {
            GeneralSettingsView(coordinator: coordinator)
                .tabItem { Label("General", systemImage: "gear") }

            HotkeySettingsView(coordinator: coordinator)
                .tabItem { Label("Hotkey", systemImage: "keyboard") }
        }
        .frame(width: 400, height: 280)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        Form {
            Picker("Default Mode", selection: $coordinator.config.preferredMode) {
                ForEach(AppMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            Picker("Voice (Voice Chat)", selection: $coordinator.config.voiceChatVoice) {
                Text("Alloy").tag("alloy")
                Text("Echo").tag("echo")
                Text("Fable").tag("fable")
                Text("Onyx").tag("onyx")
                Text("Nova").tag("nova")
                Text("Shimmer").tag("shimmer")
            }

            Picker("Language (Dictation)", selection: $coordinator.config.language) {
                Text("English").tag("en")
                Text("Spanish").tag("es")
                Text("French").tag("fr")
                Text("German").tag("de")
                Text("Japanese").tag("ja")
                Text("Chinese").tag("zh")
                Text("Korean").tag("ko")
            }

            Picker("Model", selection: $coordinator.config.realtimeModel) {
                Text("gpt-realtime-1.5").tag("gpt-realtime-1.5")
                Text("gpt-4o-realtime-preview").tag("gpt-4o-realtime-preview-2024-12-17")
            }
        }
        .padding()
    }
}

struct HotkeySettingsView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        Form {
            Picker("Trigger Key", selection: $coordinator.config.hotkey) {
                Text("Fn / Globe").tag("fn")
                Text("Right ⌘").tag("rightcmd")
                Text("Right ⌥").tag("rightopt")
                Text("F5").tag("f5")
                Text("F6").tag("f6")
                Text("F7").tag("f7")
                Text("F8").tag("f8")
            }

            Picker("Mode", selection: $coordinator.config.hotkeyMode) {
                Text("Hold to talk").tag(FlowConfig.HotkeyMode.hold)
                Text("Toggle (press to start/stop)").tag(FlowConfig.HotkeyMode.toggle)
            }

            Picker("Text Injection", selection: $coordinator.config.injectMethod) {
                Text("Clipboard paste (most reliable)").tag(FlowConfig.InjectMethod.clipboard)
                Text("Accessibility API").tag(FlowConfig.InjectMethod.accessibility)
                Text("Keystroke simulation").tag(FlowConfig.InjectMethod.keystrokes)
            }
        }
        .padding()
    }
}
