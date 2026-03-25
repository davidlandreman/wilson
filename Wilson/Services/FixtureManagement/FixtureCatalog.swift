import Foundation

/// Hardcoded catalog of available fixture types.
enum FixtureCatalog {
    static let genericStrobe = FixtureDefinition(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Generic Strobe",
        manufacturer: "Generic",
        channels: [
            ChannelDefinition(offset: 0, attribute: .dimmer, defaultValue: 0),
        ]
    )

    static let genericRGBPar = FixtureDefinition(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Generic RGB Par",
        manufacturer: "Generic",
        channels: [
            ChannelDefinition(offset: 0, attribute: .dimmer, defaultValue: 0),
            ChannelDefinition(offset: 1, attribute: .red, defaultValue: 0),
            ChannelDefinition(offset: 2, attribute: .green, defaultValue: 0),
            ChannelDefinition(offset: 3, attribute: .blue, defaultValue: 0),
        ]
    )

    static let all: [FixtureDefinition] = [genericStrobe, genericRGBPar]
}
