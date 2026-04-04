import Foundation

/// Manages light script loading, playback state, timeline tracking, and directive generation.
/// When a script is active, this service drives the Choreographer instead of autonomous mode.
@Observable
final class LightScriptService {

    // MARK: - Playback State

    enum PlaybackState: Sendable {
        case idle
        case armed
        case playing
        case finished
    }

    private(set) var playbackState: PlaybackState = .idle

    // MARK: - Public Observables

    private(set) var currentBar: Int = 0
    private(set) var currentBeatInBar: Double = 0
    private(set) var currentCueLabel: String?
    private(set) var progress: Double = 0

    /// Whether the script is actively playing (convenience for AppState).
    var isPlaying: Bool { playbackState == .playing }

    // MARK: - Script Data

    private(set) var script: LightScript?

    // MARK: - Playback Internals

    private var startTime: Double = 0
    private var currentBeatPosition: Double = 0
    private var previousBeatPosition: Double = 0
    private var activeCueIndex: Int = 0
    private var resolvedState: ScriptCueState = ScriptCueState()
    private var activeEvents: [ActiveEvent] = []

    /// Precomputed absolute beat positions for each cue (sorted).
    private var cueBeats: [Double] = []
    /// Precomputed absolute beat positions for each event.
    private var eventBeats: [Double] = []
    /// Next event index to check (events are processed in order).
    private var nextEventIndex: Int = 0
    /// Active blackout from event (forces dimmer=0).
    private(set) var isEventBlackout: Bool = false
    /// Active flash intensity (decays each frame).
    private(set) var flashIntensity: Double = 0

    private struct ActiveEvent {
        let event: ScriptEvent
        let endBeat: Double
    }

    // MARK: - Loading

    func loadScript(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(LightScript.self, from: data)
        loadScript(decoded)
    }

    func loadScript(_ newScript: LightScript) {
        script = newScript
        let beatsPerBar = newScript.beatsPerBar

        // Precompute cue beat positions
        cueBeats = newScript.cues.map { $0.absoluteBeat(beatsPerBar: beatsPerBar) }

        // Precompute event beat positions
        eventBeats = newScript.events.map { $0.absoluteBeat(beatsPerBar: beatsPerBar) }

        // Initialize resolved state from defaults
        resolvedState = newScript.defaultState

        // Apply first cue's state if it starts at beat 0
        if let firstCue = newScript.cues.first {
            resolvedState = resolvedState.merging(firstCue.state)
        }

        activeCueIndex = 0
        nextEventIndex = 0
        activeEvents = []
        isEventBlackout = false
        flashIntensity = 0
        currentBeatPosition = 0
        previousBeatPosition = 0
        currentBar = 0
        currentBeatInBar = 0
        currentCueLabel = newScript.cues.first?.label
        progress = 0
        playbackState = .armed
    }

    func unloadScript() {
        script = nil
        playbackState = .idle
        currentBar = 0
        currentBeatInBar = 0
        currentCueLabel = nil
        progress = 0
        resolvedState = ScriptCueState()
        activeEvents = []
        isEventBlackout = false
        flashIntensity = 0
    }

    // MARK: - Frame Update

    func update(engineTime: Double, deltaTime: Double, isSilent: Bool) {
        switch playbackState {
        case .idle, .finished:
            return

        case .armed:
            // Transition to playing on first sound
            if !isSilent {
                startTime = engineTime
                currentBeatPosition = 0
                previousBeatPosition = 0
                playbackState = .playing
            }
            return

        case .playing:
            break
        }

        guard let script else { return }

        // Advance timeline
        previousBeatPosition = currentBeatPosition
        let elapsed = engineTime - startTime
        let beatsPerSecond = script.metadata.bpm / 60.0
        currentBeatPosition = elapsed * beatsPerSecond

        let beatsPerBar = script.beatsPerBar

        // Update display state
        currentBar = Int(currentBeatPosition / Double(beatsPerBar)) + 1
        currentBeatInBar = currentBeatPosition.truncatingRemainder(dividingBy: Double(beatsPerBar)) + 1.0

        if let totalBeats = script.totalBeats, totalBeats > 0 {
            progress = min(currentBeatPosition / totalBeats, 1.0)
        }

        // Check for finished
        if let totalBeats = script.totalBeats, currentBeatPosition >= totalBeats {
            playbackState = .finished
            return
        }

        // Advance cues
        advanceCues(script: script)

        // Process events
        advanceEvents(script: script, deltaTime: deltaTime, beatsPerSecond: beatsPerSecond)
    }

    // MARK: - Cue Advancement

    private func advanceCues(script: LightScript) {
        // Find the last cue whose beat position we've passed
        var advanced = false
        while activeCueIndex + 1 < script.cues.count {
            let nextBeat = cueBeats[activeCueIndex + 1]
            if currentBeatPosition >= nextBeat {
                activeCueIndex += 1
                advanced = true
            } else {
                break
            }
        }

        if advanced {
            let cue = script.cues[activeCueIndex]
            resolvedState = resolvedState.merging(cue.state)
            currentCueLabel = cue.label ?? currentCueLabel
        }
    }

    // MARK: - Event Processing

