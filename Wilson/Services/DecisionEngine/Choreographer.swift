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
    private(set) var currentScenario: Scenario = .lowEnergy
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
        // Composite energy score: blends multiple mood dimensions so that
        // bright, fast, chaotic music reads as high-energy even when raw
        // volume/intensity is moderate (e.g. Sandstorm's drop sections).
        let energyScore = mood.intensity * 0.35
            + mood.excitement * 0.30
            + mood.brightness * 0.20
            + mood.chaos * 0.15

        // Base scenario from composite score
        let base: Scenario
        if energyScore > 0.55 {
            base = .highEnergy
        } else if energyScore > 0.30 {
            base = .mediumEnergy
        } else {
            base = .lowEnergy
        }

        // Trajectory modifies the base — it's a boost/tint, not the sole driver.
        switch mood.energyTrajectory {
        case .building:
            // Only use building behaviors when energy is at least moderate;
            // a quiet fade-in shouldn't get the building treatment.
            return base == .lowEnergy ? base : .building
        case .sustaining:
            // Peak requires genuinely high energy AND excitement.
            // Raised thresholds so builds and breakdowns don't trigger peak.
            if energyScore > 0.65 && mood.excitement > 0.75 {
                return .peakDrop
            }
            return base == .lowEnergy ? .mediumEnergy : base
        case .declining:
            // Declining from a high level stays at whatever the composite says.
            // Only use declining behaviors when the composite is truly low.
            return base == .lowEnergy ? .declining : base
        case .stable:
            return base
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
                // Strobe stays dark at low energy — save it for higher scenarios
                continue
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
        // Split movers into pairs so they can run independent movement
        groups = groupingEngine.group(fixtures: fixtures, strategy: hasMovers ? .moverPairSplit : .capabilitySplit)
        slots = []

        let useRainbow = varietyIndex.isMultiple(of: 2)
        // Swap mover pair roles every variety change so they trade behaviors
        let swapMoverRoles = !varietyIndex.isMultiple(of: 2)
        var moverGroupCount = 0

        for (index, group) in groups.enumerated() {
            // Effect fixtures: mostly dark, occasional punchy accent
            if group.role == .effect {
                if varietyIndex % 4 == 3 {
                    // One in four phrases: downbeat punches
                    slots.append(BehaviorSlot(
                        behavior: StrobeBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(intensity: 0.6, variant: StrobeBehavior.Mode.punchy.rawValue)
                    ))
                }
                // Otherwise strobe stays dark
                continue
            }

            // Mover dimmer: cycle between different looks
            if group.role == .movement {
                switch varietyIndex % 4 {
                case 0:
                    // Alternating beat pulse between mover pairs
                    let beatOffset = Double(moverGroupCount) * 1.0
                    slots.append(BehaviorSlot(
                        behavior: BeatPulseBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(
                            intensity: 0.8,
                            offset: beatOffset,
                            variant: BeatPulseBehavior.Mode.alternating.rawValue
                        )
                    ))
                case 1:
                    // Breathe — smooth sine wave, no beat pulsing
                    slots.append(BehaviorSlot(
                        behavior: BreatheBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(speed: 0.8, intensity: 0.8)
                    ))
                case 2:
                    // No dimmer behavior — color wash alone drives brightness
                    break
                default:
                    // Standard beat pulse
                    slots.append(BehaviorSlot(
                        behavior: BeatPulseBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(intensity: 0.7)
                    ))
                }
            } else {
                // Non-mover, non-effect: standard beat pulse
                slots.append(BehaviorSlot(
                    behavior: BeatPulseBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(intensity: 0.8)
                ))
            }

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

            // Movement: alternate behaviors across mover sub-groups, swap on variety
            if group.role == .movement {
                let isRandomGroup = (moverGroupCount == 0) != swapMoverRoles
                if isRandomGroup {
                    slots.append(BehaviorSlot(
                        behavior: RandomLookBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(speed: 0.8, intensity: 0.7)
                    ))
                } else {
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
                moverGroupCount += 1
            }
        }
    }

    private mutating func applyHighEnergy(fixtures: [StageFixture], hasMovers: Bool) {
        // Cycle through 4 movement looks:
        //   0: pair split — random looks vs pan sweep + bounce
        //   1: pair split — swapped roles
        //   2: all movers — alternating tilt sweep
        //   3: all movers — ballyhoo
        let movementVariant = varietyIndex % 4
        let usePairSplit = hasMovers && movementVariant < 2
        let strategy: GroupingEngine.Strategy = usePairSplit ? .moverPairSplit : .capabilitySplit
        groups = groupingEngine.group(fixtures: fixtures, strategy: strategy)
        slots = []

        let effectVariant = varietyIndex % 4
        var moverGroupCount = 0

        for (index, group) in groups.enumerated() {
            // Effect fixtures: cycle strobe modes
            if group.role == .effect {
                switch effectVariant {
                case 0:
                    // Onset-reactive flashes on a beat pulse base
                    slots.append(BehaviorSlot(
                        behavior: StrobeBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(intensity: 0.9, variant: StrobeBehavior.Mode.onsetReactive.rawValue)
                    ))
                    slots.append(BehaviorSlot(
                        behavior: BeatPulseBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(intensity: 0.8)
                    ))
                case 1:
                    // Rapid rhythmic strobe
                    slots.append(BehaviorSlot(
                        behavior: StrobeBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(intensity: 0.85, variant: StrobeBehavior.Mode.subdivision.rawValue)
                    ))
                    slots.append(BehaviorSlot(
                        behavior: BeatPulseBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(intensity: 0.7)
                    ))
                case 2:
                    // Half-time slam
                    slots.append(BehaviorSlot(
                        behavior: StrobeBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(intensity: 0.9, variant: StrobeBehavior.Mode.halfTime.rawValue)
                    ))
                    slots.append(BehaviorSlot(
                        behavior: BeatPulseBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(intensity: 0.85)
                    ))
                default:
                    // Plain beat pulse (contrast/relief)
                    slots.append(BehaviorSlot(
                        behavior: BeatPulseBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(intensity: 1.0)
                    ))
                }
            }

            // Beat pulse — alternating between mover groups when pair-split
            if group.role == .movement && usePairSplit {
                let beatOffset = Double(moverGroupCount) * 1.0
                slots.append(BehaviorSlot(
                    behavior: BeatPulseBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(
                        intensity: 1.0,
                        offset: beatOffset,
                        variant: BeatPulseBehavior.Mode.alternating.rawValue
                    )
                ))
            } else if group.role != .effect {
                slots.append(BehaviorSlot(
                    behavior: BeatPulseBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(intensity: 1.0)
                ))
            }

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

            // Movement
            if group.role == .movement {
                switch movementVariant {
                case 0:
                    // Pair A: random looks, Pair B: sweep + bounce
                    if moverGroupCount == 0 {
                        slots.append(BehaviorSlot(
                            behavior: RandomLookBehavior(),
                            groupID: group.id,
                            parameters: BehaviorParameters(speed: 1.2, intensity: 0.9)
                        ))
                    } else {
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
                case 1:
                    // Swapped: Pair A: sweep + bounce, Pair B: random looks
                    if moverGroupCount == 0 {
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
                    } else {
                        slots.append(BehaviorSlot(
                            behavior: RandomLookBehavior(),
                            groupID: group.id,
                            parameters: BehaviorParameters(speed: 1.2, intensity: 0.9)
                        ))
                    }
                case 2:
                    // All movers: alternating tilt sweep
                    slots.append(BehaviorSlot(
                        behavior: TiltSweepBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(speed: 1.2, intensity: 1.0)
                    ))
                default:
                    // All movers: ballyhoo
                    slots.append(BehaviorSlot(
                        behavior: MovementPatternBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(
                            speed: 1.5,
                            intensity: 1.0,
                            offset: Double(index) * 0.25,
                            variant: MovementPatternBehavior.Pattern.ballyhoo.rawValue
                        )
                    ))
                }
                moverGroupCount += 1
            }
        }
    }

    private mutating func applyBuilding(fixtures: [StageFixture], hasMovers: Bool) {
        groups = groupingEngine.group(fixtures: fixtures, strategy: .capabilitySplit)
        slots = []

        let effectVariant = varietyIndex % 3

        for group in groups {
            // Effect fixtures: cycle strobe modes during build
            if group.role == .effect {
                switch effectVariant {
                case 1:
                    // Downbeat punches accelerating with the build
                    slots.append(BehaviorSlot(
                        behavior: StrobeBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(speed: 1.3, intensity: 0.85, variant: StrobeBehavior.Mode.punchy.rawValue)
                    ))
                    slots.append(BehaviorSlot(
                        behavior: BeatPulseBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(speed: 1.2, intensity: 0.8)
                    ))
                case 2:
                    // Subdivision strobe teasing the upcoming drop
                    slots.append(BehaviorSlot(
                        behavior: StrobeBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(intensity: 0.8, variant: StrobeBehavior.Mode.subdivision.rawValue)
                    ))
                    slots.append(BehaviorSlot(
                        behavior: BeatPulseBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(speed: 1.2, intensity: 0.7)
                    ))
                default:
                    // Current: beat pulse only
                    slots.append(BehaviorSlot(
                        behavior: BeatPulseBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(speed: 1.2, intensity: 0.9)
                    ))
                }
            } else {
                // Non-effect groups: beat pulse + color wash
                slots.append(BehaviorSlot(
                    behavior: BeatPulseBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(speed: 1.2, intensity: 0.9)
                ))
                slots.append(BehaviorSlot(
                    behavior: ColorWashBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(speed: 2.5, intensity: 1.0)
                ))
            }

            // BlackoutAccent for all groups
            slots.append(BehaviorSlot(
                behavior: BlackoutAccentBehavior(),
                groupID: group.id
            ))

            if group.role == .movement {
                switch varietyIndex % 3 {
                case 0:
                    slots.append(BehaviorSlot(
                        behavior: MovementPatternBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(speed: 1.5, intensity: 0.9, variant: MovementPatternBehavior.Pattern.figure8.rawValue)
                    ))
                case 1:
                    slots.append(BehaviorSlot(
                        behavior: TiltSweepBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(speed: 1.5, intensity: 0.9)
                    ))
                default:
                    slots.append(BehaviorSlot(
                        behavior: MovementPatternBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(speed: 1.5, intensity: 0.9, variant: MovementPatternBehavior.Pattern.ballyhoo.rawValue)
                    ))
                }
            }
        }
    }

    private mutating func applyPeakDrop(fixtures: [StageFixture], hasMovers: Bool) {
        let useChase = !varietyIndex.isMultiple(of: 2)

        // Split movers for peak moments — one pair ballyhoos, the other scans
        groups = groupingEngine.group(fixtures: fixtures, strategy: hasMovers ? .moverPairSplit : .capabilitySplit)
        slots = []

        let swapMoverRoles = !varietyIndex.isMultiple(of: 2)
        var moverGroupCount = 0

        let effectVariant = varietyIndex % 3

        for (index, group) in groups.enumerated() {
            if group.role == .effect {
                // Strobes: cycle modes at peak — all full intensity
                switch effectVariant {
                case 1:
                    // Relentless rapid strobe
                    slots.append(BehaviorSlot(
                        behavior: StrobeBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(intensity: 1.0, variant: StrobeBehavior.Mode.subdivision.rawValue)
                    ))
                    slots.append(BehaviorSlot(
                        behavior: BeatPulseBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(intensity: 0.9)
                    ))
                case 2:
                    // Heavy half-time slam
                    slots.append(BehaviorSlot(
                        behavior: StrobeBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(intensity: 1.0, variant: StrobeBehavior.Mode.halfTime.rawValue)
                    ))
                    slots.append(BehaviorSlot(
                        behavior: BeatPulseBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(intensity: 1.0)
                    ))
                default:
                    // Onset-reactive (current behavior)
                    slots.append(BehaviorSlot(
                        behavior: StrobeBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(intensity: 1.0, variant: StrobeBehavior.Mode.onsetReactive.rawValue)
                    ))
                    slots.append(BehaviorSlot(
                        behavior: BeatPulseBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(intensity: 1.0)
                    ))
                }
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
                let isBallyhooGroup = (moverGroupCount == 0) != swapMoverRoles
                if isBallyhooGroup {
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
                } else {
                    // Other pair: fast random scanning
                    slots.append(BehaviorSlot(
                        behavior: RandomLookBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(speed: 1.5, intensity: 1.0)
                    ))
                }
                moverGroupCount += 1
            }
        }
    }

    private mutating func applyDeclining(fixtures: [StageFixture], hasMovers: Bool) {
        groups = groupingEngine.group(fixtures: fixtures, strategy: .capabilitySplit)
        slots = []

        for group in groups {
            if group.role == .effect {
                // Strobe stays dark when declining
                continue
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
