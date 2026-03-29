import Foundation
import os.log
import SwiftData

private let logger = Logger(subsystem: "Wilson", category: "FixtureManager")

/// Manages the runtime fixture collection on stage.
/// When a ModelContext is provided via `initialize(context:)`, fixtures persist across launches.
@Observable
final class FixtureManager {
    private(set) var fixtures: [StageFixture] = []
    private var modelContext: ModelContext?

    /// Connect to SwiftData and load any previously saved fixtures.
    func initialize(context: ModelContext) {
        guard modelContext == nil else { return }
        modelContext = context
        loadFromStore()
    }

    /// Add a fixture to the stage from a catalog definition.
    @discardableResult
    func addFixture(definition: FixtureDefinition, label: String, isVirtual: Bool = true, persist: Bool = true) -> StageFixture {
        let fixture = StageFixture(
            label: label,
            definition: definition,
            isVirtual: isVirtual,
            position: nextPosition(),
            trussSlot: fixtures.count
        )
        fixtures.append(fixture)
        if persist {
            saveFixture(fixture)
        }
        return fixture
    }

    /// Remove a fixture by ID.
    func removeFixture(id: UUID) {
        fixtures.removeAll { $0.id == id }
        reindexTrussSlots()
        deleteFixture(id: id)
    }

    /// Remove all fixtures and clear the store.
    func removeAll() {
        let ids = fixtures.map(\.id)
        fixtures.removeAll()
        for id in ids {
            deleteFixture(id: id)
        }
    }

    /// Get all fixtures matching a set of attributes.
    func fixtures(withAttribute attribute: FixtureAttribute) -> [StageFixture] {
        fixtures.filter { $0.attributes.contains(attribute) }
    }

    // MARK: - Persistence

    private func loadFromStore() {
        guard let context = modelContext else { return }
        do {
            let descriptor = FetchDescriptor<PatchedFixture>(sortBy: [SortDescriptor(\.trussSlot)])
            let saved = try context.fetch(descriptor)
            if !saved.isEmpty {
                fixtures = saved.map { $0.toStageFixture() }
                logger.info("Loaded \(saved.count) fixtures from store")
            }
        } catch {
            logger.error("Failed to load fixtures: \(error)")
        }
    }

    private func saveFixture(_ fixture: StageFixture) {
        guard let context = modelContext else { return }
        let patched = PatchedFixture.from(fixture)
        context.insert(patched)
        do {
            try context.save()
            logger.info("Saved fixture '\(fixture.label)'")
        } catch {
            logger.error("Failed to save fixture: \(error)")
        }
    }

    private func deleteFixture(id: UUID) {
        guard let context = modelContext else { return }
        do {
            let predicate = #Predicate<PatchedFixture> { $0.fixtureID == id }
            let descriptor = FetchDescriptor<PatchedFixture>(predicate: predicate)
            let matches = try context.fetch(descriptor)
            for match in matches {
                context.delete(match)
            }
            try context.save()
        } catch {
            logger.error("Failed to delete fixture: \(error)")
        }
    }

    // MARK: - Layout

    /// Reassign contiguous truss slots after a removal.
    private func reindexTrussSlots() {
        for i in fixtures.indices {
            fixtures[i].trussSlot = i
        }
    }

    /// Spread fixtures evenly across the stage.
    private func nextPosition() -> SIMD2<Double> {
        let count = Double(fixtures.count)
        let x = (count.truncatingRemainder(dividingBy: 4) + 0.5) / 4.0
        let y = (floor(count / 4) + 0.5) / 3.0
        return SIMD2(x, min(y, 0.9))
    }
}
