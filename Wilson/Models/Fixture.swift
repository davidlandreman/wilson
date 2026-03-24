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

/// A patched fixture instance on stage — a specific fixture at a specific DMX address.
@Model
final class PatchedFixture {
    var label: String
    var profile: FixtureProfile?
    var dmxAddress: Int // 1–512
    var groupName: String?
    var positionX: Double
    var positionY: Double

    init(label: String, profile: FixtureProfile? = nil, dmxAddress: Int, groupName: String? = nil, positionX: Double = 0, positionY: Double = 0) {
        self.label = label
        self.profile = profile
        self.dmxAddress = dmxAddress
        self.groupName = groupName
        self.positionX = positionX
        self.positionY = positionY
    }
}
