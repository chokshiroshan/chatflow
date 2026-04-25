import SwiftUI

/// A small popup that appears near the text field when a vocabulary correction is detected.
///
/// Shows: "Save 'wispr' → 'Wispr' to vocabulary?"
/// Buttons: [Save] [Dismiss]
///
/// Design principles:
/// - Non-intrusive: appears at the cursor position, doesn't steal focus
/// - Auto-dismisses after 8 seconds
/// - Compact — single line + two small buttons
/// - Dark glass aesthetic matching the floating pill
struct VocabSuggestionPopup: View {
    let changes: [EditDiff.WordChange]
    let onSave: (EditDiff.WordChange) -> Void
    let onDismiss: () -> Void

    @State private var currentIndex = 0
    @State private var opacity: Double = 0
    @State private var dismissTimer: Timer?

    private var currentChange: EditDiff.WordChange? {
        guard currentIndex < changes.count else { return nil }
        return changes[currentIndex]
    }

    var body: some View {
        if let change = currentChange {
            HStack(spacing: 10) {
                // Icon
                Image(systemName: "text.badge.checkmark")
                    .font(.system(size: 13))
                    .foregroundColor(FlowColors.accent)

                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text("Save correction?")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(FlowColors.textSecondary)
                    HStack(spacing: 4) {
                        Text(change.original)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.red.opacity(0.8))
                            .strikethrough()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9))
                            .foregroundColor(FlowColors.textTertiary)
                        Text(change.corrected)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(FlowColors.accent)
                    }
                }

                Spacer()

                // Buttons
                HStack(spacing: 6) {
                    Button(action: saveCurrent) {
                        Text("Save")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(FlowColors.accent)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(FlowColors.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            )
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.3)) { opacity = 1 }
                scheduleAutoDismiss()
            }
        }
    }

    // MARK: - Actions

    private func saveCurrent() {
        guard let change = currentChange else { return }
        onSave(change)

        // Move to next change if there are more
        if currentIndex + 1 < changes.count {
            currentIndex += 1
        } else {
            dismiss()
        }
    }

    private func dismiss() {
        dismissTimer?.invalidate()
        withAnimation(.easeOut(duration: 0.2)) {
            opacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }

    private func scheduleAutoDismiss() {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { _ in
            dismiss()
        }
    }
}

// MARK: - Window Controller

/// Manages the vocabulary suggestion popup as a floating NSPanel.
@MainActor
final class VocabSuggestionWindowController {
    private var window: NSPanel?

    func show(changes: [EditDiff.WordChange], onSave: @escaping (EditDiff.WordChange) -> Void) {
        // Close existing if any
        close()

        guard !changes.isEmpty else { return }

        let width: CGFloat = 340
        let height: CGFloat = 56

        // Position near the cursor (where the user is editing)
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screenWithMouse ?? NSScreen.main!
        let x = min(
            max(mouseLocation.x - width / 2, screen.visibleFrame.origin.x + 8),
            screen.visibleFrame.maxX - width - 8
        )
        let y = min(
            mouseLocation.y + 30,
            screen.visibleFrame.maxY - height - 8
        )

        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let view = VocabSuggestionPopup(
            changes: changes,
            onSave: { change in
                VocabularyManager.shared.addEntry(
                    original: change.original,
                    correction: change.corrected
                )
                onSave(change)
            },
            onDismiss: { [weak self] in
                self?.close()
            }
        )

        panel.contentView = NSHostingView(rootView: view)
        panel.orderFrontRegardless()
        self.window = panel

        print("📖 Showing vocabulary suggestion: \(changes.first!.original) → \(changes.first!.corrected)")
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }
}
