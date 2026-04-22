import SwiftUI

struct OnboardingFlowView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var step = 0
    @State private var selectedShortcut: String

    private let steps = ["Welcome", "ChatGPT", "Permissions", "Shortcut", "Done"]

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        _selectedShortcut = State(initialValue: ShortcutDisplay.toDisplay(coordinator.config.hotkey))
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(currentStep: step + 1, totalSteps: steps.count, title: steps[step])

            Group {
                switch step {
                case 0:
                    WelcomeStep(onNext: advance)
                case 1:
                    AccountStep(coordinator: coordinator, onNext: advance, onBack: goBack)
                case 2:
                    PermissionsStep(onNext: advance, onBack: goBack)
                case 3:
                    ShortcutStep(
                        selectedShortcut: $selectedShortcut,
                        onNext: persistShortcutAndAdvance,
                        onBack: goBack
                    )
                default:
                    DoneStep(
                        shortcutLabel: selectedShortcut,
                        onFinish: coordinator.completeOnboarding
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            StepDots(count: steps.count, current: step)
                .padding(.bottom, 18)
        }
        .frame(width: 540, height: 500)
        .background(Color(red: 0.95, green: 0.96, blue: 0.98))
    }

    private func advance() {
        withAnimation(.easeInOut(duration: 0.25)) {
            step = min(step + 1, steps.count - 1)
        }
    }

    private func goBack() {
        withAnimation(.easeInOut(duration: 0.25)) {
            step = max(step - 1, 0)
        }
    }

    private func persistShortcutAndAdvance() {
        coordinator.config.hotkey = ShortcutDisplay.toStored(selectedShortcut)
        coordinator.config.save()
        advance()
    }
}

private struct OnboardingHeader: View {
    let currentStep: Int
    let totalSteps: Int
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ChatFlow Setup")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black.opacity(0.75))
                Spacer()
                Text("Step \(currentStep) of \(totalSteps)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.black.opacity(0.45))
            }

            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.black.opacity(0.88))
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }
}

private struct StepDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4)
                    .fill(index == current ? Color.blue : Color.black.opacity(0.15))
                    .frame(width: index == current ? 18 : 7, height: 7)
                    .animation(.easeInOut(duration: 0.25), value: current)
            }
        }
    }
}

private struct WelcomeStep: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "waveform")
                .font(.system(size: 42, weight: .semibold))
                .foregroundColor(.purple)

            VStack(spacing: 10) {
                Text("Dictation for every app")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundColor(.black.opacity(0.88))

                Text("We'll connect your ChatGPT account, verify permissions, and set a shortcut so you can start dictating right away.")
                    .font(.system(size: 15))
                    .foregroundColor(.black.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            Button("Get Started", action: onNext)
                .buttonStyle(OnboardingPrimaryButtonStyle())

            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

private struct AccountStep: View {
    @ObservedObject var coordinator: AppCoordinator
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("ChatFlow uses your ChatGPT account for transcription, so you do not need to paste in an API key.")
                .font(.system(size: 15))
                .foregroundColor(.black.opacity(0.6))

            VStack(alignment: .leading, spacing: 12) {
                infoRow(icon: "safari", text: "Sign-in opens in your default browser.")
                infoRow(icon: "lock.shield", text: "Tokens are stored in Apple Keychain.")
                infoRow(icon: "person.crop.circle.badge.checkmark", text: statusText)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.8))
            )

            Spacer()

            HStack {
                Button("Back", action: onBack)
                    .buttonStyle(.plain)
                    .foregroundColor(.black.opacity(0.55))

                Spacer()

                if coordinator.authState.isSignedIn {
                    Button("Continue", action: onNext)
                        .buttonStyle(OnboardingPrimaryButtonStyle())
                } else if isSigningIn {
                    Button("Waiting for browser...") { }
                        .buttonStyle(OnboardingPrimaryButtonStyle(disabled: true))
                        .disabled(true)
                } else {
                    Button("Sign in with ChatGPT") {
                        coordinator.signIn()
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 28)
    }

    private var isSigningIn: Bool {
        if case .signingIn = coordinator.authState { return true }
        return false
    }

    private var statusText: String {
        switch coordinator.authState {
        case .signedIn(let email, _):
            return "Connected as \(email)"
        case .signingIn:
            return "Waiting for sign-in to finish"
        case .error(let message):
            return "Sign-in failed: \(message)"
        case .signedOut:
            return "Not connected yet"
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.green)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.black.opacity(0.68))
            Spacer()
        }
    }
}

private struct PermissionsStep: View {
    let onNext: () -> Void
    let onBack: () -> Void

    @State private var status = PermissionsManager.shared.checkAll()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ChatFlow needs microphone, accessibility, and input monitoring access to listen for your shortcut and paste text back into the active app.")
                .font(.system(size: 15))
                .foregroundColor(.black.opacity(0.6))

