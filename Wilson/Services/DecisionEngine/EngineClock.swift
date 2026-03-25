import Foundation

/// Monotonic time tracking for the decision engine.
/// Provides consistent `time` and `deltaTime` across all subsystems each frame.
struct EngineClock: Sendable {
    /// Monotonic seconds since the engine started.
    private(set) var time: Double = 0

    /// Seconds elapsed since the last tick (~0.021s at 47Hz).
    private(set) var deltaTime: Double = 0

    private var lastTickTime: UInt64?

    mutating func tick() {
        let now = DispatchTime.now().uptimeNanoseconds
        if let last = lastTickTime {
            deltaTime = Double(now - last) / 1_000_000_000
        } else {
            deltaTime = 0
        }
        lastTickTime = now
        time += deltaTime
    }

    mutating func reset() {
        time = 0
        deltaTime = 0
        lastTickTime = nil
    }
}
