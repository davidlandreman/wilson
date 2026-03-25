import Foundation

/// A composable lighting algorithm that produces fixture attribute values.
/// Behaviors are stateless structs — all temporal state comes from `BehaviorContext`.
protocol Behavior: Sendable {
    /// Unique identifier for this behavior type.
    static var id: String { get }

    /// Which attributes this behavior writes (used for layering/priority).
    var controlledAttributes: Set<FixtureAttribute> { get }

    /// Produce attribute values for the given fixtures.
    /// Returns a map of fixture ID → attribute → value (0.0–1.0).
    func evaluate(
        fixtures: [StageFixture],
        context: BehaviorContext
    ) -> [UUID: [FixtureAttribute: Double]]
}
