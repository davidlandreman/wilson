import Foundation

/// A scripted set of choreography instructions that the Choreographer applies
/// instead of its autonomous decision-making when a light script is active.
struct ChoreographerDirective: Sendable {
    let groupingStrategy: GroupingEngine.Strategy
    /// Behavior assignments keyed by group role.
    let behaviorSlots: [FixtureGroup.GroupRole: [SlotSpec]]

    /// Specification for a single behavior slot.
    struct SlotSpec: Sendable {
        let behavior: any Behavior
        let parameters: BehaviorParameters
        let weight: Double
    }
}
