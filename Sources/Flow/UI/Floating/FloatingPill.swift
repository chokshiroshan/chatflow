import SwiftUI

// MARK: - Screen Helper

extension NSScreen {
    static var screenWithMouse: NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
    }
}

/// Floating pill overlay — futuristic spacey design.
///
/// States: hidden → listening (waveform) → processing (spinner) → done (checkmark fade)
struct FloatingPill: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var dragOffset: CGSize = .zero
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.8
    @State private var waveOffset: CGFloat = 0
    @State private var dotScales: [CGFloat] = Array(repeating: 0.6, count: 7)
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
        HStack(spacing: 10) {
            // Status indicator dot
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)
                .flowGlow(stateColor, radius: 6)

            // Waveform bars
            HStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { i in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [stateColor, stateColor.opacity(0.6)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .frame(width: 3, height: 20 * dotScales[i])
                        .animation(.easeInOut(duration: 0.12), value: dotScales[i])
                }
            }
            .frame(height: 28)

            // Status label
            Text(stateLabel)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(FlowColors.textSecondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(pillBackground)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(FlowColors.borderHover, lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 16, x: 0, y: 4)
        .shadow(color: stateColor.opacity(0.15), radius: 12, x: 0, y: 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gesture(
            DragGesture()
                .onChanged { value in
                    withAnimation(.interactiveSpring()) {
                        dragOffset = value.translation
                    }
                }
        )
    }

    // MARK: - State Colors & Labels

    private var stateColor: Color {
        switch coordinator.state {
        case .recording:  return FlowColors.accent
        case .connecting: return FlowColors.accentOrange
        case .processing: return FlowColors.accentPurple
        case .injecting:  return FlowColors.accentGreen
        case .speaking:   return FlowColors.accentGreen
        case .error:      return Color(red: 1.0, green: 0.35, blue: 0.35)
        default:          return FlowColors.textTertiary
        }
    }

    private var stateLabel: String {
        switch coordinator.state {
        case .recording:  return "Listening"
        case .connecting: return "Connecting"
        case .processing: return "Transcribing"
        case .injecting:  return "Pasting"
        case .speaking:   return "Speaking"
        case .error:      return "Error"
        default:          return ""
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var pillBackground: some View {
        Capsule()
            .fill(Color(red: 0.08, green: 0.10, blue: 0.18).opacity(0.92))
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
            for i in 0..<7 {
                let phase = waveOffset + Double(i) * 0.7
                dotScales[i] = 0.3 + 0.7 * abs(sin(phase))
            }
        } else if coordinator.state == .connecting || coordinator.state == .processing {
            waveOffset += 0.15
            for i in 0..<7 {
                let phase = waveOffset + Double(i) * 0.4
                dotScales[i] = 0.5 + 0.3 * abs(sin(phase))
            }
        } else {
            for i in 0..<7 {
                dotScales[i] = 0.4
            }
        }
    }
}

// MARK: - Window Controller

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

        let screen = NSScreen.screenWithMouse ?? NSScreen.main!
        let width: CGFloat = 200
        let height: CGFloat = 52
        let x = screen.frame.origin.x + (screen.frame.width - width) / 2
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

        let wrapper = NSView(frame: NSRect(origin: .zero, size: NSSize(width: width, height: height)))
        wrapper.wantsLayer = true
        wrapper.layer?.backgroundColor = .clear
        wrapper.layer?.masksToBounds = false

        let hostingView = NSHostingView(rootView: FloatingPill(coordinator: coordinator))
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hostingView.autoresizingMask = [.width, .height]
        wrapper.addSubview(hostingView)

        panel.contentView?.addSubview(wrapper)
        panel.orderFrontRegardless()
        self.window = panel
    }
}
