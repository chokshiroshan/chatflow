import SwiftUI

// MARK: - Onboarding Flow

struct OnboardingFlowView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var step = 0

    private let steps = ["welcome", "chatgpt", "mic", "shortcut", "done"]

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: OnboardWelcomeStep(onNext: advance)
                case 1: OnboardChatGPTStep(coordinator: coordinator, onNext: advance, onBack: goBack)
                case 2: OnboardMicStep(onNext: advance, onBack: goBack)
                case 3: OnboardShortcutStep(coordinator: coordinator, onNext: advance, onBack: goBack)
                case 4: OnboardDoneStep(coordinator: coordinator, onFinish: finish)
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom dots
            FlowStepDots(count: steps.count, current: step)
                .padding(.bottom, 14)
        }
        .frame(width: 640, height: 600)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.06, blue: 0.14),
                    Color(red: 0.06, green: 0.04, blue: 0.12),
                    Color(red: 0.03, green: 0.05, blue: 0.10)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
    }

    private func advance() { withAnimation(.easeInOut(duration: 0.3)) { step = min(step + 1, steps.count - 1) } }
    private func goBack()  { withAnimation(.easeInOut(duration: 0.3)) { step = max(step - 1, 0) } }
    private func finish()  { coordinator.completeOnboarding() }
}

// MARK: - Step 1: Welcome

private struct OnboardWelcomeStep: View {
    let onNext: () -> Void
    @State private var animate = false

    var body: some View {
        VStack(spacing: 0) {
            // Animated waveform
            HStack(spacing: 3) {
                let heights: [CGFloat] = [6, 10, 18, 28, 36, 32, 22, 34, 26, 16, 28, 20, 12, 24, 30, 18, 8]
                ForEach(0..<heights.count, id: \.self) { i in
                    let baseHeight = heights[i]
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [FlowColors.accent, FlowColors.accentPurple],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .frame(width: 4, height: animate ? baseHeight : baseHeight * 0.6)
                        .flowGlow(FlowColors.accent, radius: 4)
                        .animation(
                            .easeInOut(duration: 0.8 + Double(i % 4) * 0.15)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.05),
                            value: animate
                        )
                }
            }
            .frame(height: 48)
            .onAppear { animate = true }

            Spacer().frame(height: 36)

            Text("Welcome to ChatFlow")
                .font(FlowTypography.titleLarge)
                .foregroundColor(FlowColors.textPrimary)

            Spacer().frame(height: 12)

            Text("Voice-to-text, powered by your ChatGPT account")
                .font(FlowTypography.body)
                .foregroundColor(FlowColors.textSecondary)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 44)

            FlowButton(title: "Get Started", style: .primary) { onNext() }
                .frame(width: 200, height: 44)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 100)
    }
}

// MARK: - Step 2: ChatGPT Connect

private struct OnboardChatGPTStep: View {
    @ObservedObject var coordinator: AppCoordinator
    let onNext: () -> Void
    let onBack: () -> Void
    @State private var connected = false
    @State private var loading = false

    var body: some View {
        VStack(spacing: 0) {
            // Centered OpenAI logo
            ZStack {
                Circle()
                    .fill(FlowColors.accent.opacity(0.1))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .stroke(FlowColors.accent.opacity(0.2), lineWidth: 1)
                    )
                OpenAILogo(color: FlowColors.accent, lineWidth: 2.0)
                    .frame(width: 36, height: 36)
            }
            .flowGlow(FlowColors.accent.opacity(0.3), radius: 16)

            Spacer().frame(height: 20)

            Text("Connect your ChatGPT account")
                .font(FlowTypography.title)
                .foregroundColor(FlowColors.textPrimary)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 10)

            Text("ChatFlow streams audio to OpenAI's Realtime API for transcription.\nUse your existing ChatGPT account — no API key needed.")
                .font(FlowTypography.body)
                .foregroundColor(FlowColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)

            Spacer().frame(height: 18)

