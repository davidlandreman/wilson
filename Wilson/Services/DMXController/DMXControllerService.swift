import Foundation

/// Manual DMX controller board service.
/// When active, takes over fixture output via the decision engine's override system.
@Observable
final class DMXControllerService {
    // MARK: - State

    private(set) var isActive = false

    /// Overall output intensity. Applied as a multiplier to all dimmer values.
    var grandMaster: Double = 1.0

    /// Instant all-off. When true, all output is zeroed regardless of fader positions.
    var isBlackout = false

    /// Per-fixture attribute fader values. Outer key = fixture ID, inner = attribute → 0.0–1.0.
    var fixtureValues: [UUID: [FixtureAttribute: Double]] = [:]

    /// Duration in seconds for scene crossfade transitions.
    var crossfadeDuration: Double = 2.0

    // MARK: - Flash

    /// Attributes currently being flashed (held at full).
    private(set) var flashStates: [UUID: Set<FixtureAttribute>] = [:]

    // MARK: - Crossfade

    private(set) var isCrossfading = false
    private var crossfadeStartValues: [UUID: [FixtureAttribute: Double]] = [:]
    private var crossfadeTargetValues: [UUID: [FixtureAttribute: Double]] = [:]
    private var crossfadeStartTime: Date?

    // MARK: - Submaster

    /// Scene persistent model ID (as string) → submaster fader level 0.0–1.0.
    var submasterScenes: [DMXScene] = []
    var submasterLevels: [String: Double] = [:]

    // MARK: - Bank Navigation (for raw channel view)

    var currentBank: Int = 0
    static let channelsPerBank: Int = 24

    // MARK: - Activate / Deactivate

    /// Activate manual control. Initializes fader positions from current engine states
    /// for smooth takeover (no jarring visual jump).
    func activate(fixtures: [StageFixture], currentStates: [UUID: FixtureState]) {
        fixtureValues = [:]
        for fixture in fixtures {
            if let state = currentStates[fixture.id] {
                fixtureValues[fixture.id] = state.attributes
            } else {
                // Initialize with defaults: dimmer off, colors at zero
                var defaults: [FixtureAttribute: Double] = [:]
                for attr in fixture.attributes {
                    defaults[attr] = 0
                }
                fixtureValues[fixture.id] = defaults
            }
        }
        isActive = true
    }

    /// Deactivate manual control. Removes all overrides so the autonomous engine resumes.
    func deactivate(engine: DecisionEngineService) {
        for fixtureID in fixtureValues.keys {
            engine.removeOverride(for: fixtureID)
        }
        isActive = false
        isCrossfading = false
        crossfadeStartTime = nil
        flashStates = [:]
    }

    // MARK: - Fader Control

    /// Update a single fader value and immediately push the override.
    func setFader(fixtureID: UUID, attribute: FixtureAttribute, value: Double, engine: DecisionEngineService) {
        fixtureValues[fixtureID, default: [:]][attribute] = max(0, min(1, value))
        pushOverride(for: fixtureID, engine: engine)
    }

    // MARK: - Flash

    /// Flash an attribute to full (called on mouse/key down).
    func flashDown(fixtureID: UUID, attribute: FixtureAttribute, engine: DecisionEngineService) {
        flashStates[fixtureID, default: []].insert(attribute)
        pushOverride(for: fixtureID, engine: engine)
    }

    /// Release a flash (called on mouse/key up).
    func flashUp(fixtureID: UUID, attribute: FixtureAttribute, engine: DecisionEngineService) {
        flashStates[fixtureID, default: []].remove(attribute)
        if flashStates[fixtureID]?.isEmpty == true {
            flashStates.removeValue(forKey: fixtureID)
        }
        pushOverride(for: fixtureID, engine: engine)
    }

    // MARK: - Scene Management

    /// Record the current fader state as a named scene.
    func recordScene(name: String) -> DMXScene {
        let snapshots = fixtureValues.map { fixtureID, attrs in
            DMXFixtureSnapshot(fixtureID: fixtureID, attributes: attrs)
        }
        return DMXScene(name: name, grandMaster: grandMaster, fixtureSnapshots: snapshots)
    }

