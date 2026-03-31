import Foundation

/// Generates algorithmic base looks from palette and mood, producing SceneSnapshots
/// that compete with user-created scenes in the SceneLibrary scoring pool.
struct LookGenerator: Sendable {

    func generate(
        fixtures: [StageFixture],
        scenario: Choreographer.Scenario,
        mood: MoodState,
        palette: ResolvedPalette,
        seed: Int
    ) -> SceneSnapshot {
        guard !fixtures.isEmpty else {
            return emptySnapshot(name: "Gen: Empty")
        }

        // Pick a template weighted by scenario, avoiding recent repeat via seed
        let template = pickTemplate(scenario: scenario, mood: mood, seed: seed)
        let attrs = template.build(fixtures: fixtures, palette: palette, mood: mood, seed: seed)

        // Reactivity: how much behavior output overrides the scene base.
        // Higher = behaviors dominate, allowing true blackout and dynamic range.
        let reactivity: Double = switch scenario {
        case .lowEnergy, .declining: 0.7
        case .mediumEnergy: 0.8
        case .building: 0.85
        case .highEnergy: 0.95
        case .peakDrop: 1.0
        }

        return SceneSnapshot(
            name: "Gen: \(template.name)",
            reactivity: reactivity,
            energyLevel: energyLevel(for: scenario),
            mood: sceneMood(for: mood),
            transitionStyle: .crossfade,
            transitionDuration: 2.0,
            grandMaster: 1.0,
            fixtureAttributes: attrs,
            isGenerated: true
        )
    }

    // MARK: - Template Selection

    private func pickTemplate(
        scenario: Choreographer.Scenario,
        mood: MoodState,
        seed: Int
    ) -> LookTemplate {
        let weights = templateWeights(for: scenario)
        let templates = LookTemplate.allCases

        // Deterministic weighted selection using seed
        let hash = Self.deterministicHash(seed)
        let totalWeight = weights.reduce(0, +)
        let target = Double(hash % 1000) / 1000.0 * totalWeight

        var accumulated = 0.0
        for (i, weight) in weights.enumerated() {
            accumulated += weight
            if target < accumulated {
                return templates[i]
            }
        }
        return templates.last!
    }

    private func templateWeights(for scenario: Choreographer.Scenario) -> [Double] {
        // Order matches LookTemplate.allCases
        // [backlight, warmCool, saturate, splitLR, moody, contrast, spotlight, even, complement, triColor]
        switch scenario {
        case .lowEnergy:
            return [1.2, 0.8, 0.6, 0.4, 1.5, 0.2, 1.0, 0.8, 0.6, 0.3]
        case .mediumEnergy:
            return [0.8, 1.0, 0.8, 1.0, 0.5, 0.8, 0.7, 1.0, 1.0, 0.8]
        case .highEnergy:
            return [0.5, 0.6, 1.0, 1.0, 0.2, 1.5, 0.5, 0.6, 0.8, 1.2]
        case .building:
            return [0.8, 0.8, 1.2, 0.6, 0.4, 1.0, 0.6, 1.0, 0.8, 0.8]
        case .peakDrop:
            return [0.3, 0.4, 1.2, 1.0, 0.1, 1.5, 0.4, 0.5, 1.0, 1.3]
        case .declining:
            return [1.2, 1.0, 0.5, 0.4, 1.5, 0.1, 1.0, 0.8, 0.6, 0.2]
        }
    }

    // MARK: - Helpers

    private func energyLevel(for scenario: Choreographer.Scenario) -> SceneEnergyLevel {
        switch scenario {
        case .lowEnergy, .declining: .low
        case .mediumEnergy, .building: .medium
        case .highEnergy, .peakDrop: .high
        }
    }

    private func sceneMood(for mood: MoodState) -> SceneMood {
        if mood.excitement < 0.3 && mood.chaos < 0.3 { return .calm }
        if mood.excitement > 0.6 && mood.chaos > 0.5 { return .intense }
        if mood.valence > 0.6 { return .uplifting }
        if mood.valence < 0.35 { return .dark }
        return .any
    }

    private func emptySnapshot(name: String) -> SceneSnapshot {
        SceneSnapshot(
            name: name, reactivity: 1.0, energyLevel: .any, mood: .any,
            transitionStyle: .snap, transitionDuration: 0, grandMaster: 1.0,
            fixtureAttributes: [:], isGenerated: true
        )
    }

    static func deterministicHash(_ seed: Int) -> Int {
        // Simple but effective hash for deterministic pseudo-randomness
        var h = seed &* 2654435761
        h ^= h >> 16
        h &*= 2246822519
        h ^= h >> 13
        return abs(h)
    }
}

// MARK: - Look Templates

private enum LookTemplate: CaseIterable, Sendable {
    case backlightWash
    case warmFrontCoolBack
    case singleColorSaturate
    case colorSplitLeftRight
    case moodyLow
    case highContrast
    case spotlightFocus
    case evenWash
    case complementarySplit
    case triColorSpread

