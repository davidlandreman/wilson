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

        // Reactivity varies by scenario: low energy shows more base, high energy more behavior
        let reactivity: Double = switch scenario {
        case .lowEnergy, .declining: 0.5
        case .mediumEnergy: 0.6
        case .building: 0.65
        case .highEnergy: 0.7
        case .peakDrop: 0.8
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

    func build(
        fixtures: [StageFixture],
        palette: ResolvedPalette,
        mood: MoodState,
        seed: Int
    ) -> [UUID: [FixtureAttribute: Double]] {
        var result: [UUID: [FixtureAttribute: Double]] = [:]

        switch self {
        case .backlightWash:
            // Rear fixtures (high trussSlot) bright in primary, front dim in secondary
            let maxSlot = fixtures.map(\.trussSlot).max() ?? 0
            let midSlot = maxSlot / 2
            for fixture in fixtures {
                let isRear = fixture.trussSlot > midSlot
                let color = isRear ? palette.primary() : palette.secondary()
                let dimmer = isRear ? 0.85 : 0.35
                result[fixture.id] = colorAttrs(color, dimmer: dimmer, fixture: fixture)
            }

        case .warmFrontCoolBack:
            let midY = 0.5
            for fixture in fixtures {
                let isFront = fixture.position.y < midY
                let color = isFront ? palette.primary() : palette.accent()
                let dimmer = isFront ? 0.75 : 0.65
                result[fixture.id] = colorAttrs(color, dimmer: dimmer, fixture: fixture)
            }

        case .singleColorSaturate:
            // One deep color for everything — which color rotates with seed
            let colorIndex = LookGenerator.deterministicHash(seed) % max(palette.colors.count, 1)
            let color = palette.colorForIndex(colorIndex)
            for fixture in fixtures {
                result[fixture.id] = colorAttrs(color, dimmer: 0.9, fixture: fixture)
            }

        case .colorSplitLeftRight:
            let midX = 0.5
            for fixture in fixtures {
                let isLeft = fixture.position.x < midX
                let color = isLeft ? palette.primary() : palette.secondary()
                result[fixture.id] = colorAttrs(color, dimmer: 0.8, fixture: fixture)
            }

        case .moodyLow:
            // Deep colors, low intensity
            for (i, fixture) in fixtures.enumerated() {
                let color = palette.colorForIndex(i)
                var attrs = colorAttrs(color, dimmer: 0.3 + Double(i % 3) * 0.1, fixture: fixture)
                // Movers point at floor
                if fixture.attributes.contains(.tilt) {
                    attrs[.tilt] = 0.2
                }
                result[fixture.id] = attrs
            }

        case .highContrast:
            // Alternating bright/dark by trussSlot
            for fixture in fixtures {
                let isBright = fixture.trussSlot.isMultiple(of: 2)
                let color = isBright ? palette.primary() : palette.accent()
                let dimmer = isBright ? 1.0 : 0.15
                result[fixture.id] = colorAttrs(color, dimmer: dimmer, fixture: fixture)
            }

        case .spotlightFocus:
            // Center fixture bright, others subtle
            let sorted = fixtures.sorted { abs($0.position.x - 0.5) < abs($1.position.x - 0.5) }
            for (i, fixture) in sorted.enumerated() {
                let isFocus = i == 0
                let color = isFocus ? palette.primary() : palette.secondary()
                let dimmer = isFocus ? 1.0 : 0.2
                result[fixture.id] = colorAttrs(color, dimmer: dimmer, fixture: fixture)
            }

        case .evenWash:
            // Clean unified look — all same color and intensity
            let color = palette.primary()
            for fixture in fixtures {
                result[fixture.id] = colorAttrs(color, dimmer: 0.75, fixture: fixture)
            }

        case .complementarySplit:
            // Movers get primary, color fixtures get secondary
            for fixture in fixtures {
                let hasMover = fixture.attributes.contains(.pan) || fixture.attributes.contains(.tilt)
                let color = hasMover ? palette.primary() : palette.secondary()
                result[fixture.id] = colorAttrs(color, dimmer: 0.8, fixture: fixture)
            }

        case .triColorSpread:
            // Distribute primary/secondary/accent across positions
            for (i, fixture) in fixtures.enumerated() {
                let colorIndex = i % 3
                let color: LightColor = switch colorIndex {
                case 0: palette.primary()
                case 1: palette.secondary()
                default: palette.accent()
                }
                result[fixture.id] = colorAttrs(color, dimmer: 0.85, fixture: fixture)
            }
        }

        return result
    }

    /// Build attribute dictionary from a LightColor, applying only attributes the fixture supports.
    private func colorAttrs(
        _ color: LightColor,
        dimmer: Double,
        fixture: StageFixture
    ) -> [FixtureAttribute: Double] {
        var attrs: [FixtureAttribute: Double] = [:]
        attrs[.dimmer] = dimmer
        if fixture.attributes.contains(.red) { attrs[.red] = color.red }
        if fixture.attributes.contains(.green) { attrs[.green] = color.green }
        if fixture.attributes.contains(.blue) { attrs[.blue] = color.blue }
        if fixture.attributes.contains(.white) { attrs[.white] = color.white }
        return attrs
    }
}
