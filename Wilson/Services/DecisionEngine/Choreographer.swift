import Foundation

/// Meta-decision maker that assigns behaviors to fixture groups and manages transitions.
/// Operates at a slower rate than behaviors — only makes changes on phrase boundaries,
/// energy trajectory shifts, or variety timers.
struct Choreographer: Sendable {
    private(set) var groups: [FixtureGroup] = []
    private(set) var slots: [BehaviorSlot] = []

    /// Number of bars counted (synced from MoodEngine via DecisionEngineService).
    var barCounter = 0

    /// Scene library for autonomous scene selection and blending.
    var sceneLibrary = SceneLibrary()

    private var groupingEngine = GroupingEngine()
    private var lookGenerator = LookGenerator()
    private var lastChangeTime: Double = 0
    private(set) var currentScenario: Scenario = .lowEnergy
    private var initialized = false

    /// Minimum seconds between choreography changes.
    private let minChangeCooldown: Double = 2.0

    // MARK: - Pacing

    /// Bars remaining before next variety change is allowed.
    private var holdBarsRemaining: Int = 0
    /// Last bar count seen (for decrementing hold).
    private var lastBarCount: Int = 0

    enum PacingMode: Sendable {
        case patient   // 1.5× base hold
        case moderate  // 1× base hold
        case restless  // 0.5× base hold
    }

    // MARK: - Variety Tracking

