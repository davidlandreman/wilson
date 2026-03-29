import SwiftUI

/// A vertical strip of faders for one fixture, styled like a console channel strip.
/// Shows color preview, one fader per attribute, and a flash button.
struct FixtureFaderStripView: View {
    let fixture: StageFixture
    @Binding var values: [FixtureAttribute: Double]
    let onFaderChanged: (FixtureAttribute, Double) -> Void
    let onFlashDown: () -> Void
    let onFlashUp: () -> Void

    /// Ordered list of attributes this fixture supports, in console-standard order.
    private var orderedAttributes: [FixtureAttribute] {
        let order: [FixtureAttribute] = [
            .dimmer, .red, .green, .blue, .white, .amber, .uv,
            .pan, .tilt, .panFine, .tiltFine,
            .gobo, .strobe, .colorWheel, .prism, .speed, .focus, .zoom, .mode, .custom,
        ]
        return order.filter { fixture.attributes.contains($0) }
    }

    var body: some View {
        VStack(spacing: 6) {
            // Color preview swatch
            colorPreview
                .frame(width: 36, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 3))

            // Attribute faders
            HStack(spacing: 2) {
                ForEach(orderedAttributes, id: \.self) { attr in
                    VerticalFaderView(
                        value: binding(for: attr),
                        label: shortLabel(for: attr),
                        tint: tintColor(for: attr)
                    )
                }
            }

            // Flash button
            Text("FL")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 22)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color.orange.opacity(0.4)))
                .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                    if pressing {
                        onFlashDown()
                    } else {
                        onFlashUp()
                    }
                }, perform: {})

            // Fixture label
            Text(fixture.label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.2))
        )
    }

    // MARK: - Color Preview

    @ViewBuilder
    private var colorPreview: some View {
        let r = values[.red] ?? 0
        let g = values[.green] ?? 0
        let b = values[.blue] ?? 0
        let dimmer = values[.dimmer] ?? 0

        if fixture.attributes.contains(.red) {
            Color(red: r * dimmer, green: g * dimmer, blue: b * dimmer)
        } else {
            Color.white.opacity(dimmer)
        }
    }

    // MARK: - Helpers

    private func binding(for attr: FixtureAttribute) -> Binding<Double> {
        Binding(
            get: { values[attr] ?? 0 },
            set: { newValue in
                onFaderChanged(attr, newValue)
            }
        )
    }

    private func shortLabel(for attr: FixtureAttribute) -> String {
        switch attr {
        case .dimmer: "Dim"
        case .red: "R"
        case .green: "G"
        case .blue: "B"
        case .white: "W"
        case .amber: "A"
        case .uv: "UV"
        case .pan: "Pan"
        case .tilt: "Tlt"
        case .panFine: "PnF"
        case .tiltFine: "TlF"
        case .gobo: "Gbo"
        case .strobe: "Stb"
        case .colorWheel: "CW"
        case .prism: "Prm"
        case .speed: "Spd"
        case .focus: "Foc"
        case .zoom: "Zm"
        case .mode: "Mod"
        case .custom: "Cst"
        }
    }

    private func tintColor(for attr: FixtureAttribute) -> Color {
        switch attr {
        case .dimmer: .white
        case .red: .red
        case .green: .green
        case .blue: .blue
        case .white: .white
        case .amber: .orange
        case .uv: .purple
        case .pan, .panFine: .yellow
        case .tilt, .tiltFine: .yellow
        case .strobe: .white
        default: .gray
        }
    }
}
