import Foundation
import SwiftData

/// Manages cues, palettes, and transitions between lighting states.
@Observable
final class CueService {
    private(set) var activeCue: Cue?
    private(set) var activePalette: ColorPalette?
    private(set) var isTransitioning = false

    /// Activate a cue with crossfade transition.
    func activateCue(_ cue: Cue) {
        // TODO: Phase 4 — Implement cue activation with crossfade
        activeCue = cue
        activePalette = cue.palette
    }

    /// Instant blackout — safety function.
    func blackout() {
        activeCue = nil
        activePalette = nil
    }
}
