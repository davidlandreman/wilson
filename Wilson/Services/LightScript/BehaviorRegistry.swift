import Foundation

/// Maps string identifiers from light script files to concrete behavior and strategy instances.
enum BehaviorRegistry {

    /// All known behavior IDs mapped to their factory.
    static func behavior(for id: String) -> (any Behavior)? {
        switch id {
        case BeatPulseBehavior.id: BeatPulseBehavior()
        case BreatheBehavior.id: BreatheBehavior()
        case ChaseBehavior.id: ChaseBehavior()
        case ColorWashBehavior.id: ColorWashBehavior()
        case ColorSplitBehavior.id: ColorSplitBehavior()
        case SpectralColorBehavior.id: SpectralColorBehavior()
        case PanSweepBehavior.id: PanSweepBehavior()
        case TiltBounceBehavior.id: TiltBounceBehavior()
        case TiltSweepBehavior.id: TiltSweepBehavior()
        case MovementPatternBehavior.id: MovementPatternBehavior()
        case RandomLookBehavior.id: RandomLookBehavior()
        case StrobeBehavior.id: StrobeBehavior()
        case BlackoutAccentBehavior.id: BlackoutAccentBehavior()
        default: nil
        }
    }

    /// Maps grouping strategy names from scripts to GroupingEngine.Strategy values.
    static func groupingStrategy(for name: String) -> GroupingEngine.Strategy? {
        switch name {
        case "allUnison": .allUnison
        case "capabilitySplit": .capabilitySplit
        case "moverPairSplit": .moverPairSplit
        case "spatialSplit": .spatialSplit
        case "alternating": .alternating
        case "soloBackground": .soloBackground
        default: nil
        }
    }

    /// Maps group role names from scripts to FixtureGroup.GroupRole values.
    static func groupRole(for name: String) -> FixtureGroup.GroupRole? {
        switch name {
        case "primary": .primary
        case "accent": .accent
        case "movement": .movement
        case "effect": .effect
        case "all": .all
        default: nil
        }
    }
}
