import Foundation

/// Meta-decision maker that assigns behaviors to fixture groups and manages transitions.
/// Operates at a slower rate than behaviors — only makes changes on phrase boundaries,
/// energy trajectory shifts, or variety timers.
struct Choreographer: Sendable {
    private(set) var groups: [FixtureGroup] = []
    private(set) var slots: [BehaviorSlot] = []

    /// Number of bars counted (synced from MoodEngine via DecisionEngineService).
    var barCounter = 0

    private var groupingEngine = GroupingEngine()
    private var lastChangeTime: Double = 0
    private var currentScenario: Scenario = .lowEnergy
    private var initialized = false
    /// Tracks which variety sub-variant to use within a scenario.
    private var varietyIndex = 0

    /// Minimum seconds between choreography changes.
    private let minChangeCooldown: Double = 2.0

    enum Scenario: Sendable, Equatable {
        case lowEnergy
        case mediumEnergy
        case highEnergy
        case building
        case peakDrop
        case declining
    }

    mutating func evaluate(
        musicalState: MusicalState,
        mood: MoodState,
        fixtures: [StageFixture],
        time: Double
    ) {
        // Initialize on first call
        if !initialized {
            initialized = true
            applyScenario(.lowEnergy, fixtures: fixtures, time: time)
            return
        }

        // Determine current scenario from mood
        let scenario = classifyScenario(mood: mood)

        // Only change on scenario shift + cooldown elapsed
        let cooldownElapsed = time - lastChangeTime >= minChangeCooldown
        let scenarioChanged = scenario != currentScenario

        // Also change on phrase boundaries with some probability based on chaos
        let phraseChange = musicalState.isDownbeat
            && (barCounter % 4 == 0)
            && cooldownElapsed
            && mood.chaos > 0.4

        if scenarioChanged && cooldownElapsed {
            varietyIndex = 0
            applyScenario(scenario, fixtures: fixtures, time: time)
        } else if phraseChange {
            varietyIndex += 1
            applyScenario(scenario, fixtures: fixtures, time: time)
        }
    }

    private func classifyScenario(mood: MoodState) -> Scenario {
        switch mood.energyTrajectory {
        case .building:
            return .building
        case .declining:
            // Only use declining behaviors when intensity is genuinely low.
            // If we're declining from a high level, stay energetic.
            if mood.intensity > 0.5 {
                return .highEnergy
            } else if mood.intensity > 0.3 {
                return .mediumEnergy
            } else {
                return .declining
            }
        case .sustaining:
            return mood.excitement > 0.55 ? .peakDrop : .highEnergy
        case .stable:
            if mood.intensity > 0.45 {
                return .highEnergy
            } else if mood.intensity > 0.2 {
                return .mediumEnergy
            } else {
                return .lowEnergy
            }
        }
    }

    // MARK: - Scenario Application

    private mutating func applyScenario(
        _ scenario: Scenario,
        fixtures: [StageFixture],
        time: Double
    ) {
        currentScenario = scenario
        lastChangeTime = time

        // Check what capabilities are available
        let hasMovers = fixtures.contains { $0.attributes.contains(.pan) || $0.attributes.contains(.tilt) }

        switch scenario {
        case .lowEnergy:
            applyLowEnergy(fixtures: fixtures, hasMovers: hasMovers)
        case .mediumEnergy:
            applyMediumEnergy(fixtures: fixtures, hasMovers: hasMovers)
        case .highEnergy:
            applyHighEnergy(fixtures: fixtures, hasMovers: hasMovers)
        case .building:
            applyBuilding(fixtures: fixtures, hasMovers: hasMovers)
        case .peakDrop:
            applyPeakDrop(fixtures: fixtures, hasMovers: hasMovers)
        case .declining:
            applyDeclining(fixtures: fixtures, hasMovers: hasMovers)
        }
    }

    private mutating func applyLowEnergy(fixtures: [StageFixture], hasMovers: Bool) {
        // Use capability split so strobes/effect fixtures get beat-reactive treatment
        groups = groupingEngine.group(fixtures: fixtures, strategy: .capabilitySplit)
        slots = []

        for group in groups {
            if group.role == .effect {
                // Dimmer-only fixtures (strobes): beat pulse, not breathe
                slots.append(BehaviorSlot(
                    behavior: BeatPulseBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(intensity: 0.5)
                ))
            } else {
                // Color fixtures and movers: breathe + color wash
                slots.append(BehaviorSlot(
                    behavior: BreatheBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(speed: 0.5, intensity: 0.7)
                ))
                slots.append(BehaviorSlot(
                    behavior: ColorWashBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(speed: 0.5, intensity: 0.8)
                ))
            }

            // Movement for movers
            if group.role == .movement {
                slots.append(BehaviorSlot(
                    behavior: MovementPatternBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(speed: 0.5, intensity: 0.6, variant: MovementPatternBehavior.Pattern.circle.rawValue)
                ))
            }
        }
    }

