import SwiftUI

struct VirtualFixtureView: View {
    let label: String
    let color: Color
    let intensity: Double

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Dim base circle always visible so you can see the fixture
                Circle()
                    .fill(color.opacity(0.08))
                    .frame(width: 60, height: 60)

                // Active glow driven by intensity
                Circle()
                    .fill(color.opacity(intensity))
                    .frame(width: 60, height: 60)
                    .shadow(
                        color: color.opacity(intensity * 0.8),
                        radius: 40 * intensity
                    )
                    .shadow(
                        color: color.opacity(intensity * 0.4),
                        radius: 80 * intensity
                    )
            }

            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}
