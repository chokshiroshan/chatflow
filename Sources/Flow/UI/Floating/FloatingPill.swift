import SwiftUI

// MARK: - Screen Helper

extension NSScreen {
    /// Find the screen that currently has the mouse cursor.
    static var screenWithMouse: NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
    }
}

/// Premium floating pill overlay — Wispr Flow-inspired design.
///
/// Design principles:
/// - Minimal, dark glass aesthetic
/// - Smooth sine-wave animation (not static bars)
/// - Capsule shape with subtle gradient border
/// - Bottom-center of screen (like Wispr Flow)
/// - Draggable to reposition
/// - States: hidden → listening (waveform) → processing (spinner) → done (checkmark fade)
struct FloatingPill: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var dragOffset: CGSize = .zero
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.8
    @State private var waveOffset: CGFloat = 0
    @State private var dotScales: [CGFloat] = Array(repeating: 0.6, count: 5)
    @State private var timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if shouldShow {
                pillContent
                    .opacity(opacity)
                    .scaleEffect(scale)
                    .offset(dragOffset)
                    .onAppear { appearAnimation() }
                    .onDisappear { disappearAnimation() }
                    .onChange(of: shouldShow) { _, showing in
                        if showing { appearAnimation() } else { disappearAnimation() }
                    }
                    .onReceive(timer) { _ in
                        updateWaveAnimation()
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var shouldShow: Bool {
        coordinator.state.isActive || coordinator.state == .connecting
    }

    // MARK: - Pill Content

    @ViewBuilder
    private var pillContent: some View {
        waveIcon
            .frame(width: 24, height: 24)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(pillBackground)
            .clipShape(Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity)  // Center in panel
            .gesture(
                DragGesture()
                    .onChanged { value in
                        withAnimation(.interactiveSpring()) {
                            dragOffset = value.translation
                        }
                    }
            )
    }

    // MARK: - Wave Icon

    @ViewBuilder
    private var waveIcon: some View {
        ZStack {
            // Animated dots (sine wave pattern)
            HStack(spacing: 2.5) {
                ForEach(0..<5, id: \.self) { i in
                    Capsule()
                        .fill(iconColor)
                        .frame(width: 2.5, height: 14 * dotScales[i])
                        .animation(.easeInOut(duration: 0.12), value: dotScales[i])
                }
            }
        }
    }

    private var iconColor: Color {
        switch coordinator.state {
        case .recording: return coordinator.isEnhancedMode ? FlowColors.accentOrange : FlowColors.accent
        case .connecting: return FlowColors.accentOrange
        case .processing: return FlowColors.accentPurple
        case .injecting: return FlowColors.accentGreen
        case .speaking: return FlowColors.accentGreen
        case .error: return Color(red: 1.0, green: 0.35, blue: 0.35)
        default: return FlowColors.textTertiary
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var pillBackground: some View {
        Capsule()
            .fill(.ultraThinMaterial)
    }

    // MARK: - Animations

    private func appearAnimation() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            opacity = 1
            scale = 1.0
        }
    }

    private func disappearAnimation() {
        withAnimation(.easeOut(duration: 0.2)) {
            opacity = 0
            scale = 0.9
        }
    }

    private func updateWaveAnimation() {
        if coordinator.state == .recording {
            waveOffset += 0.3
            for i in 0..<5 {
                let phase = waveOffset + Double(i) * 0.8
                dotScales[i] = 0.3 + 0.7 * abs(sin(phase))
            }
        } else if coordinator.state == .connecting || coordinator.state == .processing {
            waveOffset += 0.15
            for i in 0..<5 {
                let phase = waveOffset + Double(i) * 0.5
                dotScales[i] = 0.5 + 0.3 * abs(sin(phase))
            }
        } else {
            for i in 0..<5 {
                dotScales[i] = 0.4
            }
        }
    }
}

// MARK: - Window Controller

/// Manages the floating pill as a borderless, always-on-top NSPanel.
final class FloatingPillWindowController {
    private var window: NSPanel?
    private weak var coordinator: AppCoordinator?

    func show(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        guard window == nil else { return }
        rebuildWindow()
        print("🟢 Floating pill window shown")
    }

    func reposition() {
        // Rebuild on the active screen
        window?.orderOut(nil)
        window = nil
        rebuildWindow()
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }

    private func rebuildWindow() {
        guard let coordinator else { return }

        // Use the screen that currently has the mouse cursor
        let screen = NSScreen.screenWithMouse ?? NSScreen.main!
        let width: CGFloat = 64
        let height: CGFloat = 56
        let x = screen.frame.origin.x + (screen.frame.width - width) / 2
        // Position above the dock — use visibleFrame which excludes dock
        let y = screen.visibleFrame.origin.y + 12

        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar + 1
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        // Use a wrapper view that doesn't clip to bounds
        let wrapper = NSView(frame: NSRect(origin: .zero, size: NSSize(width: width, height: height)))
        wrapper.wantsLayer = true
        wrapper.layer?.backgroundColor = .clear
        wrapper.layer?.masksToBounds = false  // Don't clip!

        let hostingView = NSHostingView(rootView: FloatingPill(coordinator: coordinator))
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hostingView.autoresizingMask = [.width, .height]
        wrapper.addSubview(hostingView)

        panel.contentView?.addSubview(wrapper)
        panel.orderFrontRegardless()
        self.window = panel
    }
}
