import SwiftUI

/// ChatFlow landing UI matching the web design thumbnail.
/// Blue background, glass card, waveform bars, macOS window controls.
struct ChatFlowLandingView: View {
    let onStart: () -> Void

    var body: some View {
        ZStack {
            // Background: #b5c9e8
            Color(red: 0.71, green: 0.79, blue: 0.91)
                .ignoresSafeArea()

            // Main card
            VStack(spacing: 0) {
                // Window header with macOS controls
                HStack(spacing: 8) {
                    Circle().fill(Color(red: 1.0, green: 0.45, blue: 0.42)).frame(width: 12, height: 12)
                    Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
                    Circle().fill(Color(red: 0.10, green: 0.76, blue: 0.20)).frame(width: 12, height: 12)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Spacer().frame(height: 60)

                // Waveform bars
                HStack(spacing: 5) {
                    let heights: [CGFloat] = [10, 22, 34, 42, 30, 38, 18, 26, 10]
                    let colors: [Color] = [
                        Color(red: 0.65, green: 0.55, blue: 0.98),
                        Color(red: 0.49, green: 0.23, blue: 0.93),
                    ]
                    ForEach(0..<9, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(colors[i % 2])
                            .frame(width: 8, height: heights[i])
                    }
                }
                .frame(height: 50)

                Spacer().frame(height: 24)

                // Title
                Text("ChatFlow")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Color.black.opacity(0.85))

                Text("Voice-to-text setup")
                    .font(.system(size: 12))
                    .foregroundColor(Color.black.opacity(0.45))
                    .padding(.top, 4)

                Spacer()

                // Get Started button
                Button(action: onStart) {
                    Text("Get Started")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 170, height: 38)
                        .background(Color(red: 0.0, green: 0.48, blue: 1.0))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)

                Spacer().frame(height: 30)
            }
            .frame(width: 400, height: 360)
            .background(Color.white.opacity(0.85))
            .cornerRadius(18)
            .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
