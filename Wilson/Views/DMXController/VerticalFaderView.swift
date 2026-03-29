import SwiftUI

/// A custom vertical fader control styled like a physical console channel strip.
/// Supports drag gesture for primary interaction and scroll wheel for fine adjustment.
struct VerticalFaderView: View {
    @Binding var value: Double // 0.0–1.0
    var label: String
    var tint: Color = .white
    var showValue: Bool = true

    private let trackWidth: CGFloat = 32
    private let trackHeight: CGFloat = 160
    private let knobHeight: CGFloat = 16

    var dmxValue: UInt8 { UInt8(max(0, min(255, value * 255))) }

    var body: some View {
        VStack(spacing: 4) {
            if showValue {
                Text("\(dmxValue)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: trackWidth)
            }

            // Fader track + knob
            GeometryReader { geo in
                let availableHeight = geo.size.height - knobHeight
                let knobY = (1.0 - value) * availableHeight

                ZStack(alignment: .top) {
                    // Track background
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 6)
                        .frame(maxHeight: .infinity)

                    // Filled portion (below knob)
                    VStack {
                        Spacer()
                            .frame(height: knobY + knobHeight / 2)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(tint.opacity(0.6))
                            .frame(width: 6)
                        Spacer()
                            .frame(height: 0)
                    }

                    // Knob
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [Color.gray.opacity(0.9), Color.gray.opacity(0.5)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(tint.opacity(0.8), lineWidth: 1)
                        )
                        .frame(width: trackWidth, height: knobHeight)
                        .offset(y: knobY)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let normalized = 1.0 - ((drag.location.y - knobHeight / 2) / availableHeight)
                            value = max(0, min(1, normalized))
                        }
                )
            }
            .frame(width: trackWidth, height: trackHeight)
            .onScrollWheelGesture { delta in
                value = max(0, min(1, value + delta * 0.01))
            }

            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: trackWidth + 8)
        }
    }
}

// MARK: - Scroll Wheel Support

private struct ScrollWheelModifier: ViewModifier {
    let action: (Double) -> Void

    func body(content: Content) -> some View {
        content.background(
            ScrollWheelReceiver(action: action)
        )
    }
}

private struct ScrollWheelReceiver: NSViewRepresentable {
    let action: (Double) -> Void

    func makeNSView(context: Context) -> ScrollWheelNSView {
        let view = ScrollWheelNSView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.action = action
    }
}

private class ScrollWheelNSView: NSView {
    var action: ((Double) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        action?(Double(event.scrollingDeltaY))
    }
}

extension View {
    func onScrollWheelGesture(action: @escaping (Double) -> Void) -> some View {
        modifier(ScrollWheelModifier(action: action))
    }
}
