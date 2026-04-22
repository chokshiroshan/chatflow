import SwiftUI

/// The menu bar dropdown view — dark spacey theme with explicit light text.
struct MenuView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

            menuDivider

            statusSection
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            menuDivider

            authSection
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            menuDivider

            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(width: 280)
        .background(FlowColors.background)
    }

    // MARK: - Divider

    private var menuDivider: some View {
        Divider()
            .overlay(FlowColors.border)
            .padding(.horizontal, 8)
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
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("ChatFlow")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(FlowColors.textPrimary)
                Text("Voice Dictation")
                    .font(.system(size: 10))
                    .foregroundColor(FlowColors.textTertiary)
            }

            Spacer()

            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .flowGlow(statusColor, radius: 6)
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
                    .foregroundColor(FlowColors.textSecondary)

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
                    .foregroundColor(FlowColors.textSecondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(FlowColors.card)
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
                    .foregroundColor(FlowColors.accent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(FlowColors.accent.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(FlowColors.accent.opacity(0.25), lineWidth: 0.5)
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
                        .font(.system(size: 11))
                    Text("Sign in with ChatGPT")
                        .font(.system(size: 12))
                }
                .foregroundColor(FlowColors.accent)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: FlowRadii.sm)
                    .fill(FlowColors.accent.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: FlowRadii.sm)
                    .stroke(FlowColors.accent.opacity(0.25), lineWidth: 0.5)
            )

            if case .error(let msg) = coordinator.authState {
                Text(msg)
                    .font(.system(size: 10))
                    .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.4))
                    .lineLimit(2)
            }

        case .signingIn:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Signing in...")
                    .font(.system(size: 12))
                    .foregroundColor(FlowColors.textSecondary)
            }

        case .signedIn(let email, _):
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(FlowColors.accentGreen)
                    .font(.system(size: 10))
                Text(email)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundColor(FlowColors.textSecondary)
                Spacer()
                Button("Sign Out") {
                    coordinator.signOut()
                }
                .font(.system(size: 10))
                .buttonStyle(.plain)
                .foregroundColor(FlowColors.textTertiary)
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
                .foregroundColor(FlowColors.textSecondary)
            }
            .buttonStyle(.plain)

            Button {
                coordinator.reopenOnboarding()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 10))
                    Text("Help")
                        .font(.system(size: 11))
                }
                .foregroundColor(FlowColors.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("v1.0")
                .font(.system(size: 10))
                .foregroundColor(FlowColors.textTertiary)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.system(size: 11))
                    .foregroundColor(FlowColors.textTertiary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch coordinator.state {
        case .idle: return FlowColors.accentGreen
        case .connecting: return FlowColors.accentOrange
        case .recording: return FlowColors.accent
        case .processing: return FlowColors.accentPurple
        case .injecting: return FlowColors.accent
        case .error: return Color(red: 1.0, green: 0.35, blue: 0.35)
        default: return FlowColors.textTertiary
        }
    }

    private var statusLabel: String {
        switch coordinator.state {
        case .idle: return "Ready"
        case .connecting: return "Connecting..."
        case .recording: return coordinator.isEnhancedMode ? "Recording (Enhanced)" : "Recording"
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