    /// Recall a scene, optionally with crossfade.
    func recallScene(_ scene: DMXScene, crossfade: Bool, engine: DecisionEngineService) {
        let targetValues = sceneToFixtureValues(scene)

        if crossfade && crossfadeDuration > 0 {
            crossfadeStartValues = fixtureValues
            crossfadeTargetValues = targetValues
            crossfadeStartTime = Date()
            isCrossfading = true
        } else {
            fixtureValues = targetValues
            grandMaster = scene.grandMaster
            pushAllOverrides(engine: engine)
        }
    }

    /// Advance crossfade animation. Call from the refresh timer.
    func tickCrossfade(engine: DecisionEngineService) {
        guard isCrossfading, let startTime = crossfadeStartTime else { return }

        let elapsed = Date().timeIntervalSince(startTime)
        let t = min(1.0, elapsed / crossfadeDuration)

        // Lerp all attributes
        var interpolated: [UUID: [FixtureAttribute: Double]] = [:]
        let allFixtureIDs = Set(crossfadeStartValues.keys).union(crossfadeTargetValues.keys)

        for fixtureID in allFixtureIDs {
            let startAttrs = crossfadeStartValues[fixtureID] ?? [:]
            let targetAttrs = crossfadeTargetValues[fixtureID] ?? [:]
            let allAttrs = Set(startAttrs.keys).union(targetAttrs.keys)

            var attrs: [FixtureAttribute: Double] = [:]
            for attr in allAttrs {
                let from = startAttrs[attr] ?? 0
                let to = targetAttrs[attr] ?? 0
                attrs[attr] = from + (to - from) * t
            }
            interpolated[fixtureID] = attrs
        }

        fixtureValues = interpolated

        if t >= 1.0 {
            isCrossfading = false
            crossfadeStartTime = nil
            crossfadeStartValues = [:]
            crossfadeTargetValues = [:]
        }

        pushAllOverrides(engine: engine)
    }

    // MARK: - Override Building

    /// Build a FixtureState for one fixture from current faders, grand master, blackout, flash, and submasters.
    func buildFixtureState(for fixtureID: UUID) -> FixtureState {
        var attrs = fixtureValues[fixtureID] ?? [:]

        // Apply flash: flashed attributes go to full
        if let flashed = flashStates[fixtureID] {
            for attr in flashed {
                attrs[attr] = 1.0
            }
        }

        // HTP merge submasters
        for scene in submasterScenes {
            let sceneID = scene.name // Use name as key for simplicity
            guard let level = submasterLevels[sceneID], level > 0 else { continue }
            if let snapshot = scene.fixtureSnapshots.first(where: { $0.fixtureID == fixtureID }) {
                for (attr, value) in snapshot.typedAttributes {
                    let scaled = value * level
                    attrs[attr] = max(attrs[attr] ?? 0, scaled)
                }
            }
        }

        // Apply grand master to dimmer only
        if let dimmer = attrs[.dimmer] {
            attrs[.dimmer] = dimmer * grandMaster
        }

        // Blackout zeroes everything
        if isBlackout {
            for key in attrs.keys {
                attrs[key] = 0
            }
        }

        return FixtureState(fixtureID: fixtureID, attributes: attrs)
    }

    /// Push override for a single fixture.
    func pushOverride(for fixtureID: UUID, engine: DecisionEngineService) {
        guard isActive else { return }
        let state = buildFixtureState(for: fixtureID)
        engine.setOverride(for: fixtureID, state: state)
    }

    /// Push overrides for all fixtures.
    func pushAllOverrides(engine: DecisionEngineService) {
        guard isActive else { return }
        for fixtureID in fixtureValues.keys {
            pushOverride(for: fixtureID, engine: engine)
        }
    }

    // MARK: - Helpers

    private func sceneToFixtureValues(_ scene: DMXScene) -> [UUID: [FixtureAttribute: Double]] {
        var result: [UUID: [FixtureAttribute: Double]] = [:]
        for snapshot in scene.fixtureSnapshots {
            result[snapshot.fixtureID] = snapshot.typedAttributes
        }
        return result
    }
}
