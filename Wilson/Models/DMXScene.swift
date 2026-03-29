import Foundation
import SwiftData

// MARK: - Scene Tag Enums

enum SceneEnergyLevel: String, Codable, Sendable, CaseIterable {
    case low, medium, high, any
}

enum SceneMood: String, Codable, Sendable, CaseIterable {
    case calm, uplifting, intense, dark, any
}

enum SceneTransitionStyle: String, Codable, Sendable, CaseIterable {
    case crossfade, snap, slowDissolve
}

// MARK: - Fixture Snapshot

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

// MARK: - Scene Model

/// A saved lighting scene — a snapshot of all fixture fader positions.
@Model
final class DMXScene {
    var name: String
    var createdAt: Date
    var grandMaster: Double
    var fixtureSnapshots: [DMXFixtureSnapshot]

    // Choreographer integration
    var reactivity: Double
    var energyLevel: SceneEnergyLevel
    var mood: SceneMood
    var isAutonomousEnabled: Bool
    var transitionStyle: SceneTransitionStyle
    var transitionDuration: Double

    init(
        name: String,
        grandMaster: Double,
        fixtureSnapshots: [DMXFixtureSnapshot],
        reactivity: Double = 0.5,
        energyLevel: SceneEnergyLevel = .any,
        mood: SceneMood = .any,
        isAutonomousEnabled: Bool = true,
        transitionStyle: SceneTransitionStyle = .crossfade,
        transitionDuration: Double = 2.0
    ) {
        self.name = name
        self.createdAt = Date()
        self.grandMaster = grandMaster
        self.fixtureSnapshots = fixtureSnapshots
        self.reactivity = reactivity
        self.energyLevel = energyLevel
        self.mood = mood
        self.isAutonomousEnabled = isAutonomousEnabled
        self.transitionStyle = transitionStyle
        self.transitionDuration = transitionDuration
    }

    /// Convert to a pipeline-safe Sendable snapshot.
    func toSnapshot() -> SceneSnapshot {
        var fixtureAttributes: [UUID: [FixtureAttribute: Double]] = [:]
        for snap in fixtureSnapshots {
            fixtureAttributes[snap.fixtureID] = snap.typedAttributes
        }
        return SceneSnapshot(
            name: name,
            reactivity: reactivity,
            energyLevel: energyLevel,
            mood: mood,
            transitionStyle: transitionStyle,
            transitionDuration: transitionDuration,
            grandMaster: grandMaster,
            fixtureAttributes: fixtureAttributes
        )
    }
}

// MARK: - Pipeline-Safe Snapshot

/// Lightweight Sendable copy of a DMXScene for use in the decision engine pipeline.
/// Pre-resolves fixture attributes to avoid repeated dictionary conversion in the hot path.
struct SceneSnapshot: Sendable, Equatable {
    let name: String
    let reactivity: Double
    let energyLevel: SceneEnergyLevel
    let mood: SceneMood
    let transitionStyle: SceneTransitionStyle
    let transitionDuration: Double
    let grandMaster: Double
    let fixtureAttributes: [UUID: [FixtureAttribute: Double]]

    static func == (lhs: SceneSnapshot, rhs: SceneSnapshot) -> Bool {
        lhs.name == rhs.name
    }
}
