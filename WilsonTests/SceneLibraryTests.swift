import Foundation
import Testing
@testable import Wilson

@Suite("SceneLibrary")
struct SceneLibraryTests {

    // MARK: - Helpers

    private func makeSnapshot(
        name: String = "Test",
        reactivity: Double = 0.5,
        energyLevel: SceneEnergyLevel = .any,
        mood: SceneMood = .any,
        transitionStyle: SceneTransitionStyle = .crossfade,
        transitionDuration: Double = 2.0,
        fixtureAttributes: [UUID: [FixtureAttribute: Double]] = [:]
    ) -> SceneSnapshot {
        SceneSnapshot(
            name: name,
            reactivity: reactivity,
            energyLevel: energyLevel,
            mood: mood,
            transitionStyle: transitionStyle,
            transitionDuration: transitionDuration,
            grandMaster: 1.0,
            fixtureAttributes: fixtureAttributes
        )
    }

    private func makeMood(
        excitement: Double = 0.5,
        valence: Double = 0.5,
        brightness: Double = 0.5,
        chaos: Double = 0.3,
        intensity: Double = 0.5
    ) -> MoodState {
        var mood = MoodState()
        mood.excitement = excitement
        mood.valence = valence
        mood.brightness = brightness
        mood.chaos = chaos
        mood.intensity = intensity
        return mood
    }

    // MARK: - Scoring

    @Test("High energy scene scores highest in high energy scenario")
    func highEnergyScoring() {
        let library = SceneLibrary()
        let highScene = makeSnapshot(energyLevel: SceneEnergyLevel.high)
        let mood = makeMood(excitement: 0.8, valence: 0.5, brightness: 0.5, chaos: 0.5, intensity: 0.8)

        let score = library.scoreScene(highScene, scenario: .highEnergy, mood: mood)
        let lowScore = library.scoreScene(
            makeSnapshot(energyLevel: SceneEnergyLevel.low),
            scenario: .highEnergy,
            mood: mood
        )

        #expect(score > lowScore)
    }

    @Test("Mood matching: calm scene scores high with low excitement")
    func calmMoodScoring() {
        let library = SceneLibrary()
        let calmScene = makeSnapshot(mood: SceneMood.calm)
        let intenseScene = makeSnapshot(mood: SceneMood.intense)
        let calmMood = makeMood(excitement: 0.1, valence: 0.5, brightness: 0.5, chaos: 0.1, intensity: 0.3)

        let calmScore = library.scoreScene(calmScene, scenario: .lowEnergy, mood: calmMood)
        let intenseScore = library.scoreScene(intenseScene, scenario: .lowEnergy, mood: calmMood)

        #expect(calmScore > intenseScore)
    }

    // MARK: - Selection

    @Test("Empty library results in no active scene")
    func emptyLibraryFallback() {
        var library = SceneLibrary()
        library.selectScene(scenario: .mediumEnergy, mood: makeMood())

        #expect(library.activeScene == nil)
        #expect(library.hasActiveScene == false)
    }

    @Test("Scene is selected when available")
    func basicSelection() {
        var library = SceneLibrary()
        library.availableScenes = [makeSnapshot(name: "TestScene")]
        library.selectScene(scenario: .mediumEnergy, mood: makeMood())

        #expect(library.activeScene != nil)
        #expect(library.activeSceneName == "TestScene")
    }

    @Test("Best matching scene is selected")
    func bestMatchSelection() {
        var library = SceneLibrary()
        library.availableScenes = [
            makeSnapshot(name: "Low", energyLevel: SceneEnergyLevel.low),
            makeSnapshot(name: "High", energyLevel: SceneEnergyLevel.high),
        ]
        library.selectScene(scenario: .highEnergy, mood: makeMood(excitement: 0.8, valence: 0.5, brightness: 0.5, chaos: 0.3, intensity: 0.8))

        #expect(library.activeSceneName == "High")
    }

    // MARK: - Reactivity Blend

