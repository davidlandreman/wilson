import AppKit
import Foundation
import SwiftUI

/// Render state for a single virtual fixture, consumed by VirtualStageView.
struct VirtualFixtureRenderState: Sendable {
    let fixtureID: UUID
    let position: SIMD2<Double>
    let trussSlot: Int
    let color: Color
    let intensity: Double
    let pan: Double
    let tilt: Double
    let label: String

    /// Pre-resolved NSColor for SceneKit consumption.
    var nsColor: NSColor {
        NSColor(color)
    }
}

/// Translates FixtureState values into visual render states for virtual fixtures.
@Observable
final class VirtualOutputService {
    private(set) var renderStates: [UUID: VirtualFixtureRenderState] = [:]

    func update(fixtureStates: [UUID: FixtureState], fixtures: [StageFixture]) {
        var states: [UUID: VirtualFixtureRenderState] = [:]

        for fixture in fixtures {
            guard let fixtureState = fixtureStates[fixture.id] else { continue }

            let color = resolveColor(fixtureState, fixture: fixture)
            let intensity = resolveIntensity(fixtureState, fixture: fixture)

            states[fixture.id] = VirtualFixtureRenderState(
                fixtureID: fixture.id,
                position: fixture.position,
                trussSlot: fixture.trussSlot,
                color: color,
                intensity: intensity,
                pan: fixtureState.attributes[.pan] ?? 0.5,
                tilt: fixtureState.attributes[.tilt] ?? 0.0,
                label: fixture.label
            )
        }

        renderStates = states
    }

    /// Derive intensity. Fixtures with a dimmer channel use it directly.
    /// Fixtures without (e.g. Betopper 4ch RGBW) derive intensity from the brightest color channel.
    private func resolveIntensity(_ state: FixtureState, fixture: StageFixture) -> Double {
        if fixture.attributes.contains(.dimmer) {
            return state.dimmer
        }
        // No dimmer channel — derive from color output
        let r = state.attributes[.red] ?? 0
        let g = state.attributes[.green] ?? 0
        let b = state.attributes[.blue] ?? 0
        let w = state.attributes[.white] ?? 0
        return max(r, g, b, w)
    }

    private func resolveColor(_ state: FixtureState, fixture: StageFixture) -> Color {
        if fixture.attributes.contains(.red) {
            return Color(
                red: state.attributes[.red] ?? 0,
                green: state.attributes[.green] ?? 0,
                blue: state.attributes[.blue] ?? 0
            )
        }
        if fixture.attributes.contains(.colorWheel) {
            // Color wheel position → approximate hue for visualization.
            // Real color depends on the physical wheel; this gives a visual indication of changes.
            let position = state.attributes[.colorWheel] ?? 0
            if position < 0.01 {
                return .white // Open white
            }
            return Color(hue: position, saturation: 0.8, brightness: 1.0)
        }
        // Single-channel fixtures (strobe, dimmer-only): white
        return .white
    }
}
