import SwiftUI

// MARK: - Onboarding Flow

/// Multi-step onboarding matching the web design:
/// Welcome → ChatGPT → Microphone → Shortcut → Done
struct OnboardingFlowView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var step = 0

    private let steps = ["welcome", "chatgpt", "mic", "shortcut", "done"]

    var body: some View {
        VStack(spacing: 0) {
            // Content
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
            StepDots(count: steps.count, current: step)
                .padding(.bottom, 24)
        }
        .frame(width: 640, height: 600)
        .background(Color(red: 0.949, green: 0.957, blue: 0.973).opacity(0.82))
    }

    private func advance() { withAnimation(.easeInOut(duration: 0.3)) { step = min(step + 1, steps.count - 1) } }
    private func goBack() { withAnimation(.easeInOut(duration: 0.3)) { step = max(step - 1, 0) } }
    private func finish() { coordinator.completeOnboarding() }
}

// MARK: - Step Dots

private struct StepDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 4)
                    .fill(i == current ? Color(red: 0.0, green: 0.48, blue: 1.0) : Color.black.opacity(0.18))
                    .frame(width: i == current ? 20 : 7, height: 7)
                    .animation(.easeInOut(duration: 0.3), value: current)
            }
        }
    }
}

// MARK: - Step 1: Welcome