            VStack(spacing: 12) {
                permissionRow(
                    title: "Microphone",
                    detail: "Capture audio while you hold the shortcut.",
                    granted: status.microphone
                )
                permissionRow(
                    title: "Accessibility",
                    detail: "Paste transcribed text into the focused app.",
                    granted: status.accessibility
                )
                permissionRow(
                    title: "Input Monitoring",
                    detail: "Detect your shortcut anywhere on macOS.",
                    granted: status.inputMonitoring
                )
            }

            HStack(spacing: 10) {
                Button("Request Microphone") {
                    Task {
                        _ = await PermissionsManager.shared.requestMicrophone()
                        refreshStatus()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Open Accessibility") {
                    PermissionsManager.shared.openAccessibilitySettings()
                }
                .buttonStyle(.bordered)

                Button("Open Input Monitoring") {
                    PermissionsManager.shared.openInputMonitoringSettings()
                }
                .buttonStyle(.bordered)
            }

            Button("Refresh Status", action: refreshStatus)
                .buttonStyle(.plain)
                .foregroundColor(.blue)

            Spacer()

            HStack {
                Button("Back", action: onBack)
                    .buttonStyle(.plain)
                    .foregroundColor(.black.opacity(0.55))

                Spacer()

                Button("Continue", action: onNext)
                    .buttonStyle(OnboardingPrimaryButtonStyle(disabled: !status.allGranted))
                    .disabled(!status.allGranted)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 28)
        .onAppear(perform: refreshStatus)
    }

    private func permissionRow(title: String, detail: String, granted: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(granted ? .green : .gray)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(.black.opacity(0.55))
            }
            Spacer()
            Text(granted ? "Granted" : "Pending")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(granted ? .green : .orange)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.8))
        )
    }

    private func refreshStatus() {
        status = PermissionsManager.shared.checkAll()
    }
}

private struct ShortcutStep: View {
    @Binding var selectedShortcut: String
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Pick the shortcut you'll hold to dictate. You can change this later in Settings.")
                .font(.system(size: 15))
                .foregroundColor(.black.opacity(0.6))

            VStack(spacing: 12) {
                ForEach(ShortcutDisplay.pills, id: \.self) { shortcut in
                    Button {
                        selectedShortcut = shortcut
                    } label: {
                        HStack {
                            Text(shortcut)
                                .font(.system(size: 15, weight: .semibold))
                            Spacer()
                            if selectedShortcut == shortcut {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .foregroundColor(selectedShortcut == shortcut ? .blue : .black.opacity(0.75))
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(selectedShortcut == shortcut ? Color.blue.opacity(0.10) : Color.white.opacity(0.8))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(selectedShortcut == shortcut ? Color.blue : Color.black.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            HStack {
                Button("Back", action: onBack)
                    .buttonStyle(.plain)
                    .foregroundColor(.black.opacity(0.55))

                Spacer()

                Button("Save Shortcut", action: onNext)
                    .buttonStyle(OnboardingPrimaryButtonStyle())
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 28)
    }
}

private struct DoneStep: View {
    let shortcutLabel: String
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundColor(.green)

            Text("You're all set")
                .font(.system(size: 30, weight: .heavy))

            Text("ChatFlow lives in your menu bar. Hold \(shortcutLabel) anywhere to start dictating.")
                .font(.system(size: 15))
                .foregroundColor(.black.opacity(0.58))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            Button("Start dictating", action: onFinish)
                .buttonStyle(OnboardingPrimaryButtonStyle())

            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    var disabled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(minWidth: 140)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(disabled ? Color.gray.opacity(0.5) : Color.blue.opacity(configuration.isPressed ? 0.82 : 1.0))
            )
    }
}

private enum ShortcutDisplay {
    static let pills: [String] = [
        "Ctrl+Space",
        "Cmd+Shift+Space",
        "⌥ Space",
        "Right ⌘"
    ]

    static func toStored(_ display: String) -> String {
        switch display {
        case "Ctrl+Space":
            return "ctrl+space"
        case "Cmd+Shift+Space":
            return "cmd+shift+space"
        case "⌥ Space":
            return "option+space"
        case "Right ⌘":
            return "rightcmd"
        default:
            return "ctrl+space"
        }
    }

    static func toDisplay(_ stored: String) -> String {
        switch stored.lowercased() {
        case "ctrl+space":
            return "Ctrl+Space"
        case "cmd+shift+space":
            return "Cmd+Shift+Space"
        case "option+space", "opt+space", "alt+space":
            return "⌥ Space"
        case "rightcmd", "rcmd", "right+cmd":
            return "Right ⌘"
        default:
            return "Ctrl+Space"
        }
    }
}
