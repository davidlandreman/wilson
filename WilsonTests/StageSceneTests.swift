import Testing
@testable import Wilson

@Suite("3D Stage Scene Tests")
struct StageSceneTests {

    // MARK: - Center-Out Positioning Algorithm

    @Test("Single fixture positions at center")
    func singleFixtureCenter() {
        let x = StageGeometry.trussXPosition(slotIndex: 0, totalFixtures: 1, trussLength: 5.0)
        #expect(x == 0)
    }

    @Test("Two fixtures position symmetrically")
    func twoFixturesSymmetric() {
        let x0 = StageGeometry.trussXPosition(slotIndex: 0, totalFixtures: 2, trussLength: 6.0)
        let x1 = StageGeometry.trussXPosition(slotIndex: 1, totalFixtures: 2, trussLength: 6.0)
        #expect(x0 == 0)
        #expect(x1 > 0) // first added goes right
    }

    @Test("Five fixtures alternate right-left from center")
    func fiveFixturesAlternate() {
        let positions = (0..<5).map {
            StageGeometry.trussXPosition(slotIndex: $0, totalFixtures: 5, trussLength: 6.0)
        }
        // Slot 0: center
        #expect(positions[0] == 0)
        // Slot 1: right, Slot 2: left (mirror)
        #expect(positions[1] > 0)
        #expect(positions[2] < 0)
        #expect(positions[1] == -positions[2])
        // Slot 3: further right, Slot 4: further left (mirror)
        #expect(positions[3] > positions[1])
        #expect(positions[4] < positions[2])
        #expect(positions[3] == -positions[4])
    }

    @Test("Zero fixtures returns zero")
    func zeroFixtures() {
        let x = StageGeometry.trussXPosition(slotIndex: 0, totalFixtures: 0, trussLength: 5.0)
        #expect(x == 0)
    }

    // MARK: - Truss Slot Assignment

    @Test("FixtureManager assigns sequential truss slots")
    func trussSlotAssignment() {
        let manager = FixtureManager()
        let def = FixtureCatalog.genericRGBPar

        let f0 = manager.addFixture(definition: def, label: "A")
        let f1 = manager.addFixture(definition: def, label: "B")
        let f2 = manager.addFixture(definition: def, label: "C")

        #expect(f0.trussSlot == 0)
        #expect(f1.trussSlot == 1)
        #expect(f2.trussSlot == 2)
    }

    @Test("FixtureManager reindexes truss slots after removal")
    func trussSlotReindex() {
        let manager = FixtureManager()
        let def = FixtureCatalog.genericRGBPar

        let f0 = manager.addFixture(definition: def, label: "A")
        let f1 = manager.addFixture(definition: def, label: "B")
        _ = manager.addFixture(definition: def, label: "C")

        manager.removeFixture(id: f1.id)

        #expect(manager.fixtures.count == 2)
        #expect(manager.fixtures[0].id == f0.id)
        #expect(manager.fixtures[0].trussSlot == 0)
        #expect(manager.fixtures[1].trussSlot == 1)
    }

    // MARK: - Geometry Factories

    @Test("Truss node has child nodes for rails and braces")
    @MainActor
    func trussHasChildren() {
        let truss = StageGeometry.makeTruss(length: 2.0)
        #expect(truss.childNodes.count > 4) // at least 4 rails + braces
    }

    @Test("Beam cone material uses additive blend mode")
    @MainActor
    func beamConeBlendMode() {
        let (_, material) = StageGeometry.makeBeamCone()
        #expect(material.blendMode == .add)
        #expect(material.isDoubleSided == true)
        #expect(material.writesToDepthBuffer == false)
    }

    @Test("Par can returns body and yoke nodes")
    @MainActor
    func parCanNodes() {
        let (body, yoke) = StageGeometry.makeParCan()
        #expect(body.name == "parCanBody")
        #expect(yoke.name == "yoke")
    }
}