    private mutating func applyMediumEnergy(fixtures: [StageFixture], hasMovers: Bool) {
        // Always capability split so movers get movement and strobes get beats
        groups = groupingEngine.group(fixtures: fixtures, strategy: .capabilitySplit)
        slots = []

        let useRainbow = varietyIndex.isMultiple(of: 2)

        for (index, group) in groups.enumerated() {
            // All groups get beat pulse
            slots.append(BehaviorSlot(
                behavior: BeatPulseBehavior(),
                groupID: group.id,
                parameters: BehaviorParameters(intensity: 0.8)
            ))

            // Color behavior for fixtures that can do color
            if group.role != .effect {
                if useRainbow {
                    slots.append(BehaviorSlot(
                        behavior: ColorWashBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(speed: 1.0, variant: groups.count > 1 ? 1 : 0)
                    ))
                } else {
                    slots.append(BehaviorSlot(
                        behavior: ColorSplitBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(intensity: 0.9)
                    ))
                }
            }

            // Movement for movers
            if group.role == .movement {
                slots.append(BehaviorSlot(
                    behavior: PanSweepBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(speed: 0.8, intensity: 0.7, offset: Double(index) * 0.3)
                ))
                slots.append(BehaviorSlot(
                    behavior: TiltBounceBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(intensity: 0.5)
                ))
            }
        }
    }

    private mutating func applyHighEnergy(fixtures: [StageFixture], hasMovers: Bool) {
        // Capability split ensures movers get movement, strobes get beats
        groups = groupingEngine.group(fixtures: fixtures, strategy: .capabilitySplit)
        slots = []

        for (index, group) in groups.enumerated() {
            slots.append(BehaviorSlot(
                behavior: BeatPulseBehavior(),
                groupID: group.id,
                parameters: BehaviorParameters(intensity: 1.0)
            ))

            // Color for non-effect fixtures
            if group.role != .effect {
                if varietyIndex.isMultiple(of: 2) {
                    slots.append(BehaviorSlot(
                        behavior: SpectralColorBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(intensity: 1.0)
                    ))
                } else {
                    slots.append(BehaviorSlot(
                        behavior: ColorWashBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(
                            speed: 2.0,
                            offset: Double(index) * 0.5,
                            variant: 1
                        )
                    ))
                }
            }

            // Movement for movers
            if group.role == .movement {
                slots.append(BehaviorSlot(
                    behavior: PanSweepBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(speed: 1.2, intensity: 0.8, offset: Double(index) * 0.25)
                ))
                slots.append(BehaviorSlot(
                    behavior: TiltBounceBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(intensity: 0.8)
                ))
            }
        }
    }

    private mutating func applyBuilding(fixtures: [StageFixture], hasMovers: Bool) {
        groups = groupingEngine.group(fixtures: fixtures, strategy: .capabilitySplit)
        slots = []

        for group in groups {
            slots.append(BehaviorSlot(
                behavior: BeatPulseBehavior(),
                groupID: group.id,
                parameters: BehaviorParameters(speed: 1.2, intensity: 0.9)
            ))

            if group.role != .effect {
                slots.append(BehaviorSlot(
                    behavior: ColorWashBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(speed: 2.5, intensity: 1.0)
                ))
            }

            slots.append(BehaviorSlot(
                behavior: BlackoutAccentBehavior(),
                groupID: group.id
            ))

            if group.role == .movement {
                slots.append(BehaviorSlot(
                    behavior: MovementPatternBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(speed: 1.5, intensity: 0.9, variant: MovementPatternBehavior.Pattern.figure8.rawValue)
                ))
            }
        }
    }

    private mutating func applyPeakDrop(fixtures: [StageFixture], hasMovers: Bool) {
        let useChase = !varietyIndex.isMultiple(of: 2)

        // Capability split so movers get ballyhoo, strobes get strobe
        groups = groupingEngine.group(fixtures: fixtures, strategy: .capabilitySplit)
        slots = []

        for (index, group) in groups.enumerated() {
            if group.role == .effect {
                // Strobes: strobe effect at peak
                slots.append(BehaviorSlot(
                    behavior: StrobeBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(intensity: 1.0)
                ))
                slots.append(BehaviorSlot(
                    behavior: BeatPulseBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(intensity: 1.0)
                ))
            } else if useChase {
                slots.append(BehaviorSlot(
                    behavior: ChaseBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(speed: 1.5, intensity: 1.0)
                ))
            } else {
                slots.append(BehaviorSlot(
                    behavior: BeatPulseBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(intensity: 1.0)
                ))
            }

            if group.role != .effect {
                slots.append(BehaviorSlot(
                    behavior: SpectralColorBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(intensity: 1.0)
                ))
            }

            if group.role == .movement {
                slots.append(BehaviorSlot(
                    behavior: MovementPatternBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(
                        speed: 2.0,
                        intensity: 1.0,
                        offset: Double(index) * 0.5,
                        variant: MovementPatternBehavior.Pattern.ballyhoo.rawValue
                    )
                ))
            }
        }
    }

    private mutating func applyDeclining(fixtures: [StageFixture], hasMovers: Bool) {
        groups = groupingEngine.group(fixtures: fixtures, strategy: .capabilitySplit)
        slots = []

        for group in groups {
            if group.role == .effect {
                // Strobes: moderate beat pulse when declining
                slots.append(BehaviorSlot(
                    behavior: BeatPulseBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(intensity: 0.5)
                ))
            } else {
                slots.append(BehaviorSlot(
                    behavior: BreatheBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(speed: 0.6, intensity: 0.7)
                ))
                slots.append(BehaviorSlot(
                    behavior: ColorWashBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(speed: 0.6, intensity: 0.8)
                ))
            }

            if group.role == .movement {
                slots.append(BehaviorSlot(
                    behavior: PanSweepBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(speed: 0.5, intensity: 0.6)
                ))
            }
        }
    }
}
