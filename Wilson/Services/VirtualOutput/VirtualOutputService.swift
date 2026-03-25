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

        for fixture in fixtures where fixture.isVirtual {
            guard let fixtureState = fixtureStates[fixture.id] else { continue }

            let color = resolveColor(fixtureState, fixture: fixture)

            states[fixture.id] = VirtualFixtureRenderState(
                fixtureID: fixture.id,
                position: fixture.position,
                trussSlot: fixture.trussSlot,
                color: color,
                intensity: fixtureState.dimmer,
                label: fixture.label
            )
        }

        renderStates = states
    }

    private func resolveColor(_ state: FixtureState, fixture: StageFixture) -> Color {
        if fixture.attributes.contains(.red) {
            return Color(
                red: state.attributes[.red] ?? 0,
                green: state.attributes[.green] ?? 0,
                blue: state.attributes[.blue] ?? 0
            )
        }
        // Single-channel fixtures (strobe): white at dimmer intensity
        return .white
    }
}
