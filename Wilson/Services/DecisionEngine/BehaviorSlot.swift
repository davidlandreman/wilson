import Foundation

/// A behavior assigned to a fixture group with blending weight and parameters.
struct BehaviorSlot: Sendable {
    let behavior: any Behavior
    let groupID: UUID
    /// Blending weight for crossfading (0.0–1.0). 1.0 = fully active.
    var weight: Double = 1.0
    var parameters: BehaviorParameters = BehaviorParameters()
}

/// Tuning parameters passed to behaviors via the context.
struct BehaviorParameters: Sendable {
    /// Multiplier on timing (>1 = faster).
    var speed: Double = 1.0
    /// Multiplier on output strength.
    var intensity: Double = 1.0
    /// Phase offset for staggering across groups (0.0–1.0).
    var offset: Double = 0.0
    /// Sub-variation selector for behaviors with multiple modes.
    var variant: Int = 0
}
