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
    /// Blinder pattern set — independent values for each pattern channel.
    /// Returns (rgbPattern, wPattern, rgbwPattern, bgColor, bgLight, speed) or all nil.
    struct BlinderPatterns {
        var rgbPattern: Double?   // .custom — RGB zone animation
        var wPattern: Double?     // .prism — white bar animation
        var rgbwPattern: Double?  // .focus — combined RGBW effect
        var bgColor: Double?      // .zoom — background color
        var bgLight: Double?      // .amber — background intensity
        var speed: Double?        // .speed — shared velocity
    }

    private func blinderPatternsForMood(_ mood: MoodState, seed: Int) -> BlinderPatterns {
        var p = BlinderPatterns()

        // Low energy: no patterns, solid color only
        guard mood.intensity > 0.4 else { return p }

        let h1 = LookGenerator.deterministicHash(seed &+ 99)
        let h2 = LookGenerator.deterministicHash(seed &+ 137)
        let h3 = LookGenerator.deterministicHash(seed &+ 211)

        switch self {
        case .moodyLow, .backlightWash, .evenWash:
            // Subtle: just white bar partial fill, no RGB pattern
            if mood.intensity > 0.5 {
                p.wPattern = Double(5 + h1 % 25) / 255.0  // Subtle W animation
                p.speed = 0.15 + mood.intensity * 0.2
            }

        case .warmFrontCoolBack, .spotlightFocus, .complementarySplit:
            // Moderate: RGB pattern + independent W pattern
            if mood.intensity > 0.5 {
                p.rgbPattern = Double(10 + h1 % 40) / 255.0
                p.wPattern = Double(5 + h2 % 30) / 255.0
                p.speed = 0.2 + mood.intensity * 0.4
            }

        case .singleColorSaturate, .colorSplitLeftRight:
            // Active: all layers with different values
            guard mood.intensity > 0.55 else { return p }
            p.rgbPattern = Double(20 + h1 % 50) / 255.0
            p.wPattern = Double(10 + h2 % 35) / 255.0
            p.rgbwPattern = Double(15 + h3 % 40) / 255.0
            p.speed = 0.3 + mood.intensity * 0.4

        case .highContrast, .triColorSpread:
            // Peak: full layered effects + background
            guard mood.intensity > 0.5 else { return p }
            p.rgbPattern = Double(30 + h1 % 80) / 255.0
            p.wPattern = Double(15 + h2 % 50) / 255.0
            p.rgbwPattern = Double(20 + h3 % 60) / 255.0
            p.bgColor = Double(h1 % 128) / 255.0  // Background color wash
            p.bgLight = Double(20 + h2 % 40) / 255.0
            p.speed = 0.3 + mood.excitement * 0.5
        }

        return p
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
        let bp = blinderPatternsForMood(mood, seed: seed)
        let strobe = strobeForMood(mood)

        switch self {
        case .backlightWash:
            let maxSlot = fixtures.map(\.trussSlot).max() ?? 0
            let midSlot = maxSlot / 2
            for fixture in fixtures {
                let isRear = fixture.trussSlot > midSlot
                let color = isRear ? palette.primary() : palette.secondary()
                let dimmer = isRear ? 0.85 : 0.35
                result[fixture.id] = colorAttrs(color, dimmer: dimmer, fixture: fixture, gobo: gobo, blinderPatterns: bp, strobe: strobe)
            }

        case .warmFrontCoolBack:
            let midY = 0.5
            for fixture in fixtures {
                let isFront = fixture.position.y < midY
                let color = isFront ? palette.primary() : palette.accent()
                let dimmer = isFront ? 0.75 : 0.65
                result[fixture.id] = colorAttrs(color, dimmer: dimmer, fixture: fixture, gobo: gobo, blinderPatterns: bp, strobe: strobe)
            }

        case .singleColorSaturate:
            let colorIndex = LookGenerator.deterministicHash(seed) % max(palette.colors.count, 1)
            let color = palette.colorForIndex(colorIndex)
            for fixture in fixtures {
                result[fixture.id] = colorAttrs(color, dimmer: 0.9, fixture: fixture, gobo: gobo, blinderPatterns: bp, strobe: strobe)
            }

        case .colorSplitLeftRight:
            let midX = 0.5
            for fixture in fixtures {
                let isLeft = fixture.position.x < midX
                let color = isLeft ? palette.primary() : palette.secondary()
                result[fixture.id] = colorAttrs(color, dimmer: 0.8, fixture: fixture, gobo: gobo, blinderPatterns: bp, strobe: strobe)
            }

        case .moodyLow:
            for (i, fixture) in fixtures.enumerated() {
                let color = palette.colorForIndex(i)
                var attrs = colorAttrs(color, dimmer: 0.3 + Double(i % 3) * 0.1, fixture: fixture, gobo: gobo, blinderPatterns: bp)
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
                result[fixture.id] = colorAttrs(color, dimmer: dimmer, fixture: fixture, gobo: gobo, blinderPatterns: bp, strobe: strobe)
            }

        case .spotlightFocus:
            let sorted = fixtures.sorted { abs($0.position.x - 0.5) < abs($1.position.x - 0.5) }
            for (i, fixture) in sorted.enumerated() {
                let isFocus = i == 0
                let color = isFocus ? palette.primary() : palette.secondary()
                let dimmer = isFocus ? 1.0 : 0.2
                // Focus fixture gets gobo, others stay open
                let fixtureGobo = isFocus ? gobo : FixtureTranslator.GoboIntent.open
                result[fixture.id] = colorAttrs(color, dimmer: dimmer, fixture: fixture, gobo: fixtureGobo, blinderPatterns: bp, strobe: strobe)
            }

        case .evenWash:
            let color = palette.primary()
            for fixture in fixtures {
                result[fixture.id] = colorAttrs(color, dimmer: 0.75, fixture: fixture, gobo: gobo, blinderPatterns: bp, strobe: strobe)
            }

        case .complementarySplit:
            for fixture in fixtures {
                let hasMover = fixture.attributes.contains(.pan) || fixture.attributes.contains(.tilt)
                let color = hasMover ? palette.primary() : palette.secondary()
                result[fixture.id] = colorAttrs(color, dimmer: 0.8, fixture: fixture, gobo: gobo, blinderPatterns: bp, strobe: strobe)
            }

        case .triColorSpread:
            for (i, fixture) in fixtures.enumerated() {
                let colorIndex = i % 3
                let color: LightColor = switch colorIndex {
                case 0: palette.primary()
                case 1: palette.secondary()
                default: palette.accent()
                }
                result[fixture.id] = colorAttrs(color, dimmer: 0.85, fixture: fixture, gobo: gobo, blinderPatterns: bp, strobe: strobe)
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
        blinderPatterns: BlinderPatterns? = nil,
        strobe: Double? = nil
    ) -> [FixtureAttribute: Double] {
        var attrs: [FixtureAttribute: Double] = [:]

        // Blinder-class fixtures (strobe channel, no pan/tilt): reserved for peaks.
        let isBlinder = fixture.attributes.contains(.strobe) && !fixture.attributes.contains(.pan)
        if isBlinder {
            attrs[.dimmer] = dimmer * 0.08 // Very dim base — behaviors drive peaks.
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
        // Blinder pattern channels — each independent
        if let bp = blinderPatterns {
            if let v = bp.rgbPattern, fixture.attributes.contains(.custom) { attrs[.custom] = v }
            if let v = bp.wPattern, fixture.attributes.contains(.prism) { attrs[.prism] = v }
            if let v = bp.rgbwPattern, fixture.attributes.contains(.focus) { attrs[.focus] = v }
            if let v = bp.bgColor, fixture.attributes.contains(.zoom) { attrs[.zoom] = v }
            if let v = bp.bgLight, fixture.attributes.contains(.amber) { attrs[.amber] = v }
            if let v = bp.speed, fixture.attributes.contains(.speed) { attrs[.speed] = v }
        }
        // Hardware strobe speed (non-movers only)
        if let strobe, fixture.attributes.contains(.strobe),
           !fixture.attributes.contains(.pan) {
            attrs[.strobe] = strobe
        }
        return attrs
    }
}
