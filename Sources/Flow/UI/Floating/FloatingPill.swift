import SwiftUI

/// The floating pill that appears near the text cursor when dictating.
///
/// This is the signature UI element — a small translucent pill that shows:
/// - Waveform animation while recording
/// - Partial transcript streaming as you speak
/// - Processing spinner when transcribing
/// - Brief "done" checkmark after injection
///
/// Position: floats near the top of the screen, centered horizontally.
/// Can be dragged to reposition.
struct FloatingPill: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var dragOffset: CGSize = .zero
    @State private var position: CGPoint = CGPoint(x: NSScreen.main!.frame.midX, y: 80)
    @State private var opacity: Double = 0
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        if coordinator.state.isActive || coordinator.state == .idle {
            pillContent
                .opacity(shouldShow ? 1 : 0)
                .offset(dragOffset)
                .animation(.easeInOut(duration: 0.2), value: shouldShow)
                .animation(.easeInOut(duration: 0.3), value: coordinator.state)
        }
    }

    private var shouldShow: Bool {
        coordinator.state.isActive
    }

    // MARK: - Pill Content

    @ViewBuilder
    private var pillContent: some View {
        HStack(spacing: 10) {
            // Status indicator
            statusIcon

            // Waveform or transcript
            if coordinator.state == .recording || coordinator.state == .speaking {
                if coordinator.partialTranscript.isEmpty {
                    waveformAnimation
                } else {
                    transcriptView
                }
            } else if coordinator.state == .processing {
                ProgressView()
                    .controlSize(.small)
                Text("Transcribing...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            } else if coordinator.state == .injecting {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Done")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(borderColor, lineWidth: 1.5)
        )
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { _ in
                    dragOffset = .zero
                }
        )
    }

    // MARK: - Status Icon

    @ViewBuilder
    private var statusIcon: some View {
        switch coordinator.state {
        case .recording:
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .scaleEffect(pulseScale)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        pulseScale = 1.3
                    }
                }

        case .processing:
            ProgressView()
                .controlSize(.small)

        case .speaking:
            Image(systemName: "waveform")
                .foregroundStyle(.green)

        case .injecting:
            Image(systemName: "text.cursor")
                .foregroundStyle(.blue)

        default:
            EmptyView()
        }
    }

    // MARK: - Waveform Animation

    @ViewBuilder
    private var waveformAnimation: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(coordinator.state == .recording ? Color.red : Color.green)
                    .frame(width: 3, height: waveformHeight(for: i))
                    .animation(
                        .easeInOut(duration: 0.4)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.1),
                        value: coordinator.state
                    )
            }
        }
        .frame(height: 20)
    }

    private func waveformHeight(for index: Int) -> CGFloat {
        [12, 18, 8, 20, 14][index % 5]
    }

    // MARK: - Transcript Preview

    @ViewBuilder
    private var transcriptView: some View {
        Text(coordinator.partialTranscript)
            .font(.system(size: 13))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 300, alignment: .leading)
    }

    // MARK: - Border Color

    private var borderColor: Color {
        switch coordinator.state {
        case .recording: return .red.opacity(0.5)
        case .processing: return .yellow.opacity(0.3)
        case .injecting: return .blue.opacity(0.3)
        case .speaking: return .green.opacity(0.3)
        default: return .clear
        }
    }
}

// MARK: - Window Controller

/// Manages the floating pill as a borderless, always-on-top window.
final class FloatingPillWindowController {
    private var window: NSWindow?

    func show(coordinator: AppCoordinator) {
        guard window == nil else { return }

        let screen = NSScreen.main!
        let width: CGFloat = 400
        let height: CGFloat = 50
        let x = (screen.frame.width - width) / 2
        let y = screen.frame.height - 100 // Near top of screen

        let window = NSWindow(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false

        let hostingView = NSHostingView(rootView: FloatingPill(coordinator: coordinator))
        hostingView.frame = window.contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(hostingView)

        window.orderFrontRegardless()
        self.window = window
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }
}
