import SwiftUI

// MARK: - Flow Design System
// Spacey · Futuristic · Minimal

// MARK: - Color Tokens

enum FlowColors {
    // Backgrounds
    static let background      = Color(red: 0.04, green: 0.06, blue: 0.12)      // Deep space navy
    static let surface         = Color(red: 0.08, green: 0.10, blue: 0.18)      // Slightly lighter
    static let card            = Color(red: 0.12, green: 0.14, blue: 0.22)      // Card surfaces
    static let cardHover       = Color(red: 0.15, green: 0.18, blue: 0.28)

    // Accent
    static let accent          = Color(red: 0.34, green: 0.83, blue: 1.0)       // Bright cyan #57D4FF
    static let accentPurple    = Color(red: 0.56, green: 0.38, blue: 1.0)       // Electric purple
    static let accentGreen     = Color(red: 0.25, green: 0.88, blue: 0.55)      // Success green
    static let accentOrange    = Color(red: 1.0, green: 0.65, blue: 0.25)       // Warning orange

    // Text
    static let textPrimary     = Color.white.opacity(0.95)
    static let textSecondary   = Color.white.opacity(0.60)
    static let textTertiary    = Color.white.opacity(0.35)

    // Borders
    static let border         = Color.white.opacity(0.08)
    static let borderHover    = Color.white.opacity(0.14)

    // Gradients
    static let accentGradient = LinearGradient(
        colors: [accent, accentPurple],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let heroGradient = LinearGradient(
        colors: [
            Color(red: 0.12, green: 0.18, blue: 0.35),
            Color(red: 0.06, green: 0.08, blue: 0.16),
            Color(red: 0.15, green: 0.08, blue: 0.30)
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

// MARK: - Typography

enum FlowTypography {
    static let titleLarge  = Font.system(size: 28, weight: .heavy, design: .rounded)
    static let title       = Font.system(size: 22, weight: .heavy, design: .rounded)
    static let headline    = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let body        = Font.system(size: 14, weight: .regular, design: .rounded)
    static let bodyMedium  = Font.system(size: 14, weight: .medium, design: .rounded)
    static let caption     = Font.system(size: 12, weight: .medium, design: .rounded)
    static let overline    = Font.system(size: 11, weight: .bold, design: .rounded)
}

// MARK: - Spacing

enum FlowSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

// MARK: - Radii

enum FlowRadii {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
}

// MARK: - Glass Card Modifier

struct FlowGlassCard: ViewModifier {
    var cornerRadius: CGFloat = FlowRadii.lg
    var padding: CGFloat = FlowSpacing.md

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(FlowColors.border, lineWidth: 0.5)
            )
    }
}

extension View {
    func flowGlassCard(cornerRadius: CGFloat = FlowRadii.lg, padding: CGFloat = FlowSpacing.md) -> some View {
        modifier(FlowGlassCard(cornerRadius: cornerRadius, padding: padding))
    }
}

// MARK: - Glow Modifier

struct FlowGlow: ViewModifier {
    let color: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.shadow(color: color.opacity(0.5), radius: radius, x: 0, y: 0)
    }
}

extension View {
    func flowGlow(_ color: Color = FlowColors.accent, radius: CGFloat = 12) -> some View {
        modifier(FlowGlow(color: color, radius: radius))
    }
}

// MARK: - Navigation Bar (Consistent across all steps)

/// Fixed-height nav bar: Back on left, primary action on right.
/// All steps use the same 52pt height, same horizontal padding.
struct FlowNavBar<Primary: View>: View {
    let onBack: (() -> Void)?
    @ViewBuilder let primary: Primary

