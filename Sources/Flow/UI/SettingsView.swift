import SwiftUI

struct SettingsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var autoStartEnabled = AutoStartManager.shared.isEnabled

    var body: some View {
        TabView {
            generalView
                .tabItem { Label("General", systemImage: "gear") }

            hotkeyView
                .tabItem { Label("Hotkey", systemImage: "keyboard") }

            aboutView
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 420, height: 300)
    }

    // MARK: - General

    @ViewBuilder
    private var generalView: some View {
        Form {
            Picker("Default Mode", selection: $coordinator.config.preferredMode) {
                ForEach(AppMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
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
                Text("Portuguese").tag("pt")
                Text("Italian").tag("it")
                Text("Dutch").tag("nl")
            }

            Picker("Model", selection: $coordinator.config.realtimeModel) {
                Text("gpt-realtime (recommended)").tag("gpt-realtime")
            }

            Toggle("Launch at Login", isOn: $autoStartEnabled)
                .onChange(of: autoStartEnabled) { _, newValue in
                    do { try AutoStartManager.shared.toggle() } catch { }
                }
        }
        .padding()
    }

    // MARK: - Hotkey

    @ViewBuilder
    private var hotkeyView: some View {
        Form {
            Picker("Trigger Key", selection: $coordinator.config.hotkey) {
                Text("Ctrl+Space").tag("ctrl+space")
                Text("Cmd+Shift+D").tag("cmd+shift+d")
                Text("Ctrl+D").tag("ctrl+d")
                Text("Right ⌘").tag("rightcmd")
                Text("Right ⌥").tag("rightopt")
                Text("Fn / Globe").tag("fn")
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

            Section {
                HStack {
                    Text("Shortcuts")
                        .font(.headline)
                    Spacer()
                }
                LabeledContent("Dictation", value: coordinator.config.hotkey)
                LabeledContent("Settings", value: "⌘,")
                LabeledContent("Quit", value: "⌘Q")
            }
        }
        .padding()
    }

    // MARK: - About

    @ViewBuilder
    private var aboutView: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            Text("Flow")
                .font(.title)
                .bold()
            Text("Voice dictation & chat powered by ChatGPT")
                .foregroundStyle(.secondary)
            Text("v1.0.0")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Divider()

            Text("Free with your ChatGPT subscription.")
                .font(.callout)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