    /// Recent picks per dimension to avoid short-cycle repeats.
    private var recentDimmerVariant: [Int] = []
    private var recentColorVariant: [Int] = []
    private var recentMovementVariant: [Int] = []
    private var recentGroupingVariant: [Int] = []

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
        palette: ResolvedPalette,
        time: Double
    ) {
        // Initialize on first call — no generated look yet (mood hasn't settled)
        if !initialized {
            initialized = true
            applyScenario(.lowEnergy, fixtures: fixtures, time: time)
            return
        }

        // Decrement hold timer on new bars
        if barCounter > lastBarCount {
            holdBarsRemaining = max(0, holdBarsRemaining - (barCounter - lastBarCount))
            lastBarCount = barCounter
        }

        // Determine current scenario from mood
        let scenario = classifyScenario(mood: mood)

        // Only change on scenario shift + cooldown elapsed
        let cooldownElapsed = time - lastChangeTime >= minChangeCooldown
        let scenarioChanged = scenario != currentScenario

        // Phrase-boundary changes: governed by pacing hold instead of chaos gate
        let phraseChange = musicalState.isDownbeat
            && (barCounter % 4 == 0)
            && cooldownElapsed
            && holdBarsRemaining <= 0

        if scenarioChanged && cooldownElapsed {
            applyScenario(scenario, fixtures: fixtures, time: time)
            sceneLibrary.generatedLook = lookGenerator.generate(
                fixtures: fixtures, scenario: scenario, mood: mood,
                palette: palette, seed: barCounter
            )
            sceneLibrary.selectScene(scenario: scenario, mood: mood)
            holdBarsRemaining = computeHoldBars(scenario: scenario)
        } else if phraseChange {
            applyScenario(scenario, fixtures: fixtures, time: time)
            sceneLibrary.generatedLook = lookGenerator.generate(
                fixtures: fixtures, scenario: scenario, mood: mood,
                palette: palette, seed: barCounter
            )
            sceneLibrary.selectScene(scenario: scenario, mood: mood)
            holdBarsRemaining = computeHoldBars(scenario: scenario)
        }
    }

    /// Advance scene crossfade. Called every frame from DecisionEngineService.
    mutating func tickSceneTransition(deltaTime: Double) {
        sceneLibrary.tick(deltaTime: deltaTime)
    }

    // MARK: - Pacing

    private func currentPacing() -> PacingMode {
        // Rotate pacing mode every ~32 bars
        switch (barCounter / 32) % 3 {
        case 0: .moderate
        case 1: .patient
        default: .restless
        }
    }

    private func computeHoldBars(scenario: Scenario) -> Int {
        let base: Int = switch scenario {
        case .lowEnergy: 12
        case .mediumEnergy: 8
        case .highEnergy: 4
        case .building: 16
        case .peakDrop: 4
        case .declining: 12
        }

        let multiplier: Double = switch currentPacing() {
        case .patient: 1.5
        case .moderate: 1.0
        case .restless: 0.5
        }

        // Small jitter: ±1 bar via seed
        let jitter = (LookGenerator.deterministicHash(barCounter) % 3) - 1
        return max(2, Int(Double(base) * multiplier) + jitter)
    }

    // MARK: - Scenario Classification

    private func classifyScenario(mood: MoodState) -> Scenario {
        let energyScore = mood.intensity * 0.35
            + mood.excitement * 0.30
            + mood.brightness * 0.20
            + mood.chaos * 0.15

        let base: Scenario
        if energyScore > 0.55 {
            base = .highEnergy
        } else if energyScore > 0.30 {
            base = .mediumEnergy
        } else {
            base = .lowEnergy
        }

        switch mood.energyTrajectory {
        case .building:
            return base == .lowEnergy ? base : .building
        case .sustaining:
            if energyScore > 0.65 && mood.excitement > 0.75 {
                return .peakDrop
            }
            return base == .lowEnergy ? .mediumEnergy : base
        case .declining:
            return base == .lowEnergy ? .declining : base
        case .stable:
            return base
        }
    }

    // MARK: - Variety Selection

    /// Deterministic weighted selection that avoids recent picks.
    private static func pickVariant(
        count: Int,
        seed: Int,
        recent: [Int],
        salt: Int = 0
    ) -> Int {
        guard count > 0 else { return 0 }

        // Build weights: 1.0 for each option, penalize recent
        var weights = [Double](repeating: 1.0, count: count)
        for r in recent {
            if r < count {
                weights[r] *= 0.15 // Heavy penalty, not zero (fallback possible)
            }
        }

        let hash = LookGenerator.deterministicHash(seed &+ salt)
        let total = weights.reduce(0, +)
        let target = Double(hash % 1000) / 1000.0 * total

        var accumulated = 0.0
        for (i, w) in weights.enumerated() {
            accumulated += w
            if target < accumulated { return i }
        }
        return count - 1
    }

    /// Track a pick in a recent-history array (keeps last 2).
    private static func track(_ pick: Int, in recent: inout [Int]) {
        recent.append(pick)
        if recent.count > 2 { recent.removeFirst() }
    }

    // MARK: - Parameter Jitter

    /// Slightly randomize slot parameters so the same behavior combo feels different.
    private mutating func jitterParameters() {
        for i in slots.indices {
            let hash = LookGenerator.deterministicHash(barCounter &+ i &* 7)
            let speedJitter = (Double(hash % 100) / 100.0 - 0.5) * 0.3  // ±0.15
            let intensityJitter = (Double((hash >> 8) % 100) / 100.0 - 0.5) * 0.2  // ±0.1
            let offsetJitter = (Double((hash >> 16) % 100) / 100.0 - 0.5) * 0.4  // ±0.2

            slots[i].parameters.speed = max(0.1, slots[i].parameters.speed + speedJitter)
            slots[i].parameters.intensity = (slots[i].parameters.intensity + intensityJitter).clamped(to: 0...1)
            slots[i].parameters.offset += offsetJitter
        }
    }

    // MARK: - Helpers

    /// Check if a group contains any fixtures with pan/tilt capability.
    /// Used instead of `group.role == .movement` so movers get movement behaviors
    /// regardless of which grouping strategy created the group.
    private func groupHasMovers(_ group: FixtureGroup, fixtures: [StageFixture]) -> Bool {
        fixtures.contains { fixture in
            group.fixtureIDs.contains(fixture.id)
                && (fixture.attributes.contains(.pan) || fixture.attributes.contains(.tilt))
        }
    }

    /// Check if a group contains any fixtures with a strobe channel.
    private func groupHasStrobe(_ group: FixtureGroup, fixtures: [StageFixture]) -> Bool {
        fixtures.contains { fixture in
            group.fixtureIDs.contains(fixture.id) && fixture.attributes.contains(.strobe)
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

        jitterParameters()
    }

    // MARK: - Low Energy

    private mutating func applyLowEnergy(fixtures: [StageFixture], hasMovers: Bool) {
        let groupVariant = Self.pickVariant(count: 3, seed: barCounter, recent: recentGroupingVariant, salt: 100)
        Self.track(groupVariant, in: &recentGroupingVariant)

        let strategy: GroupingEngine.Strategy = switch groupVariant {
        case 0: .capabilitySplit
        case 1: hasMovers ? .soloBackground : .capabilitySplit
        default: .spatialSplit
        }
        groups = groupingEngine.group(fixtures: fixtures, strategy: strategy)
        slots = []

        let colorVariant = Self.pickVariant(count: 3, seed: barCounter, recent: recentColorVariant, salt: 200)
        Self.track(colorVariant, in: &recentColorVariant)

        let movementVariant = Self.pickVariant(count: 3, seed: barCounter, recent: recentMovementVariant, salt: 300)
        Self.track(movementVariant, in: &recentMovementVariant)

        for group in groups {
            if group.role == .effect { continue }

            // Dimmer: always breathe at low energy
            slots.append(BehaviorSlot(
                behavior: BreatheBehavior(),
                groupID: group.id,
                parameters: BehaviorParameters(speed: 0.5, intensity: 0.7)
            ))

            // Color: cycle through options
            switch colorVariant {
            case 0:
                slots.append(BehaviorSlot(
                    behavior: ColorWashBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(speed: 0.5, intensity: 0.8)
                ))
            case 1:
                slots.append(BehaviorSlot(
                    behavior: ColorSplitBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(intensity: 0.7)
                ))
            default:
                slots.append(BehaviorSlot(
                    behavior: ColorWashBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(speed: 0.3, intensity: 0.8, variant: 1) // rainbow
                ))
            }

            // Movement for any group containing movers
            if groupHasMovers(group, fixtures: fixtures) {
                let pattern: Int = switch movementVariant {
                case 0: MovementPatternBehavior.Pattern.circle.rawValue
                case 1: MovementPatternBehavior.Pattern.sweep.rawValue
                default: MovementPatternBehavior.Pattern.figure8.rawValue
                }
                slots.append(BehaviorSlot(
                    behavior: MovementPatternBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(speed: 0.5, intensity: 0.6, variant: pattern)
                ))
            }
        }
    }

    // MARK: - Medium Energy

    private mutating func applyMediumEnergy(fixtures: [StageFixture], hasMovers: Bool) {
        let groupVariant = Self.pickVariant(count: 3, seed: barCounter, recent: recentGroupingVariant, salt: 100)
        Self.track(groupVariant, in: &recentGroupingVariant)

        let strategy: GroupingEngine.Strategy = switch groupVariant {
        case 0: hasMovers ? .moverPairSplit : .capabilitySplit
        case 1: .spatialSplit
        default: .capabilitySplit
        }
        groups = groupingEngine.group(fixtures: fixtures, strategy: strategy)
        slots = []

        let dimmerVariant = Self.pickVariant(count: 6, seed: barCounter, recent: recentDimmerVariant, salt: 200)
        Self.track(dimmerVariant, in: &recentDimmerVariant)

        let colorVariant = Self.pickVariant(count: 4, seed: barCounter, recent: recentColorVariant, salt: 300)
        Self.track(colorVariant, in: &recentColorVariant)

        let movementVariant = Self.pickVariant(count: 4, seed: barCounter, recent: recentMovementVariant, salt: 400)
        Self.track(movementVariant, in: &recentMovementVariant)

        let swapMoverRoles = barCounter.isMultiple(of: 2)
        var moverGroupCount = 0

        for (index, group) in groups.enumerated() {
            if group.role == .effect {
                if dimmerVariant == 5 {
                    slots.append(BehaviorSlot(
                        behavior: StrobeBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(intensity: 0.6, variant: StrobeBehavior.Mode.punchy.rawValue)
                    ))
                }
                continue
            }

            // Dimmer behavior
            let isMoverGroup = groupHasMovers(group, fixtures: fixtures)
            if isMoverGroup {
                switch dimmerVariant {
                case 0:
                    let beatOffset = Double(moverGroupCount) * 1.0
                    slots.append(BehaviorSlot(
                        behavior: BeatPulseBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(intensity: 0.8, offset: beatOffset, variant: BeatPulseBehavior.Mode.alternating.rawValue)
                    ))
                case 1:
                    slots.append(BehaviorSlot(
                        behavior: BreatheBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(speed: 0.8, intensity: 0.8)
                    ))
                case 2:
                    break // No dimmer — color wash drives brightness
                case 3:
                    slots.append(BehaviorSlot(
                        behavior: BeatPulseBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(intensity: 0.7)
                    ))
                case 4:
                    slots.append(BehaviorSlot(
                        behavior: ChaseBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(speed: 0.8, intensity: 0.7)
                    ))
                default:
                    slots.append(BehaviorSlot(
                        behavior: BreatheBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(speed: 1.5, intensity: 0.85)
                    ))
                }
            } else {
                slots.append(BehaviorSlot(
                    behavior: BeatPulseBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(intensity: 0.8)
                ))
            }

            // Color behavior
            if group.role != .effect {
                switch colorVariant {
                case 0:
                    slots.append(BehaviorSlot(
                        behavior: ColorWashBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(speed: 1.0, variant: groups.count > 1 ? 1 : 0)
                    ))
                case 1:
                    slots.append(BehaviorSlot(
                        behavior: ColorSplitBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(intensity: 0.9)
                    ))
                case 2:
                    slots.append(BehaviorSlot(
                        behavior: SpectralColorBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(speed: 0.8, intensity: 0.8)
                    ))
                default:
                    slots.append(BehaviorSlot(
                        behavior: ColorWashBehavior(),
                        groupID: group.id,
                        parameters: BehaviorParameters(speed: 0.6, intensity: 0.9)
                    ))
                }
            }

            // Occasional strobe at medium energy — movers only (blinders reserved for peaks)
            if dimmerVariant >= 4 && isMoverGroup && groupHasStrobe(group, fixtures: fixtures) {
                slots.append(BehaviorSlot(behavior: StrobeBehavior(), groupID: group.id,
                    parameters: BehaviorParameters(intensity: 0.6, variant: StrobeBehavior.Mode.punchy.rawValue)))
            }

            // Movement
            if isMoverGroup {
                let isRandomGroup = (moverGroupCount == 0) != swapMoverRoles
                switch movementVariant {
                case 0:
                    if isRandomGroup {
                        slots.append(BehaviorSlot(behavior: RandomLookBehavior(), groupID: group.id, parameters: BehaviorParameters(speed: 0.8, intensity: 0.7)))
                    } else {
                        slots.append(BehaviorSlot(behavior: PanSweepBehavior(), groupID: group.id, parameters: BehaviorParameters(speed: 0.8, intensity: 0.7, offset: Double(index) * 0.3)))
                        slots.append(BehaviorSlot(behavior: TiltBounceBehavior(), groupID: group.id, parameters: BehaviorParameters(intensity: 0.5)))
                    }
                case 1:
                    slots.append(BehaviorSlot(behavior: MovementPatternBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(speed: 0.8, intensity: 0.7, variant: MovementPatternBehavior.Pattern.figure8.rawValue)))
                case 2:
                    slots.append(BehaviorSlot(behavior: TiltSweepBehavior(), groupID: group.id, parameters: BehaviorParameters(speed: 0.8, intensity: 0.7)))
                default:
                    if isRandomGroup {
                        slots.append(BehaviorSlot(behavior: PanSweepBehavior(), groupID: group.id, parameters: BehaviorParameters(speed: 0.8, intensity: 0.7, offset: Double(index) * 0.3)))
                    } else {
                        slots.append(BehaviorSlot(behavior: RandomLookBehavior(), groupID: group.id, parameters: BehaviorParameters(speed: 0.8, intensity: 0.7)))
                    }
                }
                moverGroupCount += 1
            }
        }
    }

    // MARK: - High Energy

    private mutating func applyHighEnergy(fixtures: [StageFixture], hasMovers: Bool) {
        let groupVariant = Self.pickVariant(count: 3, seed: barCounter, recent: recentGroupingVariant, salt: 100)
        Self.track(groupVariant, in: &recentGroupingVariant)

        let strategy: GroupingEngine.Strategy = switch groupVariant {
        case 0: hasMovers ? .moverPairSplit : .capabilitySplit
        case 1: .alternating
        default: .capabilitySplit
        }
        groups = groupingEngine.group(fixtures: fixtures, strategy: strategy)
        slots = []

        let effectVariant = Self.pickVariant(count: 5, seed: barCounter, recent: recentDimmerVariant, salt: 200)
        Self.track(effectVariant, in: &recentDimmerVariant)

        let colorVariant = Self.pickVariant(count: 4, seed: barCounter, recent: recentColorVariant, salt: 300)
        Self.track(colorVariant, in: &recentColorVariant)

        let movementVariant = Self.pickVariant(count: 5, seed: barCounter, recent: recentMovementVariant, salt: 400)
        Self.track(movementVariant, in: &recentMovementVariant)

        let usePairSplit = strategy == .moverPairSplit
        var moverGroupCount = 0

        for (index, group) in groups.enumerated() {
            // Effect fixtures
            if group.role == .effect {
                switch effectVariant {
                case 0:
                    slots.append(BehaviorSlot(behavior: StrobeBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(intensity: 0.9, variant: StrobeBehavior.Mode.onsetReactive.rawValue)))
                    slots.append(BehaviorSlot(behavior: BeatPulseBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(intensity: 0.8)))
                case 1:
                    slots.append(BehaviorSlot(behavior: StrobeBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(intensity: 0.85, variant: StrobeBehavior.Mode.subdivision.rawValue)))
                    slots.append(BehaviorSlot(behavior: BeatPulseBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(intensity: 0.7)))
                case 2:
                    slots.append(BehaviorSlot(behavior: StrobeBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(intensity: 0.9, variant: StrobeBehavior.Mode.halfTime.rawValue)))
                    slots.append(BehaviorSlot(behavior: BeatPulseBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(intensity: 0.85)))
                case 3:
                    // Strobe rest — let other behaviors breathe
                    slots.append(BehaviorSlot(behavior: BeatPulseBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(intensity: 1.0)))
                default:
                    slots.append(BehaviorSlot(behavior: ChaseBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(speed: 1.5, intensity: 0.9)))
                }
                continue
            }

            // Beat pulse
            let isMoverGroupHigh = groupHasMovers(group, fixtures: fixtures)
            if isMoverGroupHigh && usePairSplit {
                let beatOffset = Double(moverGroupCount) * 1.0
                slots.append(BehaviorSlot(behavior: BeatPulseBehavior(), groupID: group.id,
                    parameters: BehaviorParameters(intensity: 1.0, offset: beatOffset, variant: BeatPulseBehavior.Mode.alternating.rawValue)))
            } else {
                slots.append(BehaviorSlot(behavior: BeatPulseBehavior(), groupID: group.id,
                    parameters: BehaviorParameters(intensity: 1.0)))
            }

            // Color
            switch colorVariant {
            case 0:
                slots.append(BehaviorSlot(behavior: SpectralColorBehavior(), groupID: group.id,
                    parameters: BehaviorParameters(intensity: 1.0)))
            case 1:
                slots.append(BehaviorSlot(behavior: ColorWashBehavior(), groupID: group.id,
                    parameters: BehaviorParameters(speed: 2.0, offset: Double(index) * 0.5, variant: 1)))
            case 2:
                slots.append(BehaviorSlot(behavior: ColorSplitBehavior(), groupID: group.id,
                    parameters: BehaviorParameters(intensity: 1.0)))
            default:
                slots.append(BehaviorSlot(behavior: ColorWashBehavior(), groupID: group.id,
                    parameters: BehaviorParameters(speed: 3.0, intensity: 1.0)))
            }

            // Strobe on all strobe-capable fixtures at high energy.
            // Movers: shutter strobe. Blinders: dimmer flash.
            if groupHasStrobe(group, fixtures: fixtures) {
                let strobeMode: Int = switch effectVariant {
                case 0: StrobeBehavior.Mode.onsetReactive.rawValue
                case 1: StrobeBehavior.Mode.subdivision.rawValue
                case 2: StrobeBehavior.Mode.halfTime.rawValue
                default: StrobeBehavior.Mode.punchy.rawValue
                }
                slots.append(BehaviorSlot(behavior: StrobeBehavior(), groupID: group.id,
                    parameters: BehaviorParameters(intensity: 0.85, variant: strobeMode)))
            }

            // Movement
            if isMoverGroupHigh {
                switch movementVariant {
                case 0:
                    if moverGroupCount == 0 {
                        slots.append(BehaviorSlot(behavior: RandomLookBehavior(), groupID: group.id,
                            parameters: BehaviorParameters(speed: 1.2, intensity: 0.9)))
                    } else {
                        slots.append(BehaviorSlot(behavior: PanSweepBehavior(), groupID: group.id,
                            parameters: BehaviorParameters(speed: 1.2, intensity: 0.8, offset: Double(index) * 0.25)))
                        slots.append(BehaviorSlot(behavior: TiltBounceBehavior(), groupID: group.id,
                            parameters: BehaviorParameters(intensity: 0.8)))
                    }
                case 1:
                    if moverGroupCount == 0 {
                        slots.append(BehaviorSlot(behavior: PanSweepBehavior(), groupID: group.id,
                            parameters: BehaviorParameters(speed: 1.2, intensity: 0.8, offset: Double(index) * 0.25)))
                        slots.append(BehaviorSlot(behavior: TiltBounceBehavior(), groupID: group.id,
                            parameters: BehaviorParameters(intensity: 0.8)))
                    } else {
                        slots.append(BehaviorSlot(behavior: RandomLookBehavior(), groupID: group.id,
                            parameters: BehaviorParameters(speed: 1.2, intensity: 0.9)))
                    }
                case 2:
                    slots.append(BehaviorSlot(behavior: TiltSweepBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(speed: 1.2, intensity: 1.0)))
                case 3:
                    slots.append(BehaviorSlot(behavior: MovementPatternBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(speed: 1.5, intensity: 1.0, offset: Double(index) * 0.25,
                            variant: MovementPatternBehavior.Pattern.ballyhoo.rawValue)))
                default:
                    slots.append(BehaviorSlot(behavior: MovementPatternBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(speed: 1.2, intensity: 0.9, variant: MovementPatternBehavior.Pattern.figure8.rawValue)))
                }
                moverGroupCount += 1
            }
        }
    }

    // MARK: - Building

    private mutating func applyBuilding(fixtures: [StageFixture], hasMovers: Bool) {
        groups = groupingEngine.group(fixtures: fixtures, strategy: .capabilitySplit)
        slots = []

        let effectVariant = Self.pickVariant(count: 4, seed: barCounter, recent: recentDimmerVariant, salt: 200)
        Self.track(effectVariant, in: &recentDimmerVariant)

        let movementVariant = Self.pickVariant(count: 4, seed: barCounter, recent: recentMovementVariant, salt: 300)
        Self.track(movementVariant, in: &recentMovementVariant)

        for group in groups {
            if group.role == .effect {
                switch effectVariant {
                case 0:
                    slots.append(BehaviorSlot(behavior: BeatPulseBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(speed: 1.2, intensity: 0.9)))
                case 1:
                    slots.append(BehaviorSlot(behavior: StrobeBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(speed: 1.3, intensity: 0.85, variant: StrobeBehavior.Mode.punchy.rawValue)))
                    slots.append(BehaviorSlot(behavior: BeatPulseBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(speed: 1.2, intensity: 0.8)))
                case 2:
                    slots.append(BehaviorSlot(behavior: StrobeBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(intensity: 0.8, variant: StrobeBehavior.Mode.subdivision.rawValue)))
                    slots.append(BehaviorSlot(behavior: BeatPulseBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(speed: 1.2, intensity: 0.7)))
                default:
                    slots.append(BehaviorSlot(behavior: ChaseBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(speed: 1.2, intensity: 0.85)))
                }
            } else {
                slots.append(BehaviorSlot(behavior: BeatPulseBehavior(), groupID: group.id,
                    parameters: BehaviorParameters(speed: 1.2, intensity: 0.9)))
                slots.append(BehaviorSlot(behavior: ColorWashBehavior(), groupID: group.id,
                    parameters: BehaviorParameters(speed: 2.5, intensity: 1.0)))
            }

            slots.append(BehaviorSlot(behavior: BlackoutAccentBehavior(), groupID: group.id))

            // Strobe on movers during build (blinders reserved for peak)
            if groupHasMovers(group, fixtures: fixtures) {
                if groupHasStrobe(group, fixtures: fixtures) {
                    slots.append(BehaviorSlot(behavior: StrobeBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(intensity: 0.8, variant: StrobeBehavior.Mode.punchy.rawValue)))
                }

                switch movementVariant {
                case 0:
                    slots.append(BehaviorSlot(behavior: MovementPatternBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(speed: 1.5, intensity: 0.9, variant: MovementPatternBehavior.Pattern.figure8.rawValue)))
                case 1:
                    slots.append(BehaviorSlot(behavior: TiltSweepBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(speed: 1.5, intensity: 0.9)))
                case 2:
                    slots.append(BehaviorSlot(behavior: MovementPatternBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(speed: 1.5, intensity: 0.9, variant: MovementPatternBehavior.Pattern.ballyhoo.rawValue)))
                default:
                    slots.append(BehaviorSlot(behavior: PanSweepBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(speed: 1.5, intensity: 0.8)))
                    slots.append(BehaviorSlot(behavior: TiltBounceBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(intensity: 0.7)))
                }
            }
        }
    }

    // MARK: - Peak Drop

    private mutating func applyPeakDrop(fixtures: [StageFixture], hasMovers: Bool) {
        let groupVariant = Self.pickVariant(count: 3, seed: barCounter, recent: recentGroupingVariant, salt: 100)
        Self.track(groupVariant, in: &recentGroupingVariant)

        let strategy: GroupingEngine.Strategy = switch groupVariant {
        case 0: hasMovers ? .moverPairSplit : .capabilitySplit
        case 1: hasMovers ? .soloBackground : .capabilitySplit
        default: .alternating
        }
        groups = groupingEngine.group(fixtures: fixtures, strategy: strategy)
        slots = []

        let dimmerVariant = Self.pickVariant(count: 3, seed: barCounter, recent: recentDimmerVariant, salt: 200)
        Self.track(dimmerVariant, in: &recentDimmerVariant)

        let effectVariant = Self.pickVariant(count: 3, seed: barCounter, recent: [], salt: 500)
        let swapMoverRoles = !barCounter.isMultiple(of: 2)
        var moverGroupCount = 0

        for (index, group) in groups.enumerated() {
            if group.role == .effect {
                switch effectVariant {
                case 0:
                    slots.append(BehaviorSlot(behavior: StrobeBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(intensity: 1.0, variant: StrobeBehavior.Mode.onsetReactive.rawValue)))
                    slots.append(BehaviorSlot(behavior: BeatPulseBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(intensity: 1.0)))
                case 1:
                    slots.append(BehaviorSlot(behavior: StrobeBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(intensity: 1.0, variant: StrobeBehavior.Mode.subdivision.rawValue)))
                    slots.append(BehaviorSlot(behavior: BeatPulseBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(intensity: 0.9)))
                default:
                    slots.append(BehaviorSlot(behavior: StrobeBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(intensity: 1.0, variant: StrobeBehavior.Mode.halfTime.rawValue)))
                    slots.append(BehaviorSlot(behavior: BeatPulseBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(intensity: 1.0)))
                }
                continue
            }

            // Dimmer: chase or beat pulse
            switch dimmerVariant {
            case 0:
                slots.append(BehaviorSlot(behavior: ChaseBehavior(), groupID: group.id,
                    parameters: BehaviorParameters(speed: 1.5, intensity: 1.0)))
            case 1:
                slots.append(BehaviorSlot(behavior: BeatPulseBehavior(), groupID: group.id,
                    parameters: BehaviorParameters(intensity: 1.0)))
            default:
                slots.append(BehaviorSlot(behavior: BeatPulseBehavior(), groupID: group.id,
                    parameters: BehaviorParameters(intensity: 1.0, variant: BeatPulseBehavior.Mode.alternating.rawValue)))
            }

            slots.append(BehaviorSlot(behavior: SpectralColorBehavior(), groupID: group.id,
                parameters: BehaviorParameters(intensity: 1.0)))

            // Strobe on all strobe-capable fixtures at peak drop.
            // Movers: shutter strobe. Blinders: dimmer flash (hardware .strobe snapped away by scene).
            if groupHasStrobe(group, fixtures: fixtures) {
                slots.append(BehaviorSlot(behavior: StrobeBehavior(), groupID: group.id,
                    parameters: BehaviorParameters(intensity: 1.0, variant: StrobeBehavior.Mode.onsetReactive.rawValue)))
            }

            if groupHasMovers(group, fixtures: fixtures) {
                let isBallyhooGroup = (moverGroupCount == 0) != swapMoverRoles
                if isBallyhooGroup {
                    slots.append(BehaviorSlot(behavior: MovementPatternBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(speed: 2.0, intensity: 1.0, offset: Double(index) * 0.5,
                            variant: MovementPatternBehavior.Pattern.ballyhoo.rawValue)))
                } else {
                    slots.append(BehaviorSlot(behavior: RandomLookBehavior(), groupID: group.id,
                        parameters: BehaviorParameters(speed: 1.5, intensity: 1.0)))
                }
                moverGroupCount += 1
            }
        }
    }

    // MARK: - Declining

    private mutating func applyDeclining(fixtures: [StageFixture], hasMovers: Bool) {
        let colorVariant = Self.pickVariant(count: 3, seed: barCounter, recent: recentColorVariant, salt: 200)
        Self.track(colorVariant, in: &recentColorVariant)

        groups = groupingEngine.group(fixtures: fixtures, strategy: .capabilitySplit)
        slots = []

        for group in groups {
            if group.role == .effect { continue }

            slots.append(BehaviorSlot(
                behavior: BreatheBehavior(),
                groupID: group.id,
                parameters: BehaviorParameters(speed: 0.6, intensity: 0.7)
            ))

            switch colorVariant {
            case 0:
                slots.append(BehaviorSlot(behavior: ColorWashBehavior(), groupID: group.id,
                    parameters: BehaviorParameters(speed: 0.6, intensity: 0.8)))
            case 1:
                slots.append(BehaviorSlot(behavior: ColorSplitBehavior(), groupID: group.id,
                    parameters: BehaviorParameters(intensity: 0.7)))
            default:
                slots.append(BehaviorSlot(behavior: ColorWashBehavior(), groupID: group.id,
                    parameters: BehaviorParameters(speed: 0.3, intensity: 0.8, variant: 1)))
            }

            if groupHasMovers(group, fixtures: fixtures) {
                slots.append(BehaviorSlot(
                    behavior: PanSweepBehavior(),
                    groupID: group.id,
                    parameters: BehaviorParameters(speed: 0.5, intensity: 0.6)
                ))
            }
        }
    }
}

// MARK: - Helpers

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