    var body: some View {
        HStack(alignment: .center) {
            // Back button — fixed width so it doesn't shift
            Group {
                if let onBack {
                    Button(action: onBack) {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(FlowColors.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: FlowRadii.sm)
                                .fill(FlowColors.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: FlowRadii.sm)
                                .stroke(FlowColors.border, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(width: 90) // Fixed width so it never shifts
                } else {
                    Color.clear.frame(width: 90) // Same width placeholder for first step
                }
            }

            Spacer()

            primary
        }
        .frame(height: 40) // Fixed height
    }
}

// MARK: - Primary Action Button

struct FlowButton: View {
    let title: String
    var icon: String? = nil
    var style: FlowButtonStyle = .primary
    var showsProgress: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    enum FlowButtonStyle {
        case primary       // Gradient filled
        case secondary     // Glass/outline
        case destructive   // Red
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if showsProgress {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(FlowTypography.bodyMedium)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(buttonBackground)
            .clipShape(RoundedRectangle(cornerRadius: FlowRadii.sm))
            .overlay(
                RoundedRectangle(cornerRadius: FlowRadii.sm)
                    .stroke(borderColor, lineWidth: style == .primary ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1.0)
    }

    @ViewBuilder
    private var buttonBackground: some View {
        switch style {
        case .primary:
            if disabled {
                FlowColors.card
            } else {
                LinearGradient(
                    colors: [FlowColors.accent, FlowColors.accentPurple],
                    startPoint: .leading, endPoint: .trailing
                )
            }
        case .secondary:
            FlowColors.card
        case .destructive:
            Color(red: 0.85, green: 0.22, blue: 0.22)
        }
    }

    private var borderColor: Color {
        switch style {
        case .primary: return .clear
        case .secondary: return FlowColors.borderHover
        case .destructive: return .clear
        }
    }
}

// MARK: - Section Header

struct FlowSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(FlowTypography.overline)
            .foregroundColor(FlowColors.textTertiary)
            .tracking(1.0)
    }
}

// MARK: - Step Dots (Onboarding)

struct FlowStepDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3)
                    .fill(i == current ? FlowColors.accent : FlowColors.textTertiary.opacity(0.5))
                    .frame(width: i == current ? 20 : 7, height: 7)
                    .animation(.easeInOut(duration: 0.3), value: current)
            }
        }
    }
}

// MARK: - OpenAI Logo (Clean geometric)

/// Accurate OpenAI logomark drawn with SwiftUI Path.
struct OpenAILogo: View {
    var color: Color = .white
    var lineWidth: CGFloat = 1.8

    var body: some View {
        Canvas { context, size in
            let cx = size.width / 2
            let cy = size.height / 2
            let scale = min(size.width, size.height) / 30 // Normalize to 30pt grid

            // The OpenAI logomark is a stylized hexagonal knot.
            // We draw it as a set of 6 interlocking petals around a center.
            let petalCount = 6
            let innerR = 4.0 * scale  // Inner radius
            let outerR = 10.0 * scale // Outer radius of petal tips
            let petalWidth = 3.2 * scale

            for i in 0..<petalCount {
                let angle = Double(i) * (.pi * 2 / Double(petalCount)) - .pi / 2
                let nextAngle = Double(i + 2) * (.pi * 2 / Double(petalCount)) - .pi / 2

                // Start point (inner)
                let sx = cx + innerR * cos(angle)
                let sy = cy + innerR * sin(angle)

                // End point (inner, offset by 2)
                let ex = cx + innerR * cos(nextAngle)
                let ey = cy + innerR * sin(nextAngle)

                // Control points for the petal curve (bulges outward)
                let midAngle = (angle + nextAngle) / 2
                let cpDist = outerR
                let cp1x = cx + cpDist * cos(angle + 0.4)
                let cp1y = cy + cpDist * sin(angle + 0.4)
                let cp2x = cx + cpDist * cos(nextAngle - 0.4)
                let cp2y = cy + cpDist * sin(nextAngle - 0.4)

                var petal = Path()
                petal.move(to: CGPoint(x: sx, y: sy))
                petal.addCurve(
                    to: CGPoint(x: ex, y: ey),
                    control1: CGPoint(x: cp1x, y: cp1y),
                    control2: CGPoint(x: cp2x, y: cp2y)
                )

                context.stroke(
                    petal,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
            }

            // Center dot
            var hub = Path()
            hub.addEllipse(in: CGRect(
                x: cx - 2.0 * scale,
                y: cy - 2.0 * scale,
                width: 4.0 * scale,
                height: 4.0 * scale
            ))
            context.fill(hub, with: .color(color))
        }
    }
}