private struct OnboardWelcomeStep: View {
    let onNext: () -> Void
    @State private var animate = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Animated waveform
            HStack(spacing: 3) {
                let heights: [CGFloat] = [6, 10, 18, 28, 36, 32, 22, 34, 26, 16, 28, 20, 12, 24, 30, 18, 8]
                ForEach(0..<heights.count, id: \.self) { i in
                    let baseHeight = heights[i]
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.65, green: 0.55, blue: 0.98), Color(red: 0.43, green: 0.16, blue: 0.85)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .frame(width: 4, height: animate ? baseHeight : baseHeight * 0.6)
                        .shadow(color: Color(red: 0.43, green: 0.16, blue: 0.85).opacity(0.35), radius: 3)
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
                .font(.system(size: 30, weight: .heavy))
                .foregroundColor(.black.opacity(0.9))

            Spacer().frame(height: 12)

            Text("Voice-to-text, powered by your ChatGPT plan")
                .font(.system(size: 16))
                .foregroundColor(.black.opacity(0.55))
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            Spacer().frame(height: 40)

            // Get Started button
            Button(action: onNext) {
                Text("Get Started")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 200, height: 44)
                    .background(Color(red: 0.0, green: 0.48, blue: 1.0))
                    .cornerRadius(10)
                    .shadow(color: Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.35), radius: 8, x: 0, y: 2)
            }
            .buttonStyle(.plain)

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

            // Green hero banner
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 18) {
                    // OpenAI logo
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 56, height: 56)
                        OpenAILogo(color: .white, lineWidth: 2.2)
                            .frame(width: 30, height: 30)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Use your ChatGPT plan")
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundColor(.white)
                        Text("ChatFlow uses the Realtime API from your existing OpenAI account — **even the free tier**. No separate subscription, ever.")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.9))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer().frame(height: 20)

                // Free badge
                HStack(spacing: 7) {
                    Circle().fill(Color(red: 0.64, green: 1.0, blue: 0.87)).frame(width: 8, height: 8)
                    Text("Free ChatGPT account works · No credit card needed")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.18))
                .cornerRadius(12)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.62, blue: 0.44), Color(red: 0.06, green: 0.64, blue: 0.50), Color(red: 0.10, green: 0.70, blue: 0.58)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .cornerRadius(20)

            Spacer().frame(height: 24)

            // How it works
            VStack(alignment: .leading, spacing: 0) {
                Text("HOW IT WORKS")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.black.opacity(0.4))
                    .padding(.bottom, 12)

                howItWorksRow(number: 1, title: "Your voice", subtitle: "Recorded locally, never stored", highlight: false)
                howItWorksRow(number: 2, title: "Realtime API", subtitle: "OpenAI real-time transcription model", highlight: false)
                howItWorksRow(number: 3, title: "Your ChatGPT plan", subtitle: "Billed to your account — free tier included", highlight: true)
            }

            Spacer()

            OnboardingNavBar(onBack: onBack) {
                if connected {
                    PrimaryActionButton(
                        title: "Connected — Continue",
                        icon: "checkmark",
                        color: Color(red: 0.05, green: 0.62, blue: 0.44),
                        action: onNext
                    )
                } else {
                    PrimaryActionButton(
                        title: loading ? "Connecting…" : "Sign in with ChatGPT",
                        showsProgress: loading,
                        color: Color(red: 0.05, green: 0.62, blue: 0.44),
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
                loading = false
                connected = true
            case .error(let msg):
                loading = false
                // Show error briefly then reset
                print("⚠️ Onboarding auth error: \(msg)")
            case .signingIn:
                loading = true
            default:
                break
            }
        }
    }

    private func howItWorksRow(number: Int, title: String, subtitle: String, highlight: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(highlight ? Color(red: 0.06, green: 0.64, blue: 0.50).opacity(0.12) : Color.black.opacity(0.06))
                    .frame(width: 28, height: 28)
                Text("\(number)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(highlight ? Color(red: 0.05, green: 0.62, blue: 0.44) : Color.black.opacity(0.4))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(.black.opacity(0.85))
                Text(subtitle).font(.system(size: 12)).foregroundColor(.black.opacity(0.45))
            }
        }
        .padding(.bottom, 10)
    }

    private func handleConnect() {
        loading = true
        coordinator.signIn()
        // Auth state observation in .onChange will set connected = true on success
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
                        .stroke(Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.4), lineWidth: 2)
                        .frame(width: 100, height: 100)
                    Circle()
                        .stroke(Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.2), lineWidth: 2)
                        .frame(width: 120, height: 120)
                }

                ZStack {
                    Circle()
                        .fill(
                            granted
                            ? LinearGradient(colors: [Color(red: 0.20, green: 0.78, blue: 0.35), Color(red: 0.19, green: 0.72, blue: 0.32)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : requesting
                            ? LinearGradient(colors: [Color(red: 0.0, green: 0.48, blue: 1.0), Color(red: 0.35, green: 0.78, blue: 0.98)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.black.opacity(0.08), Color.black.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 100, height: 100)
                        .shadow(
                            color: granted ? Color(red: 0.20, green: 0.78, blue: 0.35).opacity(0.4) : requesting ? Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.3) : .clear,
                            radius: 24, x: 0, y: 6
                        )

                    if granted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 44, weight: .medium))
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 40))
                            .foregroundColor(requesting ? .white : .black.opacity(0.35))
                    }
                }
            }
            .frame(width: 120, height: 120)

            Spacer().frame(height: 28)

            Text(granted ? "Microphone ready" : "Allow microphone access")
                .font(.system(size: 26, weight: .heavy))
                .foregroundColor(.black.opacity(0.88))

            Spacer().frame(height: 10)

            Text(granted
                 ? "ChatFlow can now listen when you hold your shortcut key."
                 : "ChatFlow only records while you hold your shortcut key. Your audio is never stored."
            )
                .font(.system(size: 15))
                .foregroundColor(.black.opacity(0.52))
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Spacer()

            OnboardingNavBar(onBack: onBack) {
                if granted {
                    PrimaryActionButton(title: "Continue", action: onNext)
                } else {
                    PrimaryActionButton(
                        title: requesting ? "Requesting…" : "Allow Microphone",
                        showsProgress: requesting,
                        disabled: requesting,
                        action: requestMic
                    )
                }
            }

            Spacer()
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
                RoundedRectangle(cornerRadius: 22)
                    .fill(LinearGradient(colors: [Color(red: 0.35, green: 0.34, blue: 0.84), Color(red: 0.48, green: 0.43, blue: 0.96)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 80, height: 80)
                    .shadow(color: Color(red: 0.35, green: 0.34, blue: 0.84).opacity(0.4), radius: 24, x: 0, y: 8)
                Image(systemName: "keyboard")
                    .font(.system(size: 36))
                    .foregroundColor(.white)
            }

            Spacer().frame(height: 28)

            Text("Choose your shortcut")
                .font(.system(size: 26, weight: .heavy))
                .foregroundColor(.black.opacity(0.88))

            Spacer().frame(height: 10)

            Text("Hold to record, release to transcribe. Works in every app system-wide.")
                .font(.system(size: 15))
                .foregroundColor(.black.opacity(0.52))
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Spacer().frame(height: 32)

            // Shortcut pills
            HStack(spacing: 10) {
                ForEach(shortcuts, id: \.self) { s in
                    Button(action: { selectedShortcut = s }) {
                        Text(s)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(s == selectedShortcut ? Color(red: 0.35, green: 0.34, blue: 0.84) : .black.opacity(0.7))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(s == selectedShortcut ? Color(red: 0.35, green: 0.34, blue: 0.84).opacity(0.08) : Color.white.opacity(0.6))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(s == selectedShortcut ? Color(red: 0.35, green: 0.34, blue: 0.84) : Color.black.opacity(0.12), lineWidth: s == selectedShortcut ? 2 : 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer().frame(height: 28)

            Text("You can change this anytime in Settings → Shortcut")
                .font(.system(size: 13))
                .foregroundColor(.black.opacity(0.4))

            Spacer().frame(height: 32)

            OnboardingNavBar(onBack: onBack) {
                PrimaryActionButton(title: "Set Shortcut") {
                    let hotkeyString = selectedShortcut.lowercased()
                        .replacingOccurrences(of: " ", with: "+")
                        .replacingOccurrences(of: "⌥+", with: "option+")
                        .replacingOccurrences(of: "⌘", with: "cmd")
                    coordinator.updateHotkey(hotkeyString)
                    onNext()
                }
            }

            Spacer()
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
                    .fill(LinearGradient(colors: [Color(red: 0.20, green: 0.78, blue: 0.35), Color(red: 0.19, green: 0.72, blue: 0.32)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 90, height: 90)
                    .shadow(color: Color(red: 0.20, green: 0.78, blue: 0.35).opacity(0.45), radius: 32, x: 0, y: 8)
                Image(systemName: "checkmark")
                    .font(.system(size: 46, weight: .medium))
                    .foregroundColor(.white)
            }

            Spacer().frame(height: 28)

            Text("You're all set!")
                .font(.system(size: 30, weight: .heavy))
                .foregroundColor(.black.opacity(0.9))

            Spacer().frame(height: 12)

            Text("ChatFlow lives in your menu bar. Hold **\(hotkeyDisplay)** anywhere to start dictating.")
                .font(.system(size: 15))
                .foregroundColor(.black.opacity(0.52))
                .lineSpacing(5)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440)

            Spacer().frame(height: 40)

            // Tip cards
            HStack(spacing: 12) {
                ForEach(tips, id: \.0) { tip in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Image(systemName: tip.2)
                                .font(.system(size: 11))
                                .foregroundColor(.black.opacity(0.5))
                            Text(tip.0)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.black.opacity(0.8))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        Text(tip.1)
                            .font(.system(size: 12))
                            .foregroundColor(.black.opacity(0.48))
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.black.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                    )
                }
            }

            Spacer().frame(height: 40)

            Button(action: onFinish) {
                Text("Open ChatFlow")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 220, height: 44)
                    .background(Color(red: 0.0, green: 0.48, blue: 1.0))
                    .cornerRadius(10)
                    .shadow(color: Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.35), radius: 8, x: 0, y: 2)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Shared Components

// MARK: Consistent Navigation Bar

/// Standardized back/forward nav bar for onboarding steps.
/// Back button on the left, primary action on the right.
struct OnboardingNavBar<Primary: View>: View {
    let onBack: () -> Void
    @ViewBuilder let primary: Primary

    var body: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.black.opacity(0.5))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.04))
                )
            }
            .buttonStyle(.plain)

            Spacer()

            primary
        }
    }
}

