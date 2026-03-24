import Foundation
import SwiftData

/// Manages the fixture library, patching, and stage layout.
@Observable
final class FixtureManager {
    private(set) var patchedFixtures: [PatchedFixture] = []
    private(set) var fixtureGroups: [String: [PatchedFixture]] = [:]

    /// Discover what capabilities a fixture has based on its profile.
    func capabilities(for fixture: PatchedFixture) -> Set<FixtureAttribute> {
        guard let profile = fixture.profile else { return [] }
        return Set(profile.channels.map(\.attribute))
    }

    /// Get all fixtures that belong to a named group.
    func fixtures(inGroup group: String) -> [PatchedFixture] {
        fixtureGroups[group] ?? []
    }
}
