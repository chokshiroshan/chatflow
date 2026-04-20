import SwiftUI

/// The menu bar dropdown view.
struct MenuView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider()
            modePicker
            Divider()
            statusSection
            Divider()

            if coordinator.config.preferredMode == .voiceChat {
                voiceChatControls
                Divider()
            }

            authSection
            Divider()
            footer
        }
        .padding(10)
        .frame(width: 280)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack {
            Text("🎤 Flow")
                .font(.headline)
            Spacer()
            Text(coordinator.state.icon)
                .font(.title3)
        }
    }

    // MARK: - Mode Picker

    @ViewBuilder
    private var modePicker: some View {
        Picker("Mode", selection: $coordinator.config.preferredMode) {
            ForEach(AppMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: coordinator.config.preferredMode) { _, newMode in
            coordinator.switchMode(to: newMode)
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusSection: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }

        if !coordinator.partialTranscript.isEmpty {
            Text(coordinator.partialTranscript)
                .font(.caption)
                .lineLimit(3)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    // MARK: - Voice Chat Controls

    @ViewBuilder
    private var voiceChatControls: some View {
        HStack {
            if coordinator.voiceChatActive {
                Button("Stop Chat") { coordinator.stopVoiceChat() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                Button("Interrupt") { coordinator.interruptVoiceChat() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Button("🎙️ Start Voice Chat") { Task { await coordinator.startVoiceChat() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Auth

    @ViewBuilder
    private var authSection: some View {
        switch coordinator.authState {
        case .signedOut, .error:
            Button("Sign in with ChatGPT") { Task { await coordinator.signIn() } }
                .buttonStyle(.bordered)
                .controlSize(.small)

            if case .error(let msg) = coordinator.authState {
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

        case .signingIn:
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Signing in...")
                    .font(.caption)
            }

        case .signedIn(let email, let plan):
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(email)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text("✓")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Text(plan)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Sign Out") { coordinator.signOut() }
                .buttonStyle(.bordered)
                .controlSize(.mini)
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        HStack {
            Text("v1.0 · Free with ChatGPT sub")
                .font(.caption2)
                .foregroundStyle(.quaternary)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch coordinator.state {
        case .idle: return .gray
        case .connecting: return .yellow
        case .recording: return .red
        case .processing: return .yellow
        case .injecting: return .blue
        case .speaking: return .green
        case .error: return .red
        }
    }

    private var statusText: String {
        switch coordinator.state {
        case .idle: return "Ready — press \(coordinator.config.hotkey) to dictate"
        case .connecting: return "Connecting..."
        case .recording: return "🔴 Recording — speak now"
        case .processing: return "Transcribing..."
        case .injecting: return "Injecting text..."
        case .speaking: return "🔊 ChatGPT speaking"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}
