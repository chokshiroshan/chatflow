import SwiftUI

// MARK: - Settings Window

struct SettingsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var autoStartEnabled = AutoStartManager.shared.isEnabled
    @State private var selectedTab = "general"

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

    private let settingsItems: [(String, String, String)] = [
        ("general", "General", "gearshape"),
        ("transcription", "Transcription", "waveform"),
        ("shortcut", "Shortcut", "keyboard"),
        ("mic", "Microphone", "mic.fill"),
        ("privacy", "Privacy", "shield.fill"),
        ("about", "About", "info.circle"),
    ]

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 16)

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
                case "transcription": settingsTranscription
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
                settingsToggleRow("Mute system audio while recording", isOn: $coordinator.config.shouldMuteAudio)
                    .onChange(of: coordinator.config.shouldMuteAudio) { _, newValue in
                        coordinator.config.save()
                        VolumeManager.shared.shouldMuteAudio = newValue
                    }
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

    // MARK: - Transcription Settings

    /// Preset instruction templates users can pick from.
    private struct InstructionTemplate {
        let name: String
        let icon: String
        let description: String
        let instructions: String
    }

    private let instructionTemplates: [InstructionTemplate] = [
        InstructionTemplate(
            name: "Verbatim",
            icon: "text.quote",
            description: "Exact words, no corrections",
            instructions: "Transcribe exactly what was said. Output only the spoken words. Do not correct, interpret, or rephrase anything. Preserve the speaker's exact wording including informal speech, pauses as commas, and natural sentence structure. If there is no clear speech, output nothing."
        ),
        InstructionTemplate(
            name: "Clean & Formal",
            icon: "sparkles",
            description: "Grammar fixes, polished output",
            instructions: "Transcribe the user's speech and output clean, well-formed text. Fix grammar mistakes, remove filler words (um, uh, like), add proper punctuation, and format the result as polished written text. Preserve the original meaning but improve readability."
        ),
        InstructionTemplate(
            name: "Overly Eager",
            icon: "bolt.fill",
            description: "Expands abbreviations, adds context",
            instructions: "Transcribe and enhance the user's speech. Expand abbreviations to their full form, add missing context, format lists and structures clearly. If the user says something ambiguous, choose the most likely intended meaning. Be helpful and interpret generously."
        ),
        InstructionTemplate(
            name: "Code Friendly",
            icon: "chevron.left.forwardslash.chevron.right",
            description: "Optimized for technical terms",
            instructions: "Transcribe speech with technical accuracy. Properly capitalize and format programming terms, API names, variable names, and technical jargon. Use camelCase, PascalCase, or snake_case where appropriate for code terms. Format code snippets on separate lines."
        ),
        InstructionTemplate(
            name: "Minimal",
            icon: "minus",
            description: "Just the words, nothing else",
            instructions: "Output only the spoken words. No punctuation correction, no formatting, no interpretation. Raw transcription only."
        ),
    ]

    @State private var selectedTemplateIndex: Int? = nil
    @State private var showCustomEditor: Bool = false

    private var settingsTranscription: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Model selection
            settingsSection("Model") {
                settingsPickerRow("Realtime Model", selection: $coordinator.config.realtimeModel) {
                    Text("GPT Realtime 1.5 (Best)").tag("gpt-realtime-1.5")
                    Text("GPT Realtime (Stable)").tag("gpt-realtime")
                }
                .onChange(of: coordinator.config.realtimeModel) { _, _ in coordinator.config.save() }

                settingsPickerRow("Transcription Model", selection: $coordinator.config.transcriptionModel, isLast: true) {
                    Text("GPT-4o Transcribe (Best)").tag("gpt-4o-transcribe")
                    Text("GPT-4o Transcribe Diarize").tag("gpt-4o-transcribe-diarize")
                    Text("GPT-4o Mini Transcribe").tag("gpt-4o-mini-transcribe")
                    Text("Whisper 1 (Fast)").tag("whisper-1")
                }
                .onChange(of: coordinator.config.transcriptionModel) { _, _ in coordinator.config.save() }
            }

            // Instruction templates
            settingsSection("Behavior") {
                VStack(alignment: .leading, spacing: 12) {
                    // Template grid
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ], spacing: 10) {
                        ForEach(Array(instructionTemplates.enumerated()), id: \.offset) { index, template in
                            Button(action: {
                                selectedTemplateIndex = index
                                coordinator.config.systemInstructions = template.instructions
                                coordinator.config.save()
                            }) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {                                        Image(systemName: template.icon)
                                            .font(.system(size: 14))
                                            .foregroundColor(selectedTemplateIndex == index ? FlowColors.accent : FlowColors.textTertiary)
                                        Spacer()
                                        if selectedTemplateIndex == index {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 12))
                                                .foregroundColor(FlowColors.accent)
                                        }
                                    }
                                    Text(template.name)
                                        .font(FlowTypography.bodyMedium)
                                        .foregroundColor(selectedTemplateIndex == index ? FlowColors.textPrimary : FlowColors.textSecondary)
                                        .lineLimit(1)
                                    Text(template.description)
                                        .font(.system(size: 10))
                                        .foregroundColor(FlowColors.textTertiary)
                                        .lineLimit(1)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: FlowRadii.md)
                                        .fill(selectedTemplateIndex == index ? FlowColors.accent.opacity(0.1) : FlowColors.card)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: FlowRadii.md)
                                        .stroke(selectedTemplateIndex == index ? FlowColors.accent.opacity(0.4) : FlowColors.border, lineWidth: selectedTemplateIndex == index ? 1.5 : 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        // Custom option
                        Button(action: { showCustomEditor = true }) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {                                    Image(systemName: "pencil.line")
                                        .font(.system(size: 14))
                                        .foregroundColor(FlowColors.accentPurple)
                                    Spacer()
                                }
                                Text("Custom")
                                    .font(FlowTypography.bodyMedium)
                                    .foregroundColor(FlowColors.textSecondary)
                                    .lineLimit(1)
                                Text("Write your own")
                                    .font(.system(size: 10))
                                    .foregroundColor(FlowColors.textTertiary)
                                    .lineLimit(1)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: FlowRadii.md)
                                    .fill(selectedTemplateIndex == nil && !showCustomEditor ? FlowColors.accentPurple.opacity(0.1) : FlowColors.card)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: FlowRadii.md)
                                    .stroke(FlowColors.accentPurple.opacity(0.4), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 12)
            }

            // Custom instructions editor (always visible)
            settingsSection("System Instructions") {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $coordinator.config.systemInstructions)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(FlowColors.textPrimary)
                        .scrollContentBackground(.hidden)
                        .background(FlowColors.background)
                        .frame(height: 100)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: FlowRadii.sm)
                                .fill(FlowColors.background)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: FlowRadii.sm)
                                .stroke(FlowColors.border, lineWidth: 0.5)
                        )
                        .onChange(of: coordinator.config.systemInstructions) { _, newValue in
                            // Deselect template if user edits manually
                            if let idx = selectedTemplateIndex,
                               instructionTemplates[idx].instructions != newValue {
                                selectedTemplateIndex = nil
                            }
                            coordinator.config.save()
                        }

                    HStack {
                        Text("This is sent to the transcription model on every session. Edit freely.")
                            .font(.system(size: 10))
                            .foregroundColor(FlowColors.textTertiary)
                        Spacer()
                        Text("\(coordinator.config.systemInstructions.count) chars")
                            .font(.system(size: 10))
                            .foregroundColor(FlowColors.textTertiary)
                    }
                }
                .padding(.vertical, 12)
            }

            // User context — personal names/terms that survive template switches
            settingsSection("Your Context") {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $coordinator.config.userContext)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(FlowColors.textPrimary)
                        .scrollContentBackground(.hidden)
                        .background(FlowColors.background)
                        .frame(height: 60)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: FlowRadii.sm)
                                .fill(FlowColors.background)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: FlowRadii.sm)
                                .stroke(FlowColors.border, lineWidth: 0.5)
                        )
                        .onChange(of: coordinator.config.userContext) { _, _ in coordinator.config.save() }

                    HStack {
                        Text("Names, terms, projects — anything you say often. Survives template switches.")
                            .font(.system(size: 10))
                            .foregroundColor(FlowColors.textTertiary)
                        Spacer()
                    }
                }
                .padding(.vertical, 12)
            }

            // Context toggles
            settingsSection("Context") {
                settingsToggleRow("Include active app name", isOn: $coordinator.config.includeAppContext)
                    .onChange(of: coordinator.config.includeAppContext) { _, _ in coordinator.config.save() }
                settingsToggleRow("Include saved vocabulary", isOn: $coordinator.config.includeVocabulary, isLast: true)
                    .onChange(of: coordinator.config.includeVocabulary) { _, _ in coordinator.config.save() }
            }

            // Advanced parameters
            settingsSection("Advanced") {
                // Temperature slider
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Temperature")
                            .font(FlowTypography.bodyMedium)
                            .foregroundColor(FlowColors.textPrimary)
                        Spacer()
                        Text(String(format: "%.2f", coordinator.config.temperature))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(FlowColors.accent)
                    }
                    Slider(value: $coordinator.config.temperature, in: 0.6...1.2, step: 0.05)
                        .tint(FlowColors.accent)
                        .onChange(of: coordinator.config.temperature) { _, _ in coordinator.config.save() }
                    Text("Lower = more deterministic. 0.8 recommended.")
                        .font(.system(size: 10))
                        .foregroundColor(FlowColors.textTertiary)
                }
                .padding(.vertical, 8)

                // Max response tokens
                HStack {
                    Text("Max Output Tokens")
                        .font(FlowTypography.bodyMedium)
                        .foregroundColor(FlowColors.textPrimary)
                    Spacer()
                    TextField("", value: $coordinator.config.maxResponseOutputTokens, format: .number)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(FlowColors.textPrimary)
                        .textFieldStyle(.plain)
                        .frame(width: 60)
                        .padding(4)
                        .background(FlowColors.background)
                        .overlay(
                            RoundedRectangle(cornerRadius: FlowRadii.sm)
                                .stroke(FlowColors.border, lineWidth: 0.5)
                        )
                        .onChange(of: coordinator.config.maxResponseOutputTokens) { _, _ in coordinator.config.save() }
                }

                // Noise reduction
                settingsPickerRow("Noise Reduction", selection: Binding(
                    get: { coordinator.config.inputAudioNoiseReduction ?? "off" },
                    set: { coordinator.config.inputAudioNoiseReduction = ($0 == "off" ? nil : $0); coordinator.config.save() }
                ), isLast: true) {
                    Text("Off").tag("off")
                    Text("Near Field").tag("near_field")
                    Text("Far Field").tag("far_field")
                }

                // Audio format
                settingsPickerRow("Audio Format", selection: $coordinator.config.inputAudioFormat, isLast: true) {
                    Text("PCM 16-bit").tag("pcm16")
                    Text("G.711 μ-law").tag("g711_ulaw")
                    Text("G.711 A-law").tag("g711_alaw")
                }
                .onChange(of: coordinator.config.inputAudioFormat) { _, newValue in
                    coordinator.config.outputAudioFormat = newValue
                    coordinator.config.save()
                }
            }
        }
        .onAppear {
            // Match current instructions to a template if possible
            selectedTemplateIndex = instructionTemplates.firstIndex(where: { $0.instructions == coordinator.config.systemInstructions })
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
                HStack {
                    Text("Mode")
                        .font(FlowTypography.bodyMedium)
                        .foregroundColor(FlowColors.textPrimary)
                    Spacer()
                    Text("Hold to record")
                        .font(FlowTypography.caption)
                        .foregroundColor(FlowColors.textSecondary)
                }
                .padding(.vertical, 13)
                .overlay(alignment: .bottom) {
                    Divider().overlay(FlowColors.border)
                }

                HStack {
                    Text("Works system-wide in any app")
                        .font(FlowTypography.caption)
                        .foregroundColor(FlowColors.textTertiary)
                    Spacer()
                }
                .padding(.vertical, 13)
            }

            settingsSection("Enhanced Mode") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Add Shift to your shortcut")
                            .font(FlowTypography.bodyMedium)
                            .foregroundColor(FlowColors.textPrimary)
                        Spacer()
                        Text("Ctrl+Shift+Space")
                            .font(FlowTypography.caption)
                            .foregroundColor(FlowColors.accentOrange)
                    }
                    .padding(.vertical, 13)
                    .overlay(alignment: .bottom) {
                        Divider().overlay(FlowColors.border)
                    }

                    Text("Captures your screen and sends it to GPT-4o-mini for context. The transcription model then knows what app you're in, what terms are on screen, and can transcribe more accurately.")
                        .font(FlowTypography.caption)
                        .foregroundColor(FlowColors.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - Microphone

    private var settingsMic: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsSection("Input Device") {
                HStack {
                    Text("Microphone")
                        .font(FlowTypography.bodyMedium)
                        .foregroundColor(FlowColors.textPrimary)
                    Spacer()
                    Text("System Default")
                        .font(FlowTypography.caption)
                        .foregroundColor(FlowColors.textSecondary)
                }
                .padding(.vertical, 13)
                .overlay(alignment: .bottom) {
                    Divider().overlay(FlowColors.border)
                }

                Text("Change your microphone in System Settings → Sound → Input")
                    .font(FlowTypography.caption)
                    .foregroundColor(FlowColors.textTertiary)
                    .padding(.vertical, 8)
            }

            settingsSection("Usage") {
                HStack {
                    Text("This month")
                        .font(FlowTypography.bodyMedium)
                        .foregroundColor(FlowColors.textPrimary)
                    Spacer()
                    Text(coordinator.usageDisplay)
                        .font(FlowTypography.caption)
                        .foregroundColor(FlowColors.textSecondary)
                }
                .padding(.vertical, 13)
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
                    Text("Audio is streamed directly to OpenAI's Realtime API and transcribed in real-time. ChatFlow never stores or logs your recordings.\n\nEnhanced mode (Shift+shortcut) sends a screenshot to OpenAI for context — this is optional and only activates when you hold Shift.")
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

            settingsSection("Permissions") {
                permissionRow(label: "Microphone access", granted: coordinator.permissionsStatus.microphone) {
                    // Open System Settings directly to microphone privacy
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
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
                Image(systemName: "waveform")
                    .font(.system(size: 32))
                    .foregroundColor(FlowColors.accent)
            }

            Spacer().frame(height: 16)

            Text("ChatFlow")
                .font(FlowTypography.title)
                .foregroundColor(FlowColors.textPrimary)
            Text("Version 1.0.0")
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

            Text("Voice-to-text for macOS, powered by your ChatGPT plan.")
                .font(FlowTypography.caption)
                .foregroundColor(FlowColors.textTertiary)
                .multilineTextAlignment(.center)
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
