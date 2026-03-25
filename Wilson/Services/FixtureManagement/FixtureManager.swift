import Foundation

/// Manages the runtime fixture collection on stage.
@Observable
final class FixtureManager {
    private(set) var fixtures: [StageFixture] = []

    /// Add a fixture to the stage from a catalog definition.
    @discardableResult
    func addFixture(definition: FixtureDefinition, label: String, isVirtual: Bool = true) -> StageFixture {
        let fixture = StageFixture(
            label: label,
            definition: definition,
            isVirtual: isVirtual,
            position: nextPosition()
        )
        fixtures.append(fixture)
        return fixture
    }

    /// Remove a fixture by ID.
    func removeFixture(id: UUID) {
        fixtures.removeAll { $0.id == id }
    }

    /// Get all fixtures matching a set of attributes.
    func fixtures(withAttribute attribute: FixtureAttribute) -> [StageFixture] {
        fixtures.filter { $0.attributes.contains(attribute) }
    }

    /// Spread fixtures evenly across the stage.
    private func nextPosition() -> SIMD2<Double> {
        let count = Double(fixtures.count)
        let x = (count.truncatingRemainder(dividingBy: 4) + 0.5) / 4.0
        let y = (floor(count / 4) + 0.5) / 3.0
        return SIMD2(x, min(y, 0.9))
    }
}
