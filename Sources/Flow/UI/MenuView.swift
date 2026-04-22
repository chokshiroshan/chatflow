import SwiftUI

/// The menu bar dropdown view.
struct MenuView: View {
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.openWindow) var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 8)

            statusSection
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()
                .padding(.horizontal, 8)

            authSection
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()
                .padding(.horizontal, 8)

            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(width: 280)
        .background(FlowColors.surface)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 10) {
            // App icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [FlowColors.accent.opacity(0.6), FlowColors.accentPurple.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Flow")
                    .font(.system(size: 14, weight: .semibold))
                Text("Voice Dictation")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(statusColor.opacity(0.3), lineWidth: 3)
                )
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Hotkey hint
            HStack(spacing: 6) {
                Text(statusLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Spacer()

                if coordinator.state == .idle {
                    hotkeyBadge
                }
            }

            // Partial transcript (live preview)
            if !coordinator.partialTranscript.isEmpty {
                Text(coordinator.partialTranscript)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.1))
                    )
            }
        }
    }

    @ViewBuilder
    private var hotkeyBadge: some View {
        HStack(spacing: 2) {
            ForEach(parseHotkey(coordinator.config.hotkey), id: \.self) { key in
                Text(key)
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.12))
                    )
            }
        }
    }

    // MARK: - Auth

    @ViewBuilder
    private var authSection: some View {
        switch coordinator.authState {
        case .signedOut, .error:
            Button {
                coordinator.signIn()
            } label: {
                HStack {
                    Image(systemName: "person.badge.key")
                    Text("Sign in with ChatGPT")
                }
                .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if case .error(let msg) = coordinator.authState {
                Text(msg)
                    .font(.system(size: 10))
                    .foregroundStyle(.red.opacity(0.7))
                    .lineLimit(2)
            }

        case .signingIn:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Signing in...")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

        case .signedIn(let email, _):
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 10))
                Text(email)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Sign Out") {
                    coordinator.signOut()
                }
                .font(.system(size: 10))
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        HStack {
            SettingsLink {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 10))
                    Text("Settings")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button {
                openWindow(id: "onboarding")
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 10))
                    Text("Onboarding")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("v1.0")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch coordinator.state {
        case .idle: return .green
        case .connecting: return .yellow
        case .recording: return .red
        case .processing: return .yellow
        case .injecting: return .blue
        case .error: return .red
        default: return .gray
        }
    }

    private var statusLabel: String {
        switch coordinator.state {
        case .idle: return "Ready"
        case .connecting: return "Connecting..."
        case .recording: return "Recording"
        case .processing: return "Transcribing..."
        case .injecting: return "Injecting text"
        case .error(let msg): return "Error: \(msg)"
        default: return ""
        }
    }

    private func parseHotkey(_ hotkey: String) -> [String] {
        hotkey.split(separator: "+").map(String.init)
    }
}
