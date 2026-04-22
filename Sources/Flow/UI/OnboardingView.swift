import SwiftUI

// MARK: - Onboarding Flow

struct OnboardingFlowView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var step = 0

    private let steps = ["welcome", "chatgpt", "mic", "shortcut", "done"]

    var body: some View {
        VStack(spacing: 0) {
            // Content area — fills available space
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

            // Bottom bar: dots + nav — fixed height
            VStack(spacing: 0) {
                FlowStepDots(count: steps.count, current: step)
                    .padding(.bottom, 14)
            }
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
                .frame(minHeight: 60)

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

            Text("Voice-to-text, powered by your ChatGPT plan")
                .font(FlowTypography.body)
                .foregroundColor(FlowColors.textSecondary)
                .multilineTextAlignment(.center)

            Spacer().frame(minHeight: 48)

            FlowButton(title: "Get Started", style: .primary) { onNext() }
                .frame(width: 200, height: 44)

            Spacer()
                .frame(minHeight: 40)
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
                .frame(minHeight: 30)

            // Centered OpenAI logo
            ZStack {
                Circle()
                    .fill(FlowColors.accent.opacity(0.1))
                    .frame(width: 90, height: 90)
                    .overlay(
                        Circle()
                            .stroke(FlowColors.accent.opacity(0.2), lineWidth: 1)
                    )
                OpenAILogo(color: FlowColors.accent, lineWidth: 2.0)
                    .frame(width: 40, height: 40)
            }
            .flowGlow(FlowColors.accent.opacity(0.3), radius: 16)

            Spacer().frame(height: 24)

            Text("Connect your ChatGPT account")
                .font(FlowTypography.title)
                .foregroundColor(FlowColors.textPrimary)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 10)

            Text("ChatFlow uses the Realtime API from your OpenAI account.\nEven the free tier works — no separate subscription needed.")
                .font(FlowTypography.body)
                .foregroundColor(FlowColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)

            Spacer().frame(height: 20)

            // Free badge — centered
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(FlowColors.accentGreen)
                Text("Free tier works · No credit card needed")
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

            Spacer().frame(minHeight: 24)

            // How it works — centered, compact
            VStack(spacing: 10) {
                howItWorksRow(icon: "mic.fill", title: "Your voice", subtitle: "Recorded locally, never stored")
                howItWorksRow(icon: "bolt.horizontal.fill", title: "Realtime API", subtitle: "OpenAI transcription model")
                howItWorksRow(icon: "creditcard.fill", title: "Your ChatGPT plan", subtitle: "Free tier included")
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
        .frame(maxWidth: .infinity)
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
            Spacer()
                .frame(minHeight: 40)

            // Mic circle — centered, generous size
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

            Spacer().frame(height: 28)

            Text(granted ? "Microphone ready" : "Allow microphone access")
                .font(FlowTypography.title)
                .foregroundColor(FlowColors.textPrimary)

            Spacer().frame(height: 10)

            Text(granted
                 ? "ChatFlow can now listen when you hold your shortcut key."
                 : "ChatFlow only records while you hold your shortcut key.\nYour audio is never stored on our servers."
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
        .frame(maxWidth: .infinity)
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
                .frame(minHeight: 40)

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

            Spacer().frame(height: 28)

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

            // Shortcut pills — 2x2 grid for better layout
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
        .frame(maxWidth: .infinity)
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
        ("Works everywhere", "Any text field in any app.", "laptopcomputer.and.iphone"),
        ("Free to use", "Powered by your ChatGPT account.", "dollarsign.circle.fill"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(minHeight: 30)

            // Checkmark
            ZStack {
                Circle()
                    .fill(FlowColors.accentGreen.opacity(0.12))
                    .frame(width: 90, height: 90)
                    .overlay(
                        Circle()
                            .stroke(FlowColors.accentGreen.opacity(0.25), lineWidth: 1)
                    )
                Image(systemName: "checkmark")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundColor(FlowColors.accentGreen)
                    .flowGlow(FlowColors.accentGreen, radius: 10)
            }

            Spacer().frame(height: 28)

            Text("You're all set!")
                .font(FlowTypography.titleLarge)
                .foregroundColor(FlowColors.textPrimary)

            Spacer().frame(height: 10)

            Text("ChatFlow lives in your menu bar.\nHold **\(hotkeyDisplay)** anywhere to start dictating.")
                .font(FlowTypography.body)
                .foregroundColor(FlowColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)

            Spacer().frame(minHeight: 28)

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
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
    }
}
