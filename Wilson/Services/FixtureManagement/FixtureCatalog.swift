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

    static let genericMovingHeadRGB = FixtureDefinition(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Generic Moving Head RGB",
        manufacturer: "Generic",
        channels: [
            ChannelDefinition(offset: 0, attribute: .dimmer, defaultValue: 0),
            ChannelDefinition(offset: 1, attribute: .red, defaultValue: 0),
            ChannelDefinition(offset: 2, attribute: .green, defaultValue: 0),
            ChannelDefinition(offset: 3, attribute: .blue, defaultValue: 0),
            ChannelDefinition(offset: 4, attribute: .pan, defaultValue: 128),
            ChannelDefinition(offset: 5, attribute: .tilt, defaultValue: 128),
        ]
    )

    // MARK: - MINGJIE 60W Moving Head Spot (8 colors + white, 8 gobos)
    // Channel order verified against Open Fixture Library (SHEHDS LED Spot 60W).
    // Color wheel: 0-9 White, 10-19 Red, 20-29 Orange, 30-39 Yellow,
    //              40-49 Green, 50-59 Blue, 60-69 Pink, 70-79 Sky Blue,
    //              80-139 split colors, 140-255 rainbow rotation.

    /// 11-channel mode: fine pan/tilt control. Set fixture display to "11CH" mode.
    static let mingjie60wSpot11ch = FixtureDefinition(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
        name: "MINGJIE 60W Spot (11ch)",
        manufacturer: "MINGJIE",
        channels: [
            ChannelDefinition(offset: 0, attribute: .pan, defaultValue: 128),
            ChannelDefinition(offset: 1, attribute: .panFine, defaultValue: 0),
            ChannelDefinition(offset: 2, attribute: .tilt, defaultValue: 128),
            ChannelDefinition(offset: 3, attribute: .tiltFine, defaultValue: 0),
            ChannelDefinition(offset: 4, attribute: .colorWheel, defaultValue: 0),
            ChannelDefinition(offset: 5, attribute: .gobo, defaultValue: 0),
            ChannelDefinition(offset: 6, attribute: .strobe, defaultValue: 0),
            ChannelDefinition(offset: 7, attribute: .dimmer, defaultValue: 0),
            ChannelDefinition(offset: 8, attribute: .speed, defaultValue: 0),
            ChannelDefinition(offset: 9, attribute: .mode, defaultValue: 0),
            ChannelDefinition(offset: 10, attribute: .custom, defaultValue: 0), // Reset
        ]
    )

    /// 9-channel mode: no fine pan/tilt. Set fixture display to "9CH" mode.
    static let mingjie60wSpot9ch = FixtureDefinition(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
        name: "MINGJIE 60W Spot (9ch)",
        manufacturer: "MINGJIE",
        channels: [
            ChannelDefinition(offset: 0, attribute: .pan, defaultValue: 128),
            ChannelDefinition(offset: 1, attribute: .tilt, defaultValue: 128),
            ChannelDefinition(offset: 2, attribute: .colorWheel, defaultValue: 0),
            ChannelDefinition(offset: 3, attribute: .gobo, defaultValue: 0),
            ChannelDefinition(offset: 4, attribute: .strobe, defaultValue: 0),
            ChannelDefinition(offset: 5, attribute: .dimmer, defaultValue: 0),
            ChannelDefinition(offset: 6, attribute: .speed, defaultValue: 0),
            ChannelDefinition(offset: 7, attribute: .mode, defaultValue: 0),
            ChannelDefinition(offset: 8, attribute: .custom, defaultValue: 0), // Reset
        ]
    )

    // MARK: - Betopper LF4808 260W Matrix Strobe (48 RGB zones + 8 white zones)

    /// 4-channel mode: simple RGBW. Set fixture display to "4CH" mode.
    static let betopperLF4808_4ch = FixtureDefinition(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
        name: "Betopper LF4808 Matrix Strobe (4ch)",
        manufacturer: "Betopper",
        channels: [
            ChannelDefinition(offset: 0, attribute: .red, defaultValue: 0),
            ChannelDefinition(offset: 1, attribute: .green, defaultValue: 0),
            ChannelDefinition(offset: 2, attribute: .blue, defaultValue: 0),
            ChannelDefinition(offset: 3, attribute: .white, defaultValue: 0),
        ]
    )

    /// 15-channel mode: full control with strobe, patterns, background. Set fixture display to "15CH" mode.
    static let betopperLF4808_15ch = FixtureDefinition(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
        name: "Betopper LF4808 Matrix Strobe (15ch)",
        manufacturer: "Betopper",
        channels: [
            ChannelDefinition(offset: 0, attribute: .dimmer, defaultValue: 0),      // Aiming
            ChannelDefinition(offset: 1, attribute: .red, defaultValue: 0),
            ChannelDefinition(offset: 2, attribute: .green, defaultValue: 0),
            ChannelDefinition(offset: 3, attribute: .blue, defaultValue: 0),
            ChannelDefinition(offset: 4, attribute: .white, defaultValue: 0),
            ChannelDefinition(offset: 5, attribute: .custom, defaultValue: 0),       // Pigment
            ChannelDefinition(offset: 6, attribute: .custom, defaultValue: 0),       // RGB pattern
            ChannelDefinition(offset: 7, attribute: .speed, defaultValue: 0),        // RGB velocity
            ChannelDefinition(offset: 8, attribute: .custom, defaultValue: 0),       // W pattern
            ChannelDefinition(offset: 9, attribute: .speed, defaultValue: 0),        // W velocity
            ChannelDefinition(offset: 10, attribute: .strobe, defaultValue: 0),      // RGBW strobe
            ChannelDefinition(offset: 11, attribute: .custom, defaultValue: 0),      // RGBW pattern
            ChannelDefinition(offset: 12, attribute: .speed, defaultValue: 0),       // RGBW velocity
            ChannelDefinition(offset: 13, attribute: .custom, defaultValue: 0),      // Background color
            ChannelDefinition(offset: 14, attribute: .custom, defaultValue: 0),      // Background color light
        ]
    )

    static let all: [FixtureDefinition] = [
        genericStrobe,
        genericRGBPar,
        genericMovingHeadRGB,
        mingjie60wSpot11ch,
        mingjie60wSpot9ch,
        betopperLF4808_4ch,
        betopperLF4808_15ch,
    ]
}
