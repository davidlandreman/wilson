import Foundation
import SwiftData

/// Snapshot of a single fixture's attribute values within a scene.
struct DMXFixtureSnapshot: Codable, Sendable {
    var fixtureID: UUID
    /// Attribute rawValue → normalized value (0.0–1.0).
    /// Uses String keys because SwiftData requires Codable-friendly dictionary keys.
    var attributes: [String: Double]

    init(fixtureID: UUID, attributes: [FixtureAttribute: Double]) {
        self.fixtureID = fixtureID
        self.attributes = Dictionary(uniqueKeysWithValues: attributes.map { ($0.key.rawValue, $0.value) })
    }

    /// Reconstructs typed attribute dictionary.
    var typedAttributes: [FixtureAttribute: Double] {
        Dictionary(uniqueKeysWithValues: attributes.compactMap { key, value in
            FixtureAttribute(rawValue: key).map { ($0, value) }
        })
    }
}

/// A saved lighting scene — a snapshot of all fixture fader positions.
@Model
final class DMXScene {
    var name: String
    var createdAt: Date
    var grandMaster: Double
    var fixtureSnapshots: [DMXFixtureSnapshot]

    init(name: String, grandMaster: Double, fixtureSnapshots: [DMXFixtureSnapshot]) {
        self.name = name
        self.createdAt = Date()
        self.grandMaster = grandMaster
        self.fixtureSnapshots = fixtureSnapshots
    }
}