            // Badge
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(FlowColors.accentGreen)
                Text("No credit card needed · Uses your ChatGPT plan")
                    .font(FlowTypography.caption)
                    .foregroundColor(FlowColors.accentGreen)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: FlowRadii.md)
                    .fill(FlowColors.accentGreen.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: FlowRadii.md)
                    .stroke(FlowColors.accentGreen.opacity(0.15), lineWidth: 0.5)
            )

            Spacer().frame(height: 22)

            // How it works
            VStack(spacing: 10) {
                howItWorksRow(icon: "mic.fill", title: "Your voice", subtitle: "Recorded locally, streamed in real-time")
                howItWorksRow(icon: "bolt.horizontal.fill", title: "Realtime API", subtitle: "Transcribed by GPT-4o-mini")
                howItWorksRow(icon: "creditcard.fill", title: "Your ChatGPT plan", subtitle: "Billed through your OpenAI account")
            }
            .frame(maxWidth: 360)

            Spacer()

            // Nav bar
            FlowNavBar(onBack: onBack) {
                if connected {
                    FlowButton(title: "Connected — Continue", icon: "checkmark", style: .primary, action: onNext)
                } else {
                    FlowButton(
                        title: loading ? "Connecting…" : "Sign in with ChatGPT",
                        style: .primary,
                        showsProgress: loading,
                        disabled: loading,
                        action: handleConnect
                    )
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 40)
        .onAppear {
            if case .signedIn = coordinator.authState { connected = true }
        }
        .onChange(of: coordinator.authState) { _, newState in
            switch newState {
            case .signedIn:
                loading = false; connected = true
            case .error(let msg):
                loading = false
                print("⚠️ Onboarding auth error: \(msg)")
            case .signingIn:
                loading = true
            default: break
            }
        }
    }

    private func howItWorksRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(FlowColors.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(FlowTypography.bodyMedium)
                    .foregroundColor(FlowColors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(FlowColors.textSecondary)
            }
            Spacer()
        }
    }

    private func handleConnect() {
        loading = true
        coordinator.signIn()
    }
}

// MARK: - Step 3: Microphone

private struct OnboardMicStep: View {
    let onNext: () -> Void
    let onBack: () -> Void
    @State private var granted = false
    @State private var requesting = false

    var body: some View {
        VStack(spacing: 0) {
            // Mic circle
            ZStack {
                if requesting {
                    Circle()
                        .stroke(FlowColors.accent.opacity(0.2), lineWidth: 2)
                        .frame(width: 120, height: 120)
                        .scaleEffect(requesting ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: requesting)
                }

                ZStack {
                    Circle()
                        .fill(
                            granted
                            ? AnyShapeStyle(FlowColors.accentGreen.opacity(0.12))
                            : requesting
                            ? AnyShapeStyle(FlowColors.accent.opacity(0.12))
                            : AnyShapeStyle(FlowColors.card)
                        )
                        .frame(width: 100, height: 100)
                        .overlay(
                            Circle()
                                .stroke(
                                    granted ? FlowColors.accentGreen.opacity(0.3)
                                    : requesting ? FlowColors.accent.opacity(0.2)
                                    : FlowColors.border,
                                    lineWidth: 1
                                )
                        )

                    if granted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundColor(FlowColors.accentGreen)
                            .flowGlow(FlowColors.accentGreen, radius: 8)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 36))
                            .foregroundColor(requesting ? FlowColors.accent : FlowColors.textTertiary)
                    }
                }
            }
            .frame(width: 140, height: 140)

            Spacer().frame(height: 24)

            Text(granted ? "Microphone ready" : "Allow microphone access")
                .font(FlowTypography.title)
                .foregroundColor(FlowColors.textPrimary)

            Spacer().frame(height: 10)

            Text(granted
                 ? "ChatFlow can now listen when you hold your shortcut key."
                 : "ChatFlow only records while you hold your shortcut key.\nAudio is streamed directly to OpenAI — never stored locally or on our servers."
            )
                .font(FlowTypography.body)
                .foregroundColor(FlowColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 360)

            Spacer()

            FlowNavBar(onBack: onBack) {
                if granted {
                    FlowButton(title: "Continue", style: .primary, action: onNext)
                } else {
                    FlowButton(
                        title: requesting ? "Requesting…" : "Allow Microphone",
                        style: .primary,
                        showsProgress: requesting,
                        disabled: requesting,
                        action: requestMic
                    )
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 60)
        .onAppear { checkMicPermission() }
    }

    private func requestMic() {
        requesting = true
        Task {
            _ = await PermissionsManager.shared.requestMicrophone()
            // Small delay for macOS to update permission state
            try? await Task.sleep(for: .milliseconds(500))
            granted = PermissionsManager.shared.checkMicrophone()
            requesting = false
        }
    }

    /// Also check on appear (in case user granted via System Settings)
    private func checkMicPermission() {
        granted = PermissionsManager.shared.checkMicrophone()
    }
}

