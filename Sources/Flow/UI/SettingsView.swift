import SwiftUI

// MARK: - Settings Window

/// Settings window with sidebar navigation matching the web design.
/// Tabs: General, Shortcut, Microphone, Privacy, About
struct SettingsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var autoStartEnabled = AutoStartManager.shared.isEnabled
    @State private var selectedTab = "general"
    @State private var inputDevices: [AudioCapture.InputDevice] = AudioCapture.listInputDevices()

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            settingsSidebar

            // Content
            settingsContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 720, height: 560)
        .background(Color(red: 0.949, green: 0.957, blue: 0.973).opacity(0.82))
    }

    // MARK: - Sidebar

    private var settingsItems: [(String, String, String)] {
        [
            ("general", "General", "gear"),
            ("shortcut", "Shortcut", "keyboard"),
            ("mic", "Microphone", "mic.fill"),
            ("privacy", "Privacy", "shield.checkmark"),
            ("about", "About", "info.circle"),
        ]
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Traffic lights
            HStack(spacing: 7) {
                Circle().fill(Color(red: 1.0, green: 0.45, blue: 0.42)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 0.10, green: 0.76, blue: 0.20)).frame(width: 12, height: 12)
                Spacer()
                Text("Settings")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Nav items
            VStack(spacing: 2) {
                ForEach(settingsItems, id: \.0) { item in
                    Button(action: { withAnimation(.easeInOut(duration: 0.15)) { selectedTab = item.0 } }) {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedTab == item.0 ? Color(red: 0.0, green: 0.48, blue: 1.0) : Color.black.opacity(0.12))
                                    .frame(width: 28, height: 28)
                                Image(systemName: item.2)
                                    .font(.system(size: 13))
                                    .foregroundColor(selectedTab == item.0 ? .white : .black.opacity(0.5))
                            }
                            Text(item.1)
                                .font(.system(size: 13, weight: selectedTab == item.0 ? .semibold : .medium))
                                .foregroundColor(selectedTab == item.0 ? .black.opacity(0.9) : .black.opacity(0.65))
                            Spacer()
                        }
                        .padding(.vertical, 9)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selectedTab == item.0 ? Color.white.opacity(0.65) : .clear)
                        )
                        .shadow(color: selectedTab == item.0 ? .black.opacity(0.08) : .clear, radius: 4, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 10)

            Spacer()
        }
        .frame(width: 210)
        .background(Color(red: 0.82, green: 0.86, blue: 0.93).opacity(0.55))
    }

    // MARK: - Content

    @ViewBuilder
    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Section title
                Text(settingsItems.first(where: { $0.0 == selectedTab })?.1 ?? "General")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundColor(.black.opacity(0.88))
                    .padding(.bottom, 20)

                switch selectedTab {
                case "general": settingsGeneral
                case "shortcut": settingsShortcut
                case "mic": settingsMic
                case "privacy": settingsPrivacy
                case "about": settingsAbout
                default: settingsGeneral
                }
            }
            .padding(28)
        }
    }

    // MARK: - General

    private var settingsGeneral: some View {
        VStack(alignment: .leading, spacing: 24) {
            // App section
            settingsSection("App") {
                settingsToggleRow("Launch at login", isOn: $autoStartEnabled)
                    .onChange(of: autoStartEnabled) { _, _ in try? AutoStartManager.shared.toggle() }
                settingsToggleRow("Sound effects", isOn: $coordinator.config.soundEffectsEnabled)
                    .onChange(of: coordinator.config.soundEffectsEnabled) { _, _ in coordinator.config.save() }
                settingsToggleRow("Auto-paste after transcription", isOn: $coordinator.config.autoPasteEnabled, isLast: true)
                    .onChange(of: coordinator.config.autoPasteEnabled) { _, _ in coordinator.config.save() }
            }

            // Transcription section
            settingsSection("Transcription") {
                settingsPickerRow("Language", selection: $coordinator.config.language) {
                    Text("Auto-detect").tag("auto")
                    Text("English").tag("en")
                    Text("Spanish").tag("es")
                    Text("French").tag("fr")
                    Text("German").tag("de")
                    Text("Japanese").tag("ja")
                    Text("Chinese").tag("zh")
                }
                .onChange(of: coordinator.config.language) { _, _ in coordinator.config.save() }
                settingsPickerRow("Model", selection: .constant("Whisper-1"), isLast: true) {
                    Text("Whisper-1").tag("Whisper-1")
                }
            }

            // Appearance
            settingsSection("Appearance") {
                settingsPickerRow("Appearance", selection: $coordinator.config.appearance, isLast: true) {
                    Text("Match System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .onChange(of: coordinator.config.appearance) { _, newValue in
                    coordinator.config.save()
                    switch newValue {
                    case "light": NSApp.appearance = NSAppearance(named: .aqua)
                    case "dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
                    default:      NSApp.appearance = nil  // System default
                    }
                }
            }
        }
    }

    // MARK: - Shortcut

    private var settingsShortcut: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsSection("Hold to Record") {
                VStack(alignment: .leading, spacing: 16) {
                    // Shortcut pills
                    let shortcutOptions = [("Ctrl+Space", "ctrl+space"), ("Cmd+Shift+Space", "cmd+shift+space"), ("⌥ Space", "option+space"), ("Right ⌘", "rcmd")]
                    HStack(spacing: 10) {
                        ForEach(shortcutOptions, id: \.1) { display, value in
                            Button(action: { coordinator.updateHotkey(value) }) {
                                Text(display)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(coordinator.config.hotkey == value ? Color(red: 0.0, green: 0.48, blue: 1.0) : .black.opacity(0.7))
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(coordinator.config.hotkey == value ? Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.07) : Color.white.opacity(0.6))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(coordinator.config.hotkey == value ? Color(red: 0.0, green: 0.48, blue: 1.0) : Color.black.opacity(0.12), lineWidth: coordinator.config.hotkey == value ? 2 : 1.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            settingsSection("Behavior") {
                settingsToggleRow("Release to transcribe (hold mode)", isOn: .constant(true), isLast: true)
            }
        }
    }

    // MARK: - Microphone

    private var settingsMic: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsSection("Input Device") {
                settingsPickerRow("Microphone", selection: Binding(
                    get: { coordinator.config.selectedMicDeviceUID ?? "default" },
                    set: { newValue in
                        coordinator.config.selectedMicDeviceUID = newValue == "default" ? nil : newValue
                        coordinator.config.save()
                    }
                ), isLast: true) {
                    Text("System Default").tag("default")
                    ForEach(inputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
            }

            settingsSection("Input Level") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Live level (hold shortcut to test)")
                        .font(.system(size: 12))
                        .foregroundColor(.black.opacity(0.45))

                    // Level bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.black.opacity(0.08))
                                .frame(height: 8)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(LinearGradient(colors: [Color(red: 0.0, green: 0.48, blue: 1.0), Color(red: 0.35, green: 0.78, blue: 0.98)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * 0.65, height: 8)
                        }
                    }
                    .frame(height: 8)

                    // Wave bars
                    HStack(spacing: 2) {
                        ForEach(0..<40, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.3))
                                .frame(height: 20 + sin(Double(i) * 0.8) * 12)
                        }
                    }
                    .frame(height: 36)
                }
            }
        }
    }

    // MARK: - Privacy

    private var settingsPrivacy: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Privacy banner
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "shield.checkmark")
                    .font(.system(size: 22))
                    .foregroundColor(Color(red: 0.20, green: 0.78, blue: 0.35))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your audio stays private")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black.opacity(0.85))
                    Text("Audio is sent directly to OpenAI's Whisper API and deleted immediately after transcription. ChatFlow never stores, logs, or sees your recordings.")
                        .font(.system(size: 13))
                        .foregroundColor(.black.opacity(0.55))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.20, green: 0.78, blue: 0.35).opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(red: 0.20, green: 0.78, blue: 0.35).opacity(0.25), lineWidth: 0.5)
            )

            settingsSection("Data") {
                settingsToggleRow("Share anonymous analytics", isOn: .constant(false))
                settingsToggleRow("Send crash reports", isOn: .constant(true), isLast: true)
            }

            settingsSection("Permissions") {
                permissionRow(label: "Microphone access", granted: coordinator.permissionsStatus.microphone) {
                    PermissionsManager.shared.requestAccessibility()
                    coordinator.refreshPermissions()
                }
                permissionRow(label: "Accessibility (auto-paste)", granted: coordinator.permissionsStatus.accessibility) {
                    PermissionsManager.shared.openAccessibilitySettings()
                    coordinator.refreshPermissions()
                }
                permissionRow(label: "Input Monitoring", granted: coordinator.permissionsStatus.inputMonitoring, isLast: true) {
                    PermissionsManager.shared.openInputMonitoringSettings()
                    coordinator.refreshPermissions()
                }
            }
        }
    }

    // MARK: - About

    private var settingsAbout: some View {
        VStack(spacing: 0) {
            // App icon
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient(colors: [Color(red: 0.0, green: 0.48, blue: 1.0), Color(red: 0.35, green: 0.78, blue: 0.98)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 72, height: 72)
                    .shadow(color: Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.35), radius: 20, x: 0, y: 6)
                Image(systemName: "mic.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white)
            }

            Spacer().frame(height: 16)

            Text("ChatFlow")
                .font(.system(size: 20, weight: .heavy))
                .foregroundColor(.black.opacity(0.88))
            Text("Version 1.0.0 (Build 100)")
                .font(.system(size: 13))
                .foregroundColor(.black.opacity(0.4))

            Spacer().frame(height: 24)

            settingsSection("Account") {
                HStack {
                    Text("ChatGPT account")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.black.opacity(0.78))
                    Spacer()
                    if case .signedIn(let email, _) = coordinator.authState {
                        HStack(spacing: 6) {
                            Circle().fill(Color(red: 0.20, green: 0.78, blue: 0.35)).frame(width: 8, height: 8)
                            Text("Connected — \(email)")
                                .font(.system(size: 13))
                                .foregroundColor(.black.opacity(0.6))
                        }
                    } else {
                        Text("Not connected")
                            .font(.system(size: 13))
                            .foregroundColor(.black.opacity(0.4))
                    }
                }
                .padding(.vertical, 13)

                HStack {
                    Text("Usage this month")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.black.opacity(0.78))
                    Spacer()
                    Text(coordinator.usageDisplay)
                        .font(.system(size: 13))
                        .foregroundColor(.black.opacity(0.6))
                }
                .padding(.vertical, 13)
            }

            Spacer().frame(height: 24)

            settingsSection("Links") {
                settingsLinkRow("Release Notes")
                settingsLinkRow("Support")
                settingsLinkRow("Check for Updates", isLast: true)
            }
        }
    }

    // MARK: - Helper Views

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.black.opacity(0.38))
                .tracking(0.6)

            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.black.opacity(0.09), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 1)
        }
    }

    private func settingsToggleRow(_ label: String, isOn: Binding<Bool>, isLast: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.black.opacity(0.78))
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
                    .padding(.leading, 0)
            }
        }
    }

    private func settingsPickerRow<Selection: Hashable, Content: View>(_ label: String, selection: Binding<Selection>, isLast: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.black.opacity(0.78))
            Spacer()
            Picker("", selection: selection) {
                content()
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
            }
        }
    }

    private func settingsLinkRow(_ label: String, isLast: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.black.opacity(0.78))
            Spacer()
            Text("View →")
                .font(.system(size: 13))
                .foregroundColor(Color(red: 0.0, green: 0.48, blue: 1.0))
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
            }
        }
    }

    private func permissionRow(label: String, granted: Bool, isLast: Bool = false, onFix: @escaping () -> Void) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.black.opacity(0.78))
            Spacer()
            if granted {
                HStack(spacing: 6) {
                    Circle().fill(Color(red: 0.20, green: 0.78, blue: 0.35)).frame(width: 8, height: 8)
                    Text("Granted")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(red: 0.20, green: 0.78, blue: 0.35))
                }
            } else {
                Button(action: onFix) {
                    HStack(spacing: 6) {
                        Circle().fill(Color(red: 0.95, green: 0.35, blue: 0.30)).frame(width: 8, height: 8)
                        Text("Grant")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(red: 0.0, green: 0.48, blue: 1.0))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
            }
        }
    }
}
