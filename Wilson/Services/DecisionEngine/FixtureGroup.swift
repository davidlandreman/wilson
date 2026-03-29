import Foundation

/// A dynamic grouping of fixtures that share the same behavior assignment.
struct FixtureGroup: Identifiable, Sendable {
    let id: UUID
    var name: String
    var fixtureIDs: [UUID]
    var role: GroupRole

    init(id: UUID = UUID(), name: String, fixtureIDs: [UUID], role: GroupRole = .primary) {
        self.id = id
        self.name = name
        self.fixtureIDs = fixtureIDs
        self.role = role
    }

    /// The role a group plays in the light show, guiding behavior selection.
    enum GroupRole: Sendable {
        /// Main wash/color fixtures.
        case primary
        /// Highlight/contrast fixtures.
        case accent
        /// Moving heads doing sweeps.
        case movement
        /// Strobes, special effects.
        case effect
        /// Everything together (unison moments).
        case all
    }
}

/// Creates and modifies fixture group assignments using various strategies.
struct GroupingEngine: Sendable {
    enum Strategy: CaseIterable, Sendable {
        /// Every fixture in one group.
        case allUnison
        /// Group by fixture capabilities (RGB vs. movers vs. strobe-only).
        case capabilitySplit
        /// Capability split, but movers are divided into two independent sub-groups.
        /// Falls back to capabilitySplit when fewer than 2 movers.
        case moverPairSplit
        /// Group by stage position (left/right halves).
        case spatialSplit
        /// Even/odd trussSlot for interleaved effects.
        case alternating
        /// One fixture (or pair) solos against the rest.
        case soloBackground
    }

    func group(fixtures: [StageFixture], strategy: Strategy) -> [FixtureGroup] {
        guard !fixtures.isEmpty else { return [] }

        switch strategy {
        case .allUnison:
            return [FixtureGroup(
                name: "All",
                fixtureIDs: fixtures.map(\.id),
                role: .all
            )]

        case .capabilitySplit:
            return groupByCapability(fixtures)

        case .spatialSplit:
            return groupBySpatial(fixtures)

        case .alternating:
            return groupByAlternating(fixtures)

        case .moverPairSplit:
            return groupByMoverPairs(fixtures)

        case .soloBackground:
            return groupBySolo(fixtures)
        }
    }

    private func groupByCapability(_ fixtures: [StageFixture]) -> [FixtureGroup] {
        var movers: [UUID] = []
        var colorOnly: [UUID] = []
        var dimmerOnly: [UUID] = []

        for fixture in fixtures {
            let attrs = fixture.attributes
            if attrs.contains(.pan) || attrs.contains(.tilt) {
                movers.append(fixture.id)
            } else if attrs.contains(.red) || attrs.contains(.green) || attrs.contains(.blue) {
                colorOnly.append(fixture.id)
            } else {
                dimmerOnly.append(fixture.id)
            }
        }

        var groups: [FixtureGroup] = []
        if !movers.isEmpty {
            groups.append(FixtureGroup(name: "Movers", fixtureIDs: movers, role: .movement))
        }
        if !colorOnly.isEmpty {
            groups.append(FixtureGroup(name: "Color", fixtureIDs: colorOnly, role: .primary))
        }
        if !dimmerOnly.isEmpty {
            groups.append(FixtureGroup(name: "Effect", fixtureIDs: dimmerOnly, role: .effect))
        }
        // Fallback: if everything ended up in one bucket, just return all-unison
        if groups.count <= 1 {
            return [FixtureGroup(name: "All", fixtureIDs: fixtures.map(\.id), role: .all)]
        }
        return groups
    }

    private func groupByMoverPairs(_ fixtures: [StageFixture]) -> [FixtureGroup] {
        var movers: [StageFixture] = []
        var colorOnly: [UUID] = []
        var dimmerOnly: [UUID] = []

        for fixture in fixtures {
            let attrs = fixture.attributes
            if attrs.contains(.pan) || attrs.contains(.tilt) {
                movers.append(fixture)
            } else if attrs.contains(.red) || attrs.contains(.green) || attrs.contains(.blue) {
                colorOnly.append(fixture.id)
            } else {
                dimmerOnly.append(fixture.id)
            }
        }

        var groups: [FixtureGroup] = []

        // Split movers into two sub-groups by truss position (left/right pairs)
        if movers.count >= 2 {
            let sorted = movers.sorted { $0.trussSlot < $1.trussSlot }
            let mid = sorted.count / 2
            let groupA = Array(sorted.prefix(mid))
            let groupB = Array(sorted.suffix(from: mid))
            groups.append(FixtureGroup(name: "Movers A", fixtureIDs: groupA.map(\.id), role: .movement))
            groups.append(FixtureGroup(name: "Movers B", fixtureIDs: groupB.map(\.id), role: .movement))
        } else if !movers.isEmpty {
            groups.append(FixtureGroup(name: "Movers", fixtureIDs: movers.map(\.id), role: .movement))
        }

        if !colorOnly.isEmpty {
            groups.append(FixtureGroup(name: "Color", fixtureIDs: colorOnly, role: .primary))
        }
        if !dimmerOnly.isEmpty {
            groups.append(FixtureGroup(name: "Effect", fixtureIDs: dimmerOnly, role: .effect))
        }

        if groups.count <= 1 {
            return [FixtureGroup(name: "All", fixtureIDs: fixtures.map(\.id), role: .all)]
        }
        return groups
    }

    private func groupBySpatial(_ fixtures: [StageFixture]) -> [FixtureGroup] {
        let sorted = fixtures.sorted { $0.position.x < $1.position.x }
        let mid = sorted.count / 2
        let left = Array(sorted.prefix(mid))
        let right = Array(sorted.suffix(from: mid))

        return [
            FixtureGroup(name: "Left", fixtureIDs: left.map(\.id), role: .primary),
            FixtureGroup(name: "Right", fixtureIDs: right.map(\.id), role: .accent),
        ]
    }

    private func groupByAlternating(_ fixtures: [StageFixture]) -> [FixtureGroup] {
        let sorted = fixtures.sorted { $0.trussSlot < $1.trussSlot }
        var groupA: [UUID] = []
        var groupB: [UUID] = []

        for (index, fixture) in sorted.enumerated() {
            if index.isMultiple(of: 2) {
                groupA.append(fixture.id)
            } else {
                groupB.append(fixture.id)
            }
        }

        return [
            FixtureGroup(name: "Even", fixtureIDs: groupA, role: .primary),
            FixtureGroup(name: "Odd", fixtureIDs: groupB, role: .accent),
        ]
    }

    private func groupBySolo(_ fixtures: [StageFixture]) -> [FixtureGroup] {
        guard fixtures.count >= 2 else {
            return [FixtureGroup(name: "All", fixtureIDs: fixtures.map(\.id), role: .all)]
        }
        // Pick the center fixture as solo
        let sorted = fixtures.sorted { $0.trussSlot < $1.trussSlot }
        let centerIndex = sorted.count / 2
        let solo = sorted[centerIndex]
        let background = sorted.filter { $0.id != solo.id }

        return [
            FixtureGroup(name: "Solo", fixtureIDs: [solo.id], role: .accent),
            FixtureGroup(name: "Background", fixtureIDs: background.map(\.id), role: .primary),
        ]
    }
}