// MARK: - Step 4: Shortcut

private struct OnboardShortcutStep: View {
    @ObservedObject var coordinator: AppCoordinator
    let onNext: () -> Void
    let onBack: () -> Void
    @State private var selectedShortcut = "Ctrl+Space"
    @State private var accessibilityGranted = false
    @State private var inputMonitoringGranted = false

    private let shortcuts = ["Ctrl+Space", "Cmd+Shift+Space", "⌥ Space", "Right ⌘"]

    var body: some View {
        VStack(spacing: 0) {
            // Keyboard icon
            ZStack {
                RoundedRectangle(cornerRadius: FlowRadii.xl)
                    .fill(
                        LinearGradient(
                            colors: [FlowColors.accentPurple.opacity(0.2), FlowColors.accent.opacity(0.2)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: FlowRadii.xl)
                            .stroke(FlowColors.accentPurple.opacity(0.3), lineWidth: 1)
                    )
                Image(systemName: "keyboard")
                    .font(.system(size: 34))
                    .foregroundColor(FlowColors.accentPurple)
            }
            .flowGlow(FlowColors.accentPurple.opacity(0.3), radius: 12)

            Spacer().frame(height: 24)

            Text("Choose your shortcut")
                .font(FlowTypography.title)
                .foregroundColor(FlowColors.textPrimary)

            Spacer().frame(height: 10)

            Text("Hold to record, release to transcribe.\nWorks in every app, system-wide.")
                .font(FlowTypography.body)
                .foregroundColor(FlowColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Spacer().frame(height: 32)

            // Shortcut pills — 2x2 grid
            let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(shortcuts, id: \.self) { s in
                    Button(action: { selectedShortcut = s }) {
                        Text(s)
                            .font(FlowTypography.bodyMedium)
                            .foregroundColor(s == selectedShortcut ? FlowColors.accent : FlowColors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: FlowRadii.md)
                                    .fill(s == selectedShortcut ? FlowColors.accent.opacity(0.12) : FlowColors.card)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: FlowRadii.md)
                                    .stroke(s == selectedShortcut ? FlowColors.accent.opacity(0.4) : FlowColors.border, lineWidth: s == selectedShortcut ? 1.5 : 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 380)

            Spacer().frame(height: 16)

            Text("Change anytime in Settings")
                .font(.system(size: 11))
                .foregroundColor(FlowColors.textTertiary)

            Spacer().frame(height: 16)

            // Permission status
            VStack(spacing: 8) {
                permRow(
                    granted: accessibilityGranted,
                    icon: "lock.shield",
                    label: "Accessibility",
                    action: {
                        PermissionsManager.shared.requestAccessibility()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            accessibilityGranted = PermissionsManager.shared.checkAccessibility()
                        }
                    }
                )
                permRow(
                    granted: inputMonitoringGranted,
                    icon: "keyboard",
                    label: "Input Monitoring",
                    action: {
                        PermissionsManager.shared.openInputMonitoringSettings()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            inputMonitoringGranted = PermissionsManager.shared.checkInputMonitoring()
                        }
                    }
                )
            }
            .frame(maxWidth: 380)

            Spacer()

            FlowNavBar(onBack: onBack) {
                FlowButton(title: "Set Shortcut", style: .primary) {
                    let hotkeyString = selectedShortcut.lowercased()
                        .replacingOccurrences(of: " ", with: "+")
                        .replacingOccurrences(of: "⌥+", with: "option+")
                        .replacingOccurrences(of: "⌘", with: "cmd")
                    coordinator.updateHotkey(hotkeyString)
                    onNext()
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 60)
        .onAppear {
            accessibilityGranted = PermissionsManager.shared.checkAccessibility()
            inputMonitoringGranted = PermissionsManager.shared.checkInputMonitoring()
        }
    }

    private func permRow(granted: Bool, icon: String, label: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(granted ? FlowColors.accentGreen : FlowColors.accentOrange)
                .frame(width: 20)
            Text(label)
                .font(FlowTypography.bodyMedium)
                .foregroundColor(FlowColors.textPrimary)
            Spacer()
            if granted {
                Text("Granted")
                    .font(FlowTypography.caption)
                    .foregroundColor(FlowColors.accentGreen)
            } else {
                Button(action: action) {
                    Text("Grant →")
                        .font(FlowTypography.caption)
                        .foregroundColor(FlowColors.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: FlowRadii.sm)
                .fill(FlowColors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: FlowRadii.sm)
                .stroke(granted ? FlowColors.accentGreen.opacity(0.2) : FlowColors.accentOrange.opacity(0.2), lineWidth: 0.5)
        )
    }
}

// MARK: - Step 5: Done

private struct OnboardDoneStep: View {
    @ObservedObject var coordinator: AppCoordinator
    let onFinish: () -> Void

    private var hotkeyDisplay: String {
        coordinator.config.hotkey
            .split(separator: "+")
            .map { part -> String in
                switch part.lowercased() {
                case "ctrl": return "Ctrl"
                case "option", "alt": return "⌥"
                case "cmd", "command": return "⌘"
                case "shift": return "⇧"
                case "space": return "Space"
                default: return part.prefix(1).uppercased() + part.dropFirst()
                }
            }
            .joined(separator: "+")
    }

    private let tips: [(String, String, String)] = [
        ("Hold to record", "Keep the key held while you speak.", "mic.fill"),
        ("+ Shift = enhanced", "Adds screen context for better accuracy.", "display"),
        ("Works everywhere", "Any text field in any app.", "laptopcomputer.and.iphone"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Checkmark
            ZStack {
                Circle()
                    .fill(FlowColors.accentGreen.opacity(0.12))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .stroke(FlowColors.accentGreen.opacity(0.25), lineWidth: 1)
                    )
                Image(systemName: "checkmark")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundColor(FlowColors.accentGreen)
                    .flowGlow(FlowColors.accentGreen, radius: 10)
            }

            Spacer().frame(height: 24)

            Text("You're all set!")
                .font(FlowTypography.titleLarge)
                .foregroundColor(FlowColors.textPrimary)

            Spacer().frame(height: 10)

            Text("ChatFlow lives in your menu bar.\nHold **\(hotkeyDisplay)** anywhere to start dictating.\nAdd **Shift** for screen-aware transcription.")
                .font(FlowTypography.body)
                .foregroundColor(FlowColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)

            Spacer().frame(height: 24)

            // Tip cards
            HStack(spacing: 10) {
                ForEach(tips, id: \.0) { tip in
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: tip.2)
                            .font(.system(size: 14))
                            .foregroundColor(FlowColors.accent)
                        Text(tip.0)
                            .font(FlowTypography.caption)
                            .foregroundColor(FlowColors.textPrimary)
                        Text(tip.1)
                            .font(.system(size: 11))
                            .foregroundColor(FlowColors.textSecondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: FlowRadii.md)
                            .fill(FlowColors.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: FlowRadii.md)
                            .stroke(FlowColors.border, lineWidth: 0.5)
                    )
                }
            }
            .frame(maxWidth: 480)

            Spacer()

            FlowButton(title: "Open ChatFlow", style: .primary) { onFinish() }
                .frame(width: 220, height: 44)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 50)
        .padding(.horizontal, 40)
    }
}
