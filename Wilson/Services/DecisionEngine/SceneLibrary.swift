import Foundation

/// Manages scene selection and crossfade for the autonomous choreographer.
/// A Sendable struct owned by Choreographer — participates in the pipeline
/// without introducing @Observable or actor isolation.
struct SceneLibrary: Sendable {
    /// Available user-created scenes, set each frame from the main actor via DecisionEngineService.
    var availableScenes: [SceneSnapshot] = []

    /// Algorithmically generated look from LookGenerator (set by Choreographer each evaluation).
    var generatedLook: SceneSnapshot?

    /// Currently active scene (nil = pure behavior mode).
    private(set) var activeScene: SceneSnapshot?
    /// Previous scene being crossfaded from.
    private(set) var previousScene: SceneSnapshot?
    /// Crossfade progress: 0.0 = fully previous, 1.0 = fully active.
    private(set) var transitionProgress: Double = 1.0

    /// Names of recently selected scenes/looks for variety tracking.
    private var recentNames: [String] = []
    private static let maxRecent = 3

    // MARK: - Scene Selection

    /// Evaluate and select the best matching scene for the current scenario and mood.
    /// Considers both user-created scenes and the generated look as candidates.
    mutating func selectScene(scenario: Choreographer.Scenario, mood: MoodState) {
        // Build candidate pool: user scenes + generated look
        var candidates = availableScenes
        if let generated = generatedLook {
            candidates.append(generated)
        }

        guard !candidates.isEmpty else {
            if activeScene != nil {
                previousScene = activeScene
                activeScene = nil
                transitionProgress = 0
            }
            return
        }

        var bestScore: Double = -1
        var bestScene: SceneSnapshot?

        for scene in candidates {
            let score = scoreScene(scene, scenario: scenario, mood: mood)
            if score > bestScore {
                bestScore = score
                bestScene = scene
            }
        }

        // Minimum threshold — if nothing matches well, go to pure behavior mode
        guard let selected = bestScene, bestScore > 0.2 else {
            if activeScene != nil {
                previousScene = activeScene
                activeScene = nil
                transitionProgress = 0
            }
            return
        }

        // Only transition if the selection actually changed
        if selected != activeScene {
            previousScene = activeScene
            activeScene = selected
            transitionProgress = selected.transitionStyle == .snap ? 1.0 : 0.0

            // Track recency for variety
            recentNames.append(selected.name)
            if recentNames.count > Self.maxRecent {
                recentNames.removeFirst()
            }
        }
    }

    /// Score a scene against the current scenario and mood. Returns 0.0–1.0+.
    func scoreScene(_ scene: SceneSnapshot, scenario: Choreographer.Scenario, mood: MoodState) -> Double {
        let energyScore = scoreEnergy(scene.energyLevel, scenario: scenario)
        let moodScore = scoreMood(scene.mood, mood: mood)

        // User-created scenes get a preference bonus — they're hand-crafted
        let userBonus: Double = scene.isGenerated ? 0 : 0.12

        // Variety penalty: discourage re-selecting the same scene
        var varietyPenalty: Double = (scene == activeScene) ? -0.15 : 0
        // Additional penalty for recently used scenes/looks
        if recentNames.contains(scene.name) && scene != activeScene {
            varietyPenalty -= 0.2
        }

        return energyScore * 0.6 + moodScore * 0.4 + userBonus + varietyPenalty
    }

    private func scoreEnergy(_ level: SceneEnergyLevel, scenario: Choreographer.Scenario) -> Double {
        switch level {
        case .any: return 0.8
        case .low:
            switch scenario {
            case .lowEnergy, .declining: return 1.0
            case .mediumEnergy: return 0.5
            default: return 0.1
            }
        case .medium:
            switch scenario {
            case .mediumEnergy, .building: return 1.0
            case .lowEnergy, .highEnergy: return 0.5
            default: return 0.3
            }
        case .high:
            switch scenario {
            case .highEnergy, .peakDrop: return 1.0
            case .building: return 0.7
            case .mediumEnergy: return 0.5
            default: return 0.1
            }
        }
    }

    private func scoreMood(_ sceneMood: SceneMood, mood: MoodState) -> Double {
        switch sceneMood {
        case .any:
            return 0.7
        case .calm:
            // Low excitement + low chaos = calm
            let calmness = (1.0 - mood.excitement) * 0.6 + (1.0 - mood.chaos) * 0.4
            return calmness
        case .intense:
            // High excitement + high chaos = intense
            let intensity = mood.excitement * 0.6 + mood.chaos * 0.4
            return intensity
        case .uplifting:
            // High valence = uplifting
            return mood.valence
        case .dark:
            // Low valence = dark
            return 1.0 - mood.valence
        }
    }

    // MARK: - Crossfade

    /// Advance the scene transition. Called every frame.
    mutating func tick(deltaTime: Double) {
        guard transitionProgress < 1.0, let scene = activeScene else { return }

        let duration: Double
        switch scene.transitionStyle {
        case .snap:
            duration = 0
        case .crossfade:
            duration = scene.transitionDuration
        case .slowDissolve:
            duration = scene.transitionDuration * 2.0
        }

        if duration <= 0 {
            transitionProgress = 1.0
        } else {
            transitionProgress = min(1.0, transitionProgress + deltaTime / duration)
        }

        // Clean up previous scene when transition completes
        if transitionProgress >= 1.0 {
            previousScene = nil
        }
    }

    // MARK: - Output

    /// The current reactivity level, interpolated during transitions.
    var activeReactivity: Double {
        guard let active = activeScene else { return 1.0 } // No scene = full behavior mode
        guard let previous = previousScene, transitionProgress < 1.0 else {
            return active.reactivity
        }
        return previous.reactivity + (active.reactivity - previous.reactivity) * transitionProgress
    }

    /// Get the blended scene base values for a fixture, accounting for crossfade.
    /// Returns nil if no scene is active (signal to skip scene blending entirely).
    func blendedOutput(for fixtureID: UUID) -> [FixtureAttribute: Double]? {
        guard let active = activeScene else { return nil }

        let activeAttrs = active.fixtureAttributes[fixtureID]

        // If no transition in progress or no previous scene, return active directly
        guard let previous = previousScene, transitionProgress < 1.0 else {
            return activeAttrs
        }

        let previousAttrs = previous.fixtureAttributes[fixtureID]

        // Both nil = this fixture isn't in either scene
        guard activeAttrs != nil || previousAttrs != nil else { return nil }

        let from = previousAttrs ?? [:]
        let to = activeAttrs ?? [:]
        let t = transitionProgress

        // Lerp all attributes between previous and active scene
        var result: [FixtureAttribute: Double] = [:]
        let allAttrs = Set(from.keys).union(to.keys)
        for attr in allAttrs {
            let fromVal = from[attr] ?? 0
            let toVal = to[attr] ?? 0
            result[attr] = fromVal + (toVal - fromVal) * t
        }
        return result
    }

    /// Whether a scene is currently influencing output.
    var hasActiveScene: Bool { activeScene != nil }

    /// Name of the active scene (for debug display).
    var activeSceneName: String? { activeScene?.name }
}