    private func advanceEvents(script: LightScript, deltaTime: Double, beatsPerSecond: Double) {
        // Trigger new events
        while nextEventIndex < script.events.count {
            let eventBeat = eventBeats[nextEventIndex]
            if currentBeatPosition >= eventBeat {
                let event = script.events[nextEventIndex]
                let endBeat = eventBeat + (event.durationBeats ?? (1.0 / beatsPerSecond * 0.05))
                activeEvents.append(ActiveEvent(event: event, endBeat: endBeat))
                nextEventIndex += 1
            } else {
                break
            }
        }

        // Process active events and expire finished ones
        isEventBlackout = false
        var hasStrobeBurst = false

        activeEvents.removeAll { active in
            if currentBeatPosition >= active.endBeat {
                return true // expired
            }

            switch active.event.type {
            case .blackout:
                isEventBlackout = true
            case .flash:
                // Flash sets intensity on first frame, then decays
                if previousBeatPosition < eventBeats.first(where: {
                    $0 == active.endBeat - (active.event.durationBeats ?? 0.05)
                }) ?? 0 {
                    flashIntensity = active.event.intensity ?? 1.0
                }
            case .strobeBurst:
                hasStrobeBurst = true
            }
            return false
        }

        // Decay flash
        if flashIntensity > 0 {
            flashIntensity *= max(0, 1.0 - deltaTime * 20.0) // ~50ms decay
            if flashIntensity < 0.01 { flashIntensity = 0 }
        }

        // Note: strobeBurst is handled by injecting StrobeBehavior into the directive
        _ = hasStrobeBurst
    }

    // MARK: - Directive Generation

    /// Generate the current choreographer directive from the resolved script state.
    func currentDirective() -> ChoreographerDirective? {
        guard playbackState == .playing, let script else { return nil }

        let strategy = resolvedState.groupingStrategy
            .flatMap { BehaviorRegistry.groupingStrategy(for: $0) }
            ?? .capabilitySplit

        // Build behavior slots from the active cue's behavior map
        var slotMap: [FixtureGroup.GroupRole: [ChoreographerDirective.SlotSpec]] = [:]

        if let cue = script.cues[safe: activeCueIndex],
           let behaviors = cue.behaviors ?? script.cues[safe: findLastCueWithBehaviors()]?.behaviors {
            for (roleName, assignments) in behaviors {
                guard let role = BehaviorRegistry.groupRole(for: roleName) else { continue }
                let specs = assignments.compactMap { assignment -> ChoreographerDirective.SlotSpec? in
                    guard let behavior = BehaviorRegistry.behavior(for: assignment.id) else { return nil }
                    let params = BehaviorParameters(
                        speed: assignment.speed ?? 1.0,
                        intensity: assignment.intensity ?? 1.0,
                        offset: assignment.offset ?? 0.0,
                        variant: assignment.variant ?? 0
                    )
                    return ChoreographerDirective.SlotSpec(
                        behavior: behavior,
                        parameters: params,
                        weight: assignment.weight ?? 1.0
                    )
                }
                slotMap[role] = specs
            }
        }

        // Inject strobeBurst events as additional effect slots
        let hasStrobeBurst = activeEvents.contains { $0.event.type == .strobeBurst }
        if hasStrobeBurst {
            let strobeEvent = activeEvents.first { $0.event.type == .strobeBurst }
            let strobeSpec = ChoreographerDirective.SlotSpec(
                behavior: StrobeBehavior(),
                parameters: BehaviorParameters(
                    intensity: strobeEvent?.event.intensity ?? 1.0,
                    variant: strobeEvent?.event.variant ?? StrobeBehavior.Mode.onsetReactive.rawValue
                ),
                weight: 1.0
            )
            // Add strobe to all roles
            for role in [FixtureGroup.GroupRole.primary, .accent, .movement, .effect, .all] {
                slotMap[role, default: []].append(strobeSpec)
            }
        }

        return ChoreographerDirective(
            groupingStrategy: strategy,
            behaviorSlots: slotMap
        )
    }

    /// Walk backward from activeCueIndex to find the most recent cue with behaviors defined.
    private func findLastCueWithBehaviors() -> Int {
        guard let script else { return 0 }
        var idx = activeCueIndex
        while idx >= 0 {
            if script.cues[idx].behaviors != nil { return idx }
            idx -= 1
        }
        return 0
    }

    // MARK: - Active palette/reactivity for AppState

    var activePalette: ColorPalette? {
        guard isPlaying else { return nil }
        return resolvedState.palette.map { ColorPalette(name: "Script", colors: $0) }
    }

    var activeReactivity: Double? {
        guard isPlaying else { return nil }
        return resolvedState.reactivity
    }

    var activeMovementIntensity: Double? {
        guard isPlaying else { return nil }
        return resolvedState.movementIntensity
    }

    // MARK: - MusicalState Overlay

    /// Replace BPM and beat timing in MusicalState with script-derived values.
    /// Preserves real audio energy, spectral, and onset data so behaviors still react.
    func overlayMusicalState(_ state: MusicalState) -> MusicalState {
        guard playbackState == .playing, let script else { return state }

        var modified = state
        modified.bpm = script.metadata.bpm
        modified.bpmConfidence = 1.0

        let beatsPerBar = Double(script.beatsPerBar)

        // Beat phase: fractional part of current beat (0→1 sawtooth)
        modified.beatPhase = currentBeatPosition.truncatingRemainder(dividingBy: 1.0)

        // Beat position within bar (0.0 ..< beatsPerBar)
        modified.beatPosition = currentBeatPosition.truncatingRemainder(dividingBy: beatsPerBar)

        // Detect beat crossing: did we cross an integer beat boundary this frame?
        let prevWholeBeat = Int(previousBeatPosition)
        let currWholeBeat = Int(currentBeatPosition)
        modified.isBeat = currWholeBeat > prevWholeBeat && previousBeatPosition > 0

        // Detect downbeat: did we cross a bar boundary?
        let prevBar = Int(previousBeatPosition / beatsPerBar)
        let currBar = Int(currentBeatPosition / beatsPerBar)
        modified.isDownbeat = currBar > prevBar && previousBeatPosition > 0

        return modified
    }
}

// MARK: - Array Safe Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
