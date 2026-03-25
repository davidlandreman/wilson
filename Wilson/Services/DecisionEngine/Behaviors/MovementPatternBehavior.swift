import Foundation

/// Parametric movement patterns for pan/tilt using Lissajous curves.
/// Variant selects pattern: 0 = sweep, 1 = figure-8, 2 = circle, 3 = ballyhoo.
struct MovementPatternBehavior: Behavior {
    static let id = "movementPattern"

    let controlledAttributes: Set<FixtureAttribute> = [.pan, .tilt, .panFine, .tiltFine]

    func evaluate(
        fixtures: [StageFixture],
        context: BehaviorContext
    ) -> [UUID: [FixtureAttribute: Double]] {
        guard !context.musicalState.isSilent else { return [:] }

        let speed = context.parameters.speed
        let intensity = context.parameters.intensity
        let movementScale = context.movementIntensity
        let amplitude = 0.4 * intensity * movementScale

        // Phase advances continuously based on BPM-derived timing.
        // One full cycle per N beats, using monotonic time for smooth motion.
        let beatsPerSecond = max(1, context.beat.bpm) / 60.0
        let cyclesPerSecond = beatsPerSecond / 8.0 * speed // one cycle per 8 beats by default
        let basePhase = context.time * cyclesPerSecond + context.parameters.offset

        let pattern = Pattern(rawValue: context.parameters.variant) ?? .sweep

        var result: [UUID: [FixtureAttribute: Double]] = [:]

        for (index, fixture) in fixtures.enumerated() {
            guard fixture.attributes.contains(.pan) || fixture.attributes.contains(.tilt) else {
                continue
            }

            // Per-fixture phase offset for spatial variation
            let fixturePhase: Double
            if fixtures.count > 1 {
                fixturePhase = basePhase + Double(index) / Double(fixtures.count) * 0.25
            } else {
                fixturePhase = basePhase
            }

            let (pan, tilt) = pattern.evaluate(phase: fixturePhase, amplitude: amplitude)

            var attrs: [FixtureAttribute: Double] = [:]
            if fixture.attributes.contains(.pan) {
                attrs[.pan] = max(0, min(1, pan))
            }
            if fixture.attributes.contains(.tilt) {
                attrs[.tilt] = max(0, min(1, tilt))
            }
            result[fixture.id] = attrs
        }

        return result
    }

    /// Tilt home position: ~30° from straight down, pointing at the audience.
    /// 0.0 = straight down, 0.5 = horizontal, so 0.17 ≈ 30° outward.
    static let tiltHome: Double = 0.17

    enum Pattern: Int, Sendable {
        case sweep = 0
        case figure8 = 1
        case circle = 2
        case ballyhoo = 3

        func evaluate(phase: Double, amplitude: Double) -> (pan: Double, tilt: Double) {
            let p = phase * 2 * .pi
            let tiltCenter = MovementPatternBehavior.tiltHome

            switch self {
            case .sweep:
                // Horizontal sweep only, tilt stays at home
                return (
                    pan: 0.5 + amplitude * sin(p),
                    tilt: tiltCenter
                )

            case .figure8:
                // Lissajous 2:1 ratio
                return (
                    pan: 0.5 + amplitude * sin(p),
                    tilt: tiltCenter + amplitude * 0.5 * sin(p * 2)
                )

            case .circle:
                return (
                    pan: 0.5 + amplitude * sin(p),
                    tilt: tiltCenter + amplitude * 0.5 * cos(p)
                )

            case .ballyhoo:
                // Fast, organic-looking motion using incommensurate frequencies
                return (
                    pan: 0.5 + amplitude * sin(p * 1.0 + sin(p * 0.3) * 0.5),
                    tilt: tiltCenter + amplitude * 0.4 * sin(p * 1.7 + cos(p * 0.5) * 0.4)
                )
            }
        }
    }
}