    var name: String {
        switch self {
        case .backlightWash: "Backlight Wash"
        case .warmFrontCoolBack: "Warm/Cool Split"
        case .singleColorSaturate: "Saturated Wash"
        case .colorSplitLeftRight: "L/R Color Split"
        case .moodyLow: "Moody Low"
        case .highContrast: "High Contrast"
        case .spotlightFocus: "Spotlight"
        case .evenWash: "Even Wash"
        case .complementarySplit: "Complementary"
        case .triColorSpread: "Tri-Color Spread"
        }
    }

    /// Gobo intent for this template based on mood energy.
    private func goboForMood(_ mood: MoodState, seed: Int) -> Double {
        typealias G = FixtureTranslator.GoboIntent
        let hash = LookGenerator.deterministicHash(seed &+ 42)

        switch self {
        // Low-key looks: mostly open or subtle
        case .backlightWash, .evenWash, .warmFrontCoolBack:
            return hash % 3 == 0 ? G.subtle : G.open

        // Moody: always use a gobo for texture
        case .moodyLow:
            return [G.subtle, G.geometric, G.dynamic][hash % 3]

        // Medium-energy looks: introduce gobos
        case .singleColorSaturate, .colorSplitLeftRight, .complementarySplit:
            return mood.intensity > 0.4
                ? [G.open, G.subtle, G.geometric][hash % 3]
                : G.open

        // High-energy / dramatic looks: more dynamic gobos
        case .highContrast, .triColorSpread:
            return [G.geometric, G.dynamic, G.complex][hash % 3]

        // Spotlight: use a gobo for the focused fixture
        case .spotlightFocus:
            return G.geometric
        }
    }

    /// Pattern intensity for this template. 0=static, higher=more active.
    private func patternForMood(_ mood: MoodState, seed: Int) -> Double? {
        // Patterns on the Betopper are chase/flash effects — use sparingly.
        // Most of the time the fixture should show solid color, not animated patterns.
        guard mood.intensity > 0.6 else { return nil }

        let hash = LookGenerator.deterministicHash(seed &+ 99)
        switch self {
        case .highContrast, .triColorSpread:
            return Double(30 + hash % 80) / 255.0 // Active patterns at peak
        case .singleColorSaturate:
            return mood.intensity > 0.7 ? Double(20 + hash % 40) / 255.0 : nil
        default:
            return nil // Most templates: solid color, no patterns
        }
    }

    /// Speed for pattern effects. Scales with mood energy.
    private func speedForMood(_ mood: MoodState) -> Double? {
        guard mood.intensity > 0.3 else { return nil }
        return 0.2 + mood.intensity * 0.6 // 0.2–0.8 range
    }

    /// Hardware strobe speed for blinder-class fixtures.
    /// Returns nil — blinders use dimmer-based flashing (via StrobeBehavior) instead
    /// of the hardware strobe channel. Dimmer flash = brief ON in darkness (dramatic).
    /// Hardware strobe = brief OFF in light (wrong feel for blinders).
    private func strobeForMood(_ mood: MoodState) -> Double? {
        nil
    }