// MARK: Primary Action Button

/// Consistent primary action button used across onboarding.
struct PrimaryActionButton: View {
    let title: String
    var icon: String? = nil
    var color: Color = Color(red: 0.0, green: 0.48, blue: 1.0)
    var showsProgress: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if showsProgress {
                    ProgressView()
                        .controlSize(.small)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 9)
            .background(disabled ? Color.gray.opacity(0.6) : color)
            .cornerRadius(10)
            .shadow(color: (disabled ? Color.gray : color).opacity(0.35), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: OpenAI Logo (SVG-style Shape)

/// Draws the OpenAI logo as a SwiftUI Shape.
/// The classic hexagonal knot / flower pattern.
struct OpenAILogo: View {
    var color: Color = .black
    var lineWidth: CGFloat = 1.8

    var body: some View {
        Canvas { context, size in
            let cx = size.width / 2
            let cy = size.height / 2
            let r = min(size.width, size.height) * 0.38

            // Draw 6 interlocking loops of the OpenAI knot
            let angles: [Angle] = [
                .degrees(0), .degrees(60), .degrees(120),
                .degrees(180), .degrees(240), .degrees(300)
            ]

            var path = Path()
            for angle in angles {
                let rad = angle.radians
                // Each loop is a rounded arc from center outward
                let ax = cx + r * cos(rad)
                let ay = cy + r * sin(rad)

                // Draw a small circle at each vertex
                let loopR = r * 0.42
                path.addEllipse(in: CGRect(
                    x: ax - loopR,
                    y: ay - loopR,
                    width: loopR * 2,
                    height: loopR * 2
                ))
            }

            // Outer ring
            path.addEllipse(in: CGRect(
                x: cx - r * 0.68,
                y: cy - r * 0.68,
                width: r * 1.36,
                height: r * 1.36
            ))

            context.stroke(path, with: .color(color), lineWidth: lineWidth)

            // Center hub
            var hub = Path()
            hub.addEllipse(in: CGRect(
                x: cx - r * 0.15,
                y: cy - r * 0.15,
                width: r * 0.3,
                height: r * 0.3
            ))
            context.fill(hub, with: .color(color))
        }
    }
}

/// Small indeterminate progress indicator for buttons
private struct ProgressControl: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .padding(.trailing, 2)
    }
}
