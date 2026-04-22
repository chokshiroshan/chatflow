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

            // Step dots
            FlowStepDots(count: steps.count, current: step)
                .padding(.bottom, 20)
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
            Spacer()

            // Animated waveform — aurora-style
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

            Spacer().frame(height: 28)

            Text("Welcome to ChatFlow")
                .font(FlowTypography.titleLarge)
                .foregroundColor(FlowColors.textPrimary)

            Spacer().frame(height: 10)

            Text("Voice-to-text, powered by your ChatGPT plan")
                .font(FlowTypography.body)
                .foregroundColor(FlowColors.textSecondary)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 44)

            FlowButton(title: "Get Started", style: .primary) { onNext() }
                .frame(width: 200, height: 44)

            Spacer()
        }
        .frame(maxWidth: .infinity)
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
            Spacer()

            // Hero card with OpenAI info
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 18) {
                    // OpenAI logo
                    ZStack {
                        RoundedRectangle(cornerRadius: FlowRadii.md)
                            .fill(FlowColors.accent.opacity(0.15))
                            .frame(width: 56, height: 56)
                            .overlay(
                                RoundedRectangle(cornerRadius: FlowRadii.md)
                                    .stroke(FlowColors.accent.opacity(0.3), lineWidth: 0.5)
                            )
                        OpenAILogo(color: FlowColors.accent, lineWidth: 2.0)
                            .frame(width: 28, height: 28)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Use your ChatGPT plan")
                            .font(FlowTypography.headline)
                            .foregroundColor(FlowColors.textPrimary)
                        Text("ChatFlow uses the Realtime API from your existing OpenAI account — **even the free tier**. No separate subscription, ever.")
                            .font(FlowTypography.body)
                            .foregroundColor(FlowColors.textSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer().frame(height: 18)

                // Free badge
                HStack(spacing: 7) {
                    Circle().fill(FlowColors.accentGreen).frame(width: 8, height: 8)
                    Text("Free ChatGPT account works · No credit card needed")
                        .font(FlowTypography.caption)
                        .foregroundColor(FlowColors.accentGreen)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: FlowRadii.sm)
                        .fill(FlowColors.accentGreen.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: FlowRadii.sm)
                        .stroke(FlowColors.accentGreen.opacity(0.2), lineWidth: 0.5)
                )
            }
            .flowGlassCard(padding: 20)

            Spacer().frame(height: 24)

            // How it works
            VStack(alignment: .leading, spacing: 0) {
                FlowSectionHeader(title: "How it works")
                    .padding(.bottom, 12)

                howItWorksRow(number: 1, title: "Your voice", subtitle: "Recorded locally, never stored")
                howItWorksRow(number: 2, title: "Realtime API", subtitle: "OpenAI real-time transcription model")
                howItWorksRow(number: 3, title: "Your ChatGPT plan", subtitle: "Billed to your account — free tier included", highlight: true)
            }

            Spacer()

            // Nav bar — consistent height + padding
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
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 8)
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

    private func howItWorksRow(number: Int, title: String, subtitle: String, highlight: Bool = false) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: FlowRadii.sm)
                    .fill(highlight ? FlowColors.accent.opacity(0.15) : FlowColors.card)
                    .frame(width: 28, height: 28)
                Text("\(number)")
                    .font(FlowTypography.caption)
                    .foregroundColor(highlight ? FlowColors.accent : FlowColors.textTertiary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(FlowTypography.bodyMedium).foregroundColor(FlowColors.textPrimary)
                Text(subtitle).font(FlowTypography.caption).foregroundColor(FlowColors.textSecondary)
            }
        }
        .padding(.bottom, 10)
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
            Spacer()

            // Mic circle
            ZStack {
                if requesting {
                    Circle()
                        .stroke(FlowColors.accent.opacity(0.3), lineWidth: 2)
                        .frame(width: 110, height: 110)
                    Circle()
                        .stroke(FlowColors.accent.opacity(0.15), lineWidth: 2)
                        .frame(width: 130, height: 130)
                }

                ZStack {
                    Circle()
                        .fill(
                            granted
                            ? AnyShapeStyle(FlowColors.accentGreen.opacity(0.2))
                            : requesting
                            ? AnyShapeStyle(FlowColors.accent.opacity(0.2))
                            : AnyShapeStyle(FlowColors.card)
                        )
                        .frame(width: 100, height: 100)
                        .overlay(
                            Circle()
                                .stroke(
                                    granted ? FlowColors.accentGreen.opacity(0.4)
                                    : requesting ? FlowColors.accent.opacity(0.3)
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
            .frame(width: 130, height: 130)

            Spacer().frame(height: 24)

            Text(granted ? "Microphone ready" : "Allow microphone access")
                .font(FlowTypography.title)
                .foregroundColor(FlowColors.textPrimary)

            Spacer().frame(height: 8)

            Text(granted
                 ? "ChatFlow can now listen when you hold your shortcut key."
                 : "ChatFlow only records while you hold your shortcut key. Your audio is never stored."
            )
                .font(FlowTypography.body)
                .foregroundColor(FlowColors.textSecondary)
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

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
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 8)
    }

    private func requestMic() {
        requesting = true
        Task {
            _ = await PermissionsManager.shared.requestMicrophone()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                requesting = false
                granted = true
            }
        }
    }
}

