import SwiftUI

/// Raw DMX channel fader view showing 24 channels per bank.
/// Maps channels back to fixture attributes for editing.
struct ChannelFaderView: View {
    let controller: DMXControllerService
    let fixtures: [StageFixture]
    let engine: DecisionEngineService
    @Binding var currentBank: Int

    /// Flat list of (fixture, channelDef) pairs representing all DMX channels in order.
    private var channelMap: [(fixture: StageFixture, channel: ChannelDefinition, absoluteChannel: Int)] {
        var result: [(StageFixture, ChannelDefinition, Int)] = []
        var nextChannel = 1
        for fixture in fixtures {
            for chDef in fixture.definition.channels.sorted(by: { $0.offset < $1.offset }) {
                result.append((fixture, chDef, nextChannel))
                nextChannel += 1
            }
        }
        return result
    }

    private var bankChannels: [(fixture: StageFixture, channel: ChannelDefinition, absoluteChannel: Int)] {
        let start = currentBank * DMXControllerService.channelsPerBank
        let end = min(start + DMXControllerService.channelsPerBank, channelMap.count)
        guard start < channelMap.count else { return [] }
        return Array(channelMap[start..<end])
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: 4) {
                ForEach(Array(bankChannels.enumerated()), id: \.offset) { _, entry in
                    VStack(spacing: 4) {
                        // Channel number
                        Text("Ch \(entry.absoluteChannel)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)

                        // Fader
                        VerticalFaderView(
                            value: Binding(
                                get: {
                                    controller.fixtureValues[entry.fixture.id]?[entry.channel.attribute] ?? 0
                                },
                                set: { newValue in
                                    controller.setFader(
                                        fixtureID: entry.fixture.id,
                                        attribute: entry.channel.attribute,
                                        value: newValue,
                                        engine: engine
                                    )
                                }
                            ),
                            label: shortLabel(entry.channel.attribute),
                            tint: tintColor(entry.channel.attribute)
                        )

                        // Fixture name
                        Text(entry.fixture.label)
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .frame(width: 40)
                    }
                }
            }
            .padding(12)
        }
        .frame(maxHeight: .infinity)
    }

    private func shortLabel(_ attr: FixtureAttribute) -> String {
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
        default: String(attr.rawValue.prefix(3)).capitalized
        }
    }

    private func tintColor(_ attr: FixtureAttribute) -> Color {
        switch attr {
        case .dimmer: .white
        case .red: .red
        case .green: .green
        case .blue: .blue
        case .white: .white
        case .amber: .orange
        case .uv: .purple
        case .pan, .tilt: .yellow
        default: .gray
        }
    }
}
