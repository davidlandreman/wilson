import Foundation
import Testing
@testable import Wilson

@Suite("Tracer Bullet Tests")
struct TracerBulletTests {

    // MARK: - FixtureDefinition

    @Test("Fixture definition reports correct attributes")
    func fixtureDefinitionAttributes() {
        let strobe = FixtureCatalog.genericStrobe
        #expect(strobe.attributes == [.dimmer])
        #expect(strobe.channelCount == 1)

        let par = FixtureCatalog.genericRGBPar
        #expect(par.attributes == [.dimmer, .red, .green, .blue])
        #expect(par.channelCount == 4)
    }

    // MARK: - FixtureCatalog

    @Test("Catalog contains expected fixtures")
    func catalogContents() {
        #expect(FixtureCatalog.all.count == 2)
        #expect(FixtureCatalog.all.contains(where: { $0.name == "Generic Strobe" }))
        #expect(FixtureCatalog.all.contains(where: { $0.name == "Generic RGB Par" }))
    }

    // MARK: - FixtureState

    @Test("Fixture state dimmer accessor")
    func fixtureStateDimmer() {
        var state = FixtureState(fixtureID: UUID())
        #expect(state.dimmer == 0)

        state.attributes[.dimmer] = 0.75
        #expect(state.dimmer == 0.75)
    }

    @Test("Fixture state color accessor")
    func fixtureStateColor() {
        var state = FixtureState(fixtureID: UUID())
        state.attributes[.red] = 1.0
        state.attributes[.green] = 0.5
        state.attributes[.blue] = 0.25

        let color = state.color
        #expect(color.red == 1.0)
        #expect(color.green == 0.5)
        #expect(color.blue == 0.25)
        #expect(color.white == 0)
    }

    // MARK: - FixtureManager

    @Test("Fixture manager add and remove") @MainActor
    func fixtureManagerAddRemove() {
        let manager = FixtureManager()
        #expect(manager.fixtures.isEmpty)

        let fixture = manager.addFixture(
            definition: FixtureCatalog.genericStrobe,
            label: "Test Strobe"
        )
        #expect(manager.fixtures.count == 1)
        #expect(manager.fixtures[0].label == "Test Strobe")
        #expect(manager.fixtures[0].isVirtual == true)

        manager.removeFixture(id: fixture.id)
        #expect(manager.fixtures.isEmpty)
    }

    // MARK: - DecisionEngine

    @Test("Decision engine produces strobe on beat") @MainActor
    func decisionEngineStrobeOnBeat() {
        let engine = DecisionEngineService()
        let fixture = StageFixture(
            label: "Strobe",
            definition: FixtureCatalog.genericStrobe
        )

        var state = MusicalState()
        state.isSilent = false
        state.isBeat = true

        engine.update(musicalState: state, fixtures: [fixture])

        let fixtureState = engine.fixtureStates[fixture.id]
        #expect(fixtureState != nil)
        #expect(fixtureState!.dimmer == 1.0)
    }

    @Test("Decision engine decays between beats") @MainActor
    func decisionEngineDecay() {
        let engine = DecisionEngineService()
        let fixture = StageFixture(
            label: "Strobe",
            definition: FixtureCatalog.genericStrobe
        )

        var state = MusicalState()
        state.isSilent = false
        state.isBeat = false
        state.beatPhase = 0.5  // halfway between beats

        engine.update(musicalState: state, fixtures: [fixture])

        let fixtureState = engine.fixtureStates[fixture.id]
        #expect(fixtureState != nil)
        // (1 - 0.5)^3 = 0.125
        #expect(fixtureState!.dimmer == 0.125)
    }

    @Test("Decision engine produces zero in silence") @MainActor
    func decisionEngineSilence() {
        let engine = DecisionEngineService()
        let fixture = StageFixture(
            label: "Strobe",
            definition: FixtureCatalog.genericStrobe
        )

        var state = MusicalState()
        state.isSilent = true

        engine.update(musicalState: state, fixtures: [fixture])

        let fixtureState = engine.fixtureStates[fixture.id]
        #expect(fixtureState != nil)
        #expect(fixtureState!.dimmer == 0)
    }

    @Test("Decision engine sets RGB to white for RGB fixtures") @MainActor
    func decisionEngineRGB() {
        let engine = DecisionEngineService()
        let fixture = StageFixture(
            label: "Par",
            definition: FixtureCatalog.genericRGBPar
        )

        var state = MusicalState()
        state.isSilent = false
        state.isBeat = true

        engine.update(musicalState: state, fixtures: [fixture])

        let fixtureState = engine.fixtureStates[fixture.id]
        #expect(fixtureState != nil)
        #expect(fixtureState!.attributes[.red] == 1.0)
        #expect(fixtureState!.attributes[.green] == 1.0)
        #expect(fixtureState!.attributes[.blue] == 1.0)
    }
}
