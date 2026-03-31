import Foundation

/// Translates MusicalState into per-fixture lighting states.
/// Orchestrates a layered system: mood → choreographer → behaviors → compositing.
/// Produces FixtureState values — the abstraction boundary between
/// lighting decisions and output backends (DMX, virtual rendering).
@Observable
final class DecisionEngineService {
    // MARK: - Output

    private(set) var fixtureStates: [UUID: FixtureState] = [:]

    /// Per-fixture manual overrides. When set, the override state is used
    /// instead of computing from musical state.
    private(set) var overrides: [UUID: FixtureState] = [:]

    // MARK: - User-facing controls

    /// Active cue parameters influencing behavior.
    var reactivity: Double = 0.5       // 0 = subtle, 1 = aggressive
    var movementIntensity: Double = 0.5
    var colorTemperature: Double = 0.5 // 0 = cool, 1 = warm

    /// Active color palette from CueService.
    var activePalette: ColorPalette?

    /// Scene snapshots for autonomous choreographer scene selection.
    /// Set by AppState each frame from the cached main-actor snapshot array.
    var autonomousScenes: [SceneSnapshot] = []

    // MARK: - Observable debug state

    private(set) var currentMood = MoodState()
    private(set) var activeGroups: [FixtureGroup] = []
    private(set) var activeSlotDescriptions: [String] = []
    private(set) var currentScenario: Choreographer.Scenario = .lowEnergy
    private(set) var activeSceneName: String?

    // MARK: - Internal subsystems

    private var clock = EngineClock()
    private var moodEngine = MoodEngine()
    private var choreographer = Choreographer()
    private var colorEngine = ColorEngine()
    private var movementLimiter = MovementLimiter()

    // MARK: - Override API

    func setOverride(for fixtureID: UUID, state: FixtureState) {
        overrides[fixtureID] = state
        fixtureStates[fixtureID] = state
    }

    func removeOverride(for fixtureID: UUID) {
        overrides.removeValue(forKey: fixtureID)
        fixtureStates.removeValue(forKey: fixtureID)
    }

    // MARK: - Main update loop

    /// Generate fixture states based on current musical state and stage fixtures.
    func update(musicalState: MusicalState, fixtures: [StageFixture]) {
        clock.tick()

        // Layer 1: Update mood (slow EMA)
        moodEngine.update(musicalState: musicalState, deltaTime: clock.deltaTime)
        currentMood = moodEngine.state

        // Resolve palette early — choreographer needs it for generative looks
        let resolvedPalette = colorEngine.resolve(
            palette: activePalette,
            mood: moodEngine.state,
            musicalState: musicalState
        )

        // Provide scene snapshots to choreographer for autonomous selection
        choreographer.sceneLibrary.availableScenes = autonomousScenes

        // Sync bar counter from mood engine to choreographer
        choreographer.barCounter = moodEngine.barCounter

        // Layer 2: Choreographer decisions (conditional, not every frame)
        choreographer.evaluate(
            musicalState: musicalState,
            mood: moodEngine.state,
            fixtures: fixtures,
            palette: resolvedPalette,
            time: clock.time
        )
        activeGroups = choreographer.groups
        activeSlotDescriptions = choreographer.slots.map {
            "\(type(of: $0.behavior).id) → \($0.groupID.uuidString.prefix(4))"
        }
        currentScenario = choreographer.currentScenario

        // Advance scene crossfade each frame
        choreographer.tickSceneTransition(deltaTime: clock.deltaTime)

        // Layer 4: Run all active behaviors and composite output
        var composited: [UUID: [FixtureAttribute: Double]] = [:]

        for slot in choreographer.slots {
            guard let group = choreographer.groups.first(where: { $0.id == slot.groupID }) else {
                continue
            }
            let groupFixtures = fixtures.filter { group.fixtureIDs.contains($0.id) }
            guard !groupFixtures.isEmpty else { continue }

            let context = BehaviorContext(
                musicalState: musicalState,
                moodState: moodEngine.state,
                palette: resolvedPalette,
                beat: BeatContext(from: musicalState, phraseCounter: choreographer.barCounter),
                time: clock.time,
                deltaTime: clock.deltaTime,
                reactivity: reactivity,
                movementIntensity: movementIntensity,
                parameters: slot.parameters
            )

            let slotOutput = slot.behavior.evaluate(fixtures: groupFixtures, context: context)

            // Composite with HTP (highest takes precedence) weighted by slot
            for (fixtureID, attrs) in slotOutput {
                for (attr, value) in attrs {
                    let weighted = value * slot.weight
                    if let existing = composited[fixtureID]?[attr] {
                        composited[fixtureID]?[attr] = max(existing, weighted)
                    } else {
                        composited[fixtureID, default: [:]][attr] = weighted
                    }
                }
            }
        }

        // Layer 4.5: Scene base layer blend
        // When the choreographer has selected a scene, lerp between scene base
        // values and behavior output based on the scene's reactivity level.
        // Movement attributes (pan/tilt) are excluded — scenes control color/intensity,
        // behaviors have full authority over movement.
        if choreographer.sceneLibrary.hasActiveScene {
            let sceneReactivity = choreographer.sceneLibrary.activeReactivity
            let movementAttrs: Set<FixtureAttribute> = [.pan, .tilt, .panFine, .tiltFine]
            for fixture in fixtures {
                guard let sceneBase = choreographer.sceneLibrary.blendedOutput(for: fixture.id) else {
                    continue
                }
                let behaviorAttrs = composited[fixture.id] ?? [:]
                var blended: [FixtureAttribute: Double] = [:]

                let allAttrs = Set(sceneBase.keys).union(behaviorAttrs.keys)
                for attr in allAttrs {
                    // Movement: behaviors have full control
                    if movementAttrs.contains(attr) {
                        if let bv = behaviorAttrs[attr] {
                            blended[attr] = bv
                        }
                        continue
                    }
                    let sv = sceneBase[attr] ?? 0
                    let bv = behaviorAttrs[attr] ?? 0
                    blended[attr] = sv + (bv - sv) * sceneReactivity
                }
                composited[fixture.id] = blended
            }
        }

        activeSceneName = choreographer.sceneLibrary.activeSceneName

        // Layer 5: Build final fixture states
        var states: [UUID: FixtureState] = [:]

        for fixture in fixtures {
            // Manual overrides take precedence
            if let override = overrides[fixture.id] {
                states[fixture.id] = override
                continue
            }

            var state = FixtureState(fixtureID: fixture.id)
            if let attrs = composited[fixture.id] {
                state.attributes = attrs
            }

            // Apply movement slew-rate limiting
            if fixture.attributes.contains(.pan) || fixture.attributes.contains(.tilt) {
                let previous = fixtureStates[fixture.id]
                movementLimiter.apply(to: &state, previous: previous, deltaTime: clock.deltaTime)
            }

            // Silence safety: behaviors already handle isSilent individually.
            // Only force blackout when mood intensity has fully decayed,
            // confirming sustained silence rather than a percussive gap.
            if musicalState.isSilent && moodEngine.state.intensity < 0.05 {
                state.attributes[.dimmer] = 0
            }

            states[fixture.id] = state
        }

        fixtureStates = states
    }
}