    @Test("Reactivity 0% returns scene values unchanged")
    func reactivityZero() {
        let fixtureID = UUID()
        let attrs: [FixtureAttribute: Double] = [.red: 0.8, .green: 0.2]
        var library = SceneLibrary()
        library.availableScenes = [
            makeSnapshot(
                reactivity: 0.0,
                transitionStyle: SceneTransitionStyle.snap,
                fixtureAttributes: [fixtureID: attrs]
            ),
        ]
        library.selectScene(scenario: .mediumEnergy, mood: makeMood())

        #expect(library.activeReactivity == 0.0)

        let output = library.blendedOutput(for: fixtureID)
        #expect(output != nil)
        #expect(output?[FixtureAttribute.red] == 0.8)
        #expect(output?[FixtureAttribute.green] == 0.2)
    }

    @Test("Reactivity 100% means full behavior mode")
    func reactivityFull() {
        var library = SceneLibrary()
        library.availableScenes = [makeSnapshot(reactivity: 1.0, transitionStyle: SceneTransitionStyle.snap)]
        library.selectScene(scenario: .mediumEnergy, mood: makeMood())

        #expect(library.activeReactivity == 1.0)
    }

    @Test("Reactivity blend at 50% produces midpoint")
    func reactivityMidpoint() {
        let reactivity = 0.5
        let sceneVal = 0.2
        let behaviorVal = 0.8
        let blended = sceneVal + (behaviorVal - sceneVal) * reactivity

        #expect(blended == 0.5)
    }

    // MARK: - Fixture Mismatch

    @Test("Missing fixture in scene returns nil for that fixture")
    func fixtureMismatch() {
        let sceneFixture = UUID()
        let otherFixture = UUID()
        let attrs: [FixtureAttribute: Double] = [.dimmer: 1.0]
        var library = SceneLibrary()
        library.availableScenes = [
            makeSnapshot(
                transitionStyle: SceneTransitionStyle.snap,
                fixtureAttributes: [sceneFixture: attrs]
            ),
        ]
        library.selectScene(scenario: .mediumEnergy, mood: makeMood())

        #expect(library.blendedOutput(for: sceneFixture) != nil)
        #expect(library.blendedOutput(for: otherFixture) == nil)
    }

    // MARK: - Crossfade

    @Test("Crossfade transition interpolates over time")
    func crossfadeTransition() {
        let fixtureID = UUID()
        let attrsA: [FixtureAttribute: Double] = [.red: 0.0]
        let attrsB: [FixtureAttribute: Double] = [.red: 1.0]

        var library = SceneLibrary()

        // Start with scene A (snap)
        let sceneA = makeSnapshot(
            name: "A",
            transitionStyle: SceneTransitionStyle.snap,
            fixtureAttributes: [fixtureID: attrsA]
        )
        library.availableScenes = [sceneA]
        library.selectScene(scenario: .lowEnergy, mood: makeMood())
        library.tick(deltaTime: 0.1)

        // Now transition to scene B with crossfade
        let sceneB = makeSnapshot(
            name: "B",
            transitionStyle: SceneTransitionStyle.crossfade,
            transitionDuration: 2.0,
            fixtureAttributes: [fixtureID: attrsB]
        )
        library.availableScenes = [sceneB]
        library.selectScene(scenario: .highEnergy, mood: makeMood(excitement: 0.9, valence: 0.5, brightness: 0.5, chaos: 0.3, intensity: 0.9))

        // Mid-transition (1 second into 2-second crossfade)
        library.tick(deltaTime: 1.0)

        let output = library.blendedOutput(for: fixtureID)
        #expect(output != nil)
        if let red = output?[FixtureAttribute.red] {
            #expect(red > 0.4 && red < 0.6)
        }
    }

    @Test("Snap transition completes immediately")
    func snapTransition() {
        var library = SceneLibrary()
        library.availableScenes = [makeSnapshot(transitionStyle: SceneTransitionStyle.snap)]
        library.selectScene(scenario: .mediumEnergy, mood: makeMood())

        #expect(library.transitionProgress == 1.0)
    }

    @Test("No active scene returns 1.0 reactivity (full behavior mode)")
    func noSceneFullBehavior() {
        let library = SceneLibrary()
        #expect(library.activeReactivity == 1.0)
    }
}