    func build(
        fixtures: [StageFixture],
        palette: ResolvedPalette,
        mood: MoodState,
        seed: Int
    ) -> [UUID: [FixtureAttribute: Double]] {
        var result: [UUID: [FixtureAttribute: Double]] = [:]
        let gobo = goboForMood(mood, seed: seed)
        let pattern = patternForMood(mood, seed: seed)
        let speed = speedForMood(mood)
        let strobe = strobeForMood(mood)

        switch self {
        case .backlightWash:
            let maxSlot = fixtures.map(\.trussSlot).max() ?? 0
            let midSlot = maxSlot / 2
            for fixture in fixtures {
                let isRear = fixture.trussSlot > midSlot
                let color = isRear ? palette.primary() : palette.secondary()
                let dimmer = isRear ? 0.85 : 0.35
                result[fixture.id] = colorAttrs(color, dimmer: dimmer, fixture: fixture, gobo: gobo, pattern: pattern, speed: speed, strobe: strobe)
            }

        case .warmFrontCoolBack:
            let midY = 0.5
            for fixture in fixtures {
                let isFront = fixture.position.y < midY
                let color = isFront ? palette.primary() : palette.accent()
                let dimmer = isFront ? 0.75 : 0.65
                result[fixture.id] = colorAttrs(color, dimmer: dimmer, fixture: fixture, gobo: gobo, pattern: pattern, speed: speed, strobe: strobe)
            }

        case .singleColorSaturate:
            let colorIndex = LookGenerator.deterministicHash(seed) % max(palette.colors.count, 1)
            let color = palette.colorForIndex(colorIndex)
            for fixture in fixtures {
                result[fixture.id] = colorAttrs(color, dimmer: 0.9, fixture: fixture, gobo: gobo, pattern: pattern, speed: speed, strobe: strobe)
            }

        case .colorSplitLeftRight:
            let midX = 0.5
            for fixture in fixtures {
                let isLeft = fixture.position.x < midX
                let color = isLeft ? palette.primary() : palette.secondary()
                result[fixture.id] = colorAttrs(color, dimmer: 0.8, fixture: fixture, gobo: gobo, pattern: pattern, speed: speed, strobe: strobe)
            }

        case .moodyLow:
            for (i, fixture) in fixtures.enumerated() {
                let color = palette.colorForIndex(i)
                var attrs = colorAttrs(color, dimmer: 0.3 + Double(i % 3) * 0.1, fixture: fixture, gobo: gobo)
                if fixture.attributes.contains(.tilt) {
                    attrs[.tilt] = 0.2
                }
                result[fixture.id] = attrs
            }

        case .highContrast:
            for fixture in fixtures {
                let isBright = fixture.trussSlot.isMultiple(of: 2)
                let color = isBright ? palette.primary() : palette.accent()
                let dimmer = isBright ? 1.0 : 0.15
                result[fixture.id] = colorAttrs(color, dimmer: dimmer, fixture: fixture, gobo: gobo, pattern: pattern, speed: speed, strobe: strobe)
            }

        case .spotlightFocus:
            let sorted = fixtures.sorted { abs($0.position.x - 0.5) < abs($1.position.x - 0.5) }
            for (i, fixture) in sorted.enumerated() {
                let isFocus = i == 0
                let color = isFocus ? palette.primary() : palette.secondary()
                let dimmer = isFocus ? 1.0 : 0.2
                // Focus fixture gets gobo, others stay open
                let fixtureGobo = isFocus ? gobo : FixtureTranslator.GoboIntent.open
                result[fixture.id] = colorAttrs(color, dimmer: dimmer, fixture: fixture, gobo: fixtureGobo, pattern: pattern, speed: speed, strobe: strobe)
            }

        case .evenWash:
            let color = palette.primary()
            for fixture in fixtures {
                result[fixture.id] = colorAttrs(color, dimmer: 0.75, fixture: fixture, gobo: gobo, pattern: pattern, speed: speed, strobe: strobe)
            }

        case .complementarySplit:
            for fixture in fixtures {
                let hasMover = fixture.attributes.contains(.pan) || fixture.attributes.contains(.tilt)
                let color = hasMover ? palette.primary() : palette.secondary()
                result[fixture.id] = colorAttrs(color, dimmer: 0.8, fixture: fixture, gobo: gobo, pattern: pattern, speed: speed, strobe: strobe)
            }

        case .triColorSpread:
            for (i, fixture) in fixtures.enumerated() {
                let colorIndex = i % 3
                let color: LightColor = switch colorIndex {
                case 0: palette.primary()
                case 1: palette.secondary()
                default: palette.accent()
                }
                result[fixture.id] = colorAttrs(color, dimmer: 0.85, fixture: fixture, gobo: gobo, pattern: pattern, speed: speed, strobe: strobe)
            }
        }

        return result
    }

    /// Build attribute dictionary from a LightColor.
    /// Writes RGB intent for all color-capable fixtures (RGB or color wheel).
    /// Optionally includes gobo, pattern, and speed intents.
    private func colorAttrs(
        _ color: LightColor,
        dimmer: Double,
        fixture: StageFixture,
        gobo: Double? = nil,
        pattern: Double? = nil,
        speed: Double? = nil,
        strobe: Double? = nil
    ) -> [FixtureAttribute: Double] {
        var attrs: [FixtureAttribute: Double] = [:]

        // Blinder-class fixtures (strobe channel, no pan/tilt): reserved for peaks.
        // Off at low energy, barely on at medium, moderate at high.
        let isBlinder = fixture.attributes.contains(.strobe) && !fixture.attributes.contains(.pan)
        if isBlinder {
            attrs[.dimmer] = dimmer * 0.08 // Very dim base — ~DMX 20 max. Behaviors drive peaks.
        } else {
            attrs[.dimmer] = dimmer
        }
        let hasColor = fixture.attributes.contains(.red) || fixture.attributes.contains(.colorWheel)
        if hasColor {
            attrs[.red] = color.red
            attrs[.green] = color.green
            attrs[.blue] = color.blue
            attrs[.white] = color.white
        }
        if let gobo, fixture.attributes.contains(.gobo) {
            attrs[.gobo] = gobo
        }
        if let pattern, fixture.attributes.contains(.custom) {
            attrs[.custom] = pattern
        }
        if let speed, fixture.attributes.contains(.speed) {
            attrs[.speed] = speed
        }
        // Hardware strobe speed: sustained value for fixtures with strobe channels.
        // Only for non-mover fixtures (movers use shutter semantics instead).
        if let strobe, fixture.attributes.contains(.strobe),
           !fixture.attributes.contains(.pan) {
            attrs[.strobe] = strobe
        }
        return attrs
    }
}
