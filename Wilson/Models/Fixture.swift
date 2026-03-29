import Foundation
import SwiftData

/// A fixture profile defines a type of lighting fixture and its DMX channel layout.
@Model
final class FixtureProfile {
    var name: String
    var manufacturer: String
    var channelCount: Int
    var channels: [ChannelDefinition]

    init(name: String, manufacturer: String, channelCount: Int, channels: [ChannelDefinition]) {
        self.name = name
        self.manufacturer = manufacturer
        self.channelCount = channelCount
        self.channels = channels
    }
}

/// Defines what a single DMX channel controls on a fixture.
struct ChannelDefinition: Codable, Sendable {
    var offset: Int
    var attribute: FixtureAttribute
    var defaultValue: UInt8
}

/// Classification of what a DMX channel controls.
enum FixtureAttribute: String, Codable, Sendable, CaseIterable {
    case dimmer
    case red, green, blue, white, amber, uv
    case pan, panFine
    case tilt, tiltFine
    case gobo
    case strobe
    case speed
    case mode
    case colorWheel
    case prism
    case focus
    case zoom
    case custom
}

/// A patched fixture instance on stage — persisted via SwiftData, converted to StageFixture at runtime.
@Model
final class PatchedFixture {
    /// Stable UUID that matches StageFixture.id across launches.
    var fixtureID: UUID = UUID()
    var label: String = ""
    var dmxAddress: Int = 0 // 1–512, or 0 for unpatched
    var isVirtual: Bool = true
    var positionX: Double = 0
    var positionY: Double = 0
    var trussSlot: Int = 0

    // Definition data stored directly so we're self-contained
    var definitionID: UUID = UUID()
    var definitionName: String = ""
    var definitionManufacturer: String = ""
    var definitionChannels: [ChannelDefinition] = []

    init(
        fixtureID: UUID,
        label: String,
        dmxAddress: Int = 0,
        isVirtual: Bool = true,
        positionX: Double = 0,
        positionY: Double = 0,
        trussSlot: Int = 0,
        definitionID: UUID,
        definitionName: String,
        definitionManufacturer: String,
        definitionChannels: [ChannelDefinition]
    ) {
        self.fixtureID = fixtureID
        self.label = label
        self.dmxAddress = dmxAddress
        self.isVirtual = isVirtual
        self.positionX = positionX
        self.positionY = positionY
        self.trussSlot = trussSlot
        self.definitionID = definitionID
        self.definitionName = definitionName
        self.definitionManufacturer = definitionManufacturer
        self.definitionChannels = definitionChannels
    }

    /// Convert to the runtime StageFixture used by the pipeline.
    func toStageFixture() -> StageFixture {
        let definition = FixtureDefinition(
            id: definitionID,
            name: definitionName,
            manufacturer: definitionManufacturer,
            channels: definitionChannels
        )
        return StageFixture(
            id: fixtureID,
            label: label,
            definition: definition,
            dmxAddress: dmxAddress > 0 ? dmxAddress : nil,
            isVirtual: isVirtual,
            position: SIMD2(positionX, positionY),
            trussSlot: trussSlot
        )
    }

    /// Create a PatchedFixture from a runtime StageFixture.
    static func from(_ fixture: StageFixture) -> PatchedFixture {
        PatchedFixture(
            fixtureID: fixture.id,
            label: fixture.label,
            dmxAddress: fixture.dmxAddress ?? 0,
            isVirtual: fixture.isVirtual,
            positionX: fixture.position.x,
            positionY: fixture.position.y,
            trussSlot: fixture.trussSlot,
            definitionID: fixture.definition.id,
            definitionName: fixture.definition.name,
            definitionManufacturer: fixture.definition.manufacturer,
            definitionChannels: fixture.definition.channels
        )
    }
}
