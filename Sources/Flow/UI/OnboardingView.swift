import SwiftUI

/// First-launch onboarding view that guides users through granting permissions.
struct OnboardingView: View {
    @State private var micGranted = false
    @State private var accGranted = false
    @State private var inputGranted = false
    @State private var currentStep = 0

    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Header
            Image(systemName: "mic.fill.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            Text("Welcome to Flow")
                .font(.largeTitle)
                .bold()
            Text("Grant these permissions to get started")
                .foregroundStyle(.secondary)

            // Permission steps
            VStack(spacing: 12) {
                permissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    desc: "Needed to capture your voice",
                    granted: micGranted,
                    action: { await requestMic() }
                )

                permissionRow(
                    icon: "accessibility",
                    title: "Accessibility",
                    desc: "Needed to inject text into other apps",
                    granted: accGranted,
                    action: { requestAcc() }
                )

                permissionRow(
                    icon: "keyboard",
                    title: "Input Monitoring",
                    desc: "Needed to detect the dictation hotkey",
                    granted: inputGranted,
                    action: { requestInput() }
                )
            }

            Spacer()

            // Continue button
            Button(allGranted ? "Get Started" : "Continue Anyway") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(false)
        }
        .padding(30)
        .frame(width: 420, height: 440)
        .onAppear { refreshStatus() }
    }

    private var allGranted: Bool {
        micGranted && accGranted && inputGranted
    }

    // MARK: - Permission Row

    @ViewBuilder
    private func permissionRow(
        icon: String, title: String, desc: String,
        granted: Bool, action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(granted ? .green : .secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            } else {
                Button("Grant") { action() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(granted ? Color.green.opacity(0.05) : Color.gray.opacity(0.05))
        )
    }

    // MARK: - Actions

    private func refreshStatus() {
        let status = PermissionsManager.shared.checkAll()
        micGranted = status.microphone
        accGranted = status.accessibility
        inputGranted = status.inputMonitoring
    }

    private func requestMic() async {
        _ = await PermissionsManager.shared.requestMicrophone()
        refreshStatus()
    }

    private func requestAcc() {
        PermissionsManager.shared.requestAccessibility()
        // Accessibility requires app restart to take effect
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { refreshStatus() }
    }

    private func requestInput() {
        PermissionsManager.shared.openInputMonitoringSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { refreshStatus() }
    }
}
