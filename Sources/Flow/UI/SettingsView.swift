import SwiftUI

// MARK: - Settings Window

struct SettingsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var autoStartEnabled = AutoStartManager.shared.isEnabled
    @State private var selectedTab = "general"
    @State private var inputDevices: [AudioCapture.InputDevice] = AudioCapture.listInputDevices()

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            settingsContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 720, height: 560)
        .background(FlowColors.background)
    }

    // MARK: - Sidebar

    private var settingsItems: [(String, String, String)] {
        [
            ("general", "General", "gearshape"),
            ("shortcut", "Shortcut", "keyboard"),
            ("mic", "Microphone", "mic.fill"),
            ("privacy", "Privacy", "shield.fill"),
            ("about", "About", "info.circle"),
        ]
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 16)

            // Nav items
            VStack(spacing: 2) {
                ForEach(settingsItems, id: \.0) { item in
                    Button(action: { withAnimation(.easeInOut(duration: 0.15)) { selectedTab = item.0 } }) {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: FlowRadii.sm)
                                    .fill(selectedTab == item.0 ? FlowColors.accent.opacity(0.2) : FlowColors.card)
                                    .frame(width: 28, height: 28)
                                Image(systemName: item.2)
                                    .font(.system(size: 13))
                                    .foregroundColor(selectedTab == item.0 ? FlowColors.accent : FlowColors.textTertiary)
                            }
                            Text(item.1)
                                .font(FlowTypography.bodyMedium)
                                .foregroundColor(selectedTab == item.0 ? FlowColors.textPrimary : FlowColors.textSecondary)
                            Spacer()
                        }
                        .padding(.vertical, 9)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: FlowRadii.md)
                                .fill(selectedTab == item.0 ? FlowColors.accent.opacity(0.06) : .clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)

            Spacer()
        }
        .frame(width: 210)
        .background(FlowColors.surface)
    }

    // MARK: - Content

    @ViewBuilder
    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(settingsItems.first(where: { $0.0 == selectedTab })?.1 ?? "General")
                    .font(FlowTypography.title)
                    .foregroundColor(FlowColors.textPrimary)
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
            settingsSection("App") {
                settingsToggleRow("Launch at login", isOn: $autoStartEnabled)
                    .onChange(of: autoStartEnabled) { _, _ in try? AutoStartManager.shared.toggle() }
                settingsToggleRow("Sound effects", isOn: $coordinator.config.soundEffectsEnabled)
                    .onChange(of: coordinator.config.soundEffectsEnabled) { _, _ in coordinator.config.save() }
                settingsToggleRow("Auto-paste after transcription", isOn: $coordinator.config.autoPasteEnabled, isLast: true)
                    .onChange(of: coordinator.config.autoPasteEnabled) { _, _ in coordinator.config.save() }
            }

            settingsSection("Transcription") {
                settingsPickerRow("Language", selection: $coordinator.config.language, isLast: true) {
                    Text("Auto-detect").tag("auto")
                    Text("English").tag("en")
                    Text("Spanish").tag("es")
                    Text("French").tag("fr")
                    Text("German").tag("de")
                    Text("Japanese").tag("ja")
                    Text("Chinese").tag("zh")
                }
                .onChange(of: coordinator.config.language) { _, _ in coordinator.config.save() }
            }

            settingsSection("Appearance") {
                settingsPickerRow("Theme", selection: $coordinator.config.appearance, isLast: true) {
                    Text("Dark").tag("dark")
                    Text("Match System").tag("system")
                    Text("Light").tag("light")
                }
                .onChange(of: coordinator.config.appearance) { _, newValue in
                    coordinator.config.save()
                    switch newValue {
                    case "light": NSApp.appearance = NSAppearance(named: .aqua)
                    case "dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
                    default:      NSApp.appearance = nil
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
                    let shortcutOptions = [("Ctrl+Space", "ctrl+space"), ("Cmd+Shift+Space", "cmd+shift+space"), ("⌥ Space", "option+space"), ("Right ⌘", "rcmd")]
                    HStack(spacing: 10) {
                        ForEach(shortcutOptions, id: \.1) { display, value in
                            Button(action: { coordinator.updateHotkey(value) }) {
                                Text(display)
                                    .font(FlowTypography.bodyMedium)
                                    .foregroundColor(coordinator.config.hotkey == value ? FlowColors.accent : FlowColors.textSecondary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: FlowRadii.md)
                                            .fill(coordinator.config.hotkey == value ? FlowColors.accent.opacity(0.12) : FlowColors.card)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: FlowRadii.md)
                                            .stroke(coordinator.config.hotkey == value ? FlowColors.accent.opacity(0.4) : FlowColors.border, lineWidth: coordinator.config.hotkey == value ? 1.5 : 0.5)
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
                        .font(FlowTypography.caption)
                        .foregroundColor(FlowColors.textTertiary)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(FlowColors.card)
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(LinearGradient(colors: [FlowColors.accent, FlowColors.accentPurple], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * 0.65, height: 6)
                        }
                    }
                    .frame(height: 6)

                    HStack(spacing: 2) {
                        ForEach(0..<40, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(FlowColors.accent.opacity(0.25))
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
                Image(systemName: "shield.fill")
                    .font(.system(size: 20))
                    .foregroundColor(FlowColors.accentGreen)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your audio stays private")
                        .font(FlowTypography.bodyMedium)
                        .foregroundColor(FlowColors.textPrimary)
                    Text("Audio is streamed directly to OpenAI's Realtime API and transcribed in real-time. ChatFlow never stores or logs your recordings.")
                        .font(FlowTypography.caption)
                        .foregroundColor(FlowColors.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: FlowRadii.md)
                    .fill(FlowColors.accentGreen.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: FlowRadii.md)
                    .stroke(FlowColors.accentGreen.opacity(0.15), lineWidth: 0.5)
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
                RoundedRectangle(cornerRadius: FlowRadii.lg)
                    .fill(
                        LinearGradient(colors: [FlowColors.accent.opacity(0.3), FlowColors.accentPurple.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 72, height: 72)
                    .overlay(
                        RoundedRectangle(cornerRadius: FlowRadii.lg)
                            .stroke(FlowColors.accent.opacity(0.3), lineWidth: 1)
                    )
                Image(systemName: "mic.fill")
                    .font(.system(size: 32))
                    .foregroundColor(FlowColors.accent)
            }

            Spacer().frame(height: 16)

            Text("ChatFlow")
                .font(FlowTypography.title)
                .foregroundColor(FlowColors.textPrimary)
            Text("Version 1.0.0 (Build 100)")
                .font(FlowTypography.caption)
                .foregroundColor(FlowColors.textTertiary)

            Spacer().frame(height: 24)

            settingsSection("Account") {
                settingsInfoRow("ChatGPT account") {
                    if case .signedIn(let email, _) = coordinator.authState {
                        HStack(spacing: 6) {
                            Circle().fill(FlowColors.accentGreen).frame(width: 8, height: 8)
                            Text("Connected — \(email)")
                                .font(FlowTypography.caption)
                                .foregroundColor(FlowColors.textSecondary)
                        }
                    } else {
                        Text("Not connected")
                            .font(FlowTypography.caption)
                            .foregroundColor(FlowColors.textTertiary)
                    }
                }
                settingsInfoRow("Usage this month") {
                    Text(coordinator.usageDisplay)
                        .font(FlowTypography.caption)
                        .foregroundColor(FlowColors.textSecondary)
                }
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
            FlowSectionHeader(title: title)

            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: FlowRadii.lg)
                    .fill(FlowColors.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: FlowRadii.lg)
                    .stroke(FlowColors.border, lineWidth: 0.5)
            )
        }
    }

    private func settingsToggleRow(_ label: String, isOn: Binding<Bool>, isLast: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(FlowTypography.bodyMedium)
                .foregroundColor(FlowColors.textPrimary)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(FlowColors.accent)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider().overlay(FlowColors.border)
            }
        }
    }

    private func settingsPickerRow<Selection: Hashable, Content: View>(_ label: String, selection: Binding<Selection>, isLast: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(FlowTypography.bodyMedium)
                .foregroundColor(FlowColors.textPrimary)
            Spacer()
            Picker("", selection: selection) {
                content()
            }
            .pickerStyle(.menu)
            .tint(FlowColors.accent)
            .labelsHidden()
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider().overlay(FlowColors.border)
            }
        }
    }

    private func settingsLinkRow(_ label: String, isLast: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(FlowTypography.bodyMedium)
                .foregroundColor(FlowColors.textPrimary)
            Spacer()
            Text("View →")
                .font(FlowTypography.caption)
                .foregroundColor(FlowColors.accent)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider().overlay(FlowColors.border)
            }
        }
    }

    private func settingsInfoRow(_ label: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack {
            Text(label)
                .font(FlowTypography.bodyMedium)
                .foregroundColor(FlowColors.textPrimary)
            Spacer()
            trailing()
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Divider().overlay(FlowColors.border)
        }
    }

    private func permissionRow(label: String, granted: Bool, isLast: Bool = false, onFix: @escaping () -> Void) -> some View {
        HStack {
            Text(label)
                .font(FlowTypography.bodyMedium)
                .foregroundColor(FlowColors.textPrimary)
            Spacer()
            if granted {
                HStack(spacing: 6) {
                    Circle().fill(FlowColors.accentGreen).frame(width: 8, height: 8)
                    Text("Granted")
                        .font(FlowTypography.caption)
                        .foregroundColor(FlowColors.accentGreen)
                }
            } else {
                Button(action: onFix) {
                    HStack(spacing: 6) {
                        Circle().fill(FlowColors.accentOrange).frame(width: 8, height: 8)
                        Text("Grant")
                            .font(FlowTypography.caption)
                            .foregroundColor(FlowColors.accent)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider().overlay(FlowColors.border)
            }
        }
    }
}