// MARK: - Step 4: Shortcut

private struct OnboardShortcutStep: View {
    @ObservedObject var coordinator: AppCoordinator
    let onNext: () -> Void
    let onBack: () -> Void
    @State private var selectedShortcut = "Ctrl+Space"

    private let shortcuts = ["Ctrl+Space", "Cmd+Shift+Space", "⌥ Space", "Right ⌘"]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Key icon
            ZStack {
                RoundedRectangle(cornerRadius: FlowRadii.xl)
                    .fill(
                        LinearGradient(
                            colors: [FlowColors.accentPurple.opacity(0.3), FlowColors.accent.opacity(0.3)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: FlowRadii.xl)
                            .stroke(FlowColors.accentPurple.opacity(0.4), lineWidth: 1)
                    )
                Image(systemName: "keyboard")
                    .font(.system(size: 34))
                    .foregroundColor(FlowColors.accentPurple)
            }

            Spacer().frame(height: 24)

            Text("Choose your shortcut")
                .font(FlowTypography.title)
                .foregroundColor(FlowColors.textPrimary)

            Spacer().frame(height: 8)

            Text("Hold to record, release to transcribe. Works in every app system-wide.")
                .font(FlowTypography.body)
                .foregroundColor(FlowColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            Spacer().frame(height: 32)

            // Shortcut pills
            HStack(spacing: 10) {
                ForEach(shortcuts, id: \.self) { s in
                    Button(action: { selectedShortcut = s }) {
                        Text(s)
                            .font(FlowTypography.bodyMedium)
                            .foregroundColor(s == selectedShortcut ? FlowColors.accent : FlowColors.textSecondary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: FlowRadii.md)
                                    .fill(s == selectedShortcut ? FlowColors.accent.opacity(0.12) : FlowColors.card)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: FlowRadii.md)
                                    .stroke(s == selectedShortcut ? FlowColors.accent.opacity(0.5) : FlowColors.border, lineWidth: s == selectedShortcut ? 1.5 : 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer().frame(height: 20)

            Text("You can change this anytime in Settings → Shortcut")
                .font(FlowTypography.caption)
                .foregroundColor(FlowColors.textTertiary)

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
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 8)
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
        ("Hold to record", "Keep the key held while you speak. Release to transcribe instantly.", "mic.fill"),
        ("Works everywhere", "Dictate in emails, docs, Slack, Notion — any text field.", "laptopcomputer.and.iphone"),
        ("Free to use", "Powered by your ChatGPT account. Free tier included.", "dollarsign.circle.fill"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Checkmark
            ZStack {
                Circle()
                    .fill(FlowColors.accentGreen.opacity(0.15))
                    .frame(width: 90, height: 90)
                    .overlay(
                        Circle()
                            .stroke(FlowColors.accentGreen.opacity(0.3), lineWidth: 1)
                    )
                Image(systemName: "checkmark")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundColor(FlowColors.accentGreen)
                    .flowGlow(FlowColors.accentGreen, radius: 10)
            }

            Spacer().frame(height: 24)

            Text("You're all set!")
                .font(FlowTypography.titleLarge)
                .foregroundColor(FlowColors.textPrimary)

            Spacer().frame(height: 8)

            Text("ChatFlow lives in your menu bar. Hold **\(hotkeyDisplay)** anywhere to start dictating.")
                .font(FlowTypography.body)
                .foregroundColor(FlowColors.textSecondary)
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440)

            Spacer().frame(height: 32)

            // Tip cards
            HStack(spacing: 10) {
                ForEach(tips, id: \.0) { tip in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: tip.2)
                                .font(.system(size: 11))
                                .foregroundColor(FlowColors.accent)
                            Text(tip.0)
                                .font(FlowTypography.caption)
                                .foregroundColor(FlowColors.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        Text(tip.1)
                            .font(.system(size: 11))
                            .foregroundColor(FlowColors.textSecondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
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

            Spacer().frame(height: 32)

            FlowButton(title: "Open ChatFlow", style: .primary) { onFinish() }
                .frame(width: 220, height: 44)

            Spacer()
        }
        .padding(.horizontal, 40)
    }
}
