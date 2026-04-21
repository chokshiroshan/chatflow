import SwiftUI

/// Wispr Flow-inspired floating pill with live waveform animation.
///
/// Shows near the cursor when dictation is active:
/// - Animated sine-wave while recording
/// - Partial transcript streaming as you speak
/// - Processing spinner → Done checkmark
///
/// Only visible when actively recording or processing.
struct FloatingPill: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var dragOffset: CGSize = .zero
    @State private var opacity: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var wavePhase: CGFloat = 0
    @State private var waveAmplitudes: [CGFloat] = [0.3, 0.5, 0.8, 1.0, 0.8, 0.5, 0.3]
    @State private var displayLink: NSDisplayLink?
    @State private var animationTimer: Timer?

    var body: some View {
        Group {
            if shouldShow {
                pillContent
                    .opacity(opacity)
                    .offset(dragOffset)
                    .onAppear { appearAnimation() }
                    .onDisappear { disappearAnimation() }
                    .onChange(of: shouldShow) { _, showing in
                        if showing { appearAnimation() } else { disappearAnimation() }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var shouldShow: Bool {
        coordinator.state.isActive || coordinator.state == .connecting
    }

    // MARK: - Pill Content

    @ViewBuilder
    private var pillContent: some View {
        HStack(spacing: 10) {
            // Animated waveform icon
            waveIcon

            // Status text
            statusContent
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(pillBackground)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(borderColor, lineWidth: 1))
        .shadow(color: shadowColor, radius: 12, y: 4)
        .gesture(
            DragGesture()
                .onChanged { value in dragOffset = value.translation }
                .onEnded { _ in dragOffset = .zero }
        )
    }

    // MARK: - Wave Icon

    @ViewBuilder
    private var waveIcon: some View {
        ZStack {
            // Glow ring
            if coordinator.state == .recording {
                Circle()
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 28, height: 28)
                    .scaleEffect(pulseScale)
            }

            // Animated wave bars
            HStack(spacing: 2.5) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(waveBarColor)
                        .frame(width: 3, height: waveBarHeight(for: i))
                        .animation(
                            .easeInOut(duration: 0.35)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.08),
                            value: coordinator.state == .recording
                        )
                }
            }
            .frame(width: 22, height: 18)
        }
        .frame(width: 28, height: 28)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulseScale = 1.4
            }
        }
    }

    private var waveBarColor: Color {
        switch coordinator.state {
        case .recording: return .red
        case .connecting: return .orange
        case .processing: return .yellow
        case .speaking: return .green
        case .injecting: return .blue
        default: return .gray
        }
    }

    private func waveBarHeight(for index: Int) -> CGFloat {
        if coordinator.state == .recording {
            return [8, 14, 6, 16, 10][index % 5]
        } else if coordinator.state == .connecting {
            return 6 // flat bars
        } else {
            return 4
        }
    }

    // MARK: - Status Content

    @ViewBuilder
    private var statusContent: some View {
        switch coordinator.state {
        case .connecting:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Connecting...")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

        case .recording:
            if coordinator.partialTranscript.isEmpty {
                Text("Listening...")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                Text(coordinator.partialTranscript)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 280, alignment: .leading)
            }

        case .processing:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Transcribing...")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

        case .injecting:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Done")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.green)
            }

        case .speaking:
            Text(coordinator.partialTranscript)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .lineLimit(1)

        case .error(let msg):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(msg)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

        default:
            EmptyView()
        }
    }

    // MARK: - Background & Styling

    @ViewBuilder
    private var pillBackground: some View {
        RoundedRectangle(cornerRadius: 22)
            .fill(.ultraThinMaterial)
            .blur(radius: 0.5)
    }

    private var borderColor: Color {
        switch coordinator.state {
        case .recording: return .red.opacity(0.4)
        case .connecting: return .orange.opacity(0.3)
        case .processing: return .yellow.opacity(0.3)
        case .injecting: return .green.opacity(0.4)
        case .speaking: return .green.opacity(0.3)
        case .error: return .red.opacity(0.3)
        default: return .white.opacity(0.1)
        }
    }

    private var shadowColor: Color {
        switch coordinator.state {
        case .recording: return .red.opacity(0.2)
        default: return .black.opacity(0.15)
        }
    }

    // MARK: - Animations

    private func appearAnimation() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            opacity = 1
        }
    }

    private func disappearAnimation() {
        withAnimation(.easeOut(duration: 0.25)) {
            opacity = 0
        }
    }
}

// MARK: - Window Controller

/// Manages the floating pill as a borderless, always-on-top window.
final class FloatingPillWindowController {
    private var window: NSWindow?
    private weak var coordinator: AppCoordinator?

    func show(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        guard window == nil else { return }
        rebuildWindow()
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }

    private func rebuildWindow() {
        guard let coordinator else { return }

        let screen = NSScreen.main!
        let width: CGFloat = 420
        let height: CGFloat = 52
        let x = (screen.frame.width - width) / 2
        let y = screen.frame.height - 100

        let win = NSWindow(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = .floating
        win.ignoresMouseEvents = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.isReleasedWhenClosed = false

        let hostingView = NSHostingView(rootView: FloatingPill(coordinator: coordinator))
        hostingView.frame = win.contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        win.contentView?.addSubview(hostingView)

        win.orderFrontRegardless()
        self.window = win
    }
}
