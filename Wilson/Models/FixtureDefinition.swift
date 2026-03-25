import Foundation

/// A lightweight runtime fixture profile describing a type of lighting fixture.
/// Reuses ChannelDefinition and FixtureAttribute from Fixture.swift.
struct FixtureDefinition: Identifiable, Sendable, Hashable {
    let id: UUID
    let name: String
    let manufacturer: String
    let channels: [ChannelDefinition]

    var channelCount: Int { channels.count }
    var attributes: Set<FixtureAttribute> { Set(channels.map(\.attribute)) }

    static func == (lhs: FixtureDefinition, rhs: FixtureDefinition) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
