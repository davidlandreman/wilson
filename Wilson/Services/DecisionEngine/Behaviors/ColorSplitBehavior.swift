import Foundation

/// Assigns different palette colors to different fixtures simultaneously.
/// Creates intentional color contrast using complementary palette relationships.
/// Fixtures are assigned colors based on their index within the group.
struct ColorSplitBehavior: Behavior {
    static let id = "colorSplit"

    let controlledAttributes: Set<FixtureAttribute> = [.red, .green, .blue, .white]

    func evaluate(
        fixtures: [StageFixture],
        context: BehaviorContext
    ) -> [UUID: [FixtureAttribute: Double]] {
        let palette = context.palette
        let intensity = context.parameters.intensity
        let colorCount = max(1, palette.colors.count)

        var result: [UUID: [FixtureAttribute: Double]] = [:]

        for (index, fixture) in fixtures.enumerated() {
            guard fixture.attributes.contains(.red) else { continue }

            // Spread palette colors across fixtures evenly
            let colorIndex: Int
            if fixtures.count <= colorCount {
                colorIndex = index
            } else {
                // More fixtures than colors: distribute evenly
                colorIndex = (index * colorCount) / fixtures.count
            }

            let color = palette.colorForIndex(colorIndex).scaled(by: intensity)

            result[fixture.id] = [
                .red: color.red,
                .green: color.green,
                .blue: color.blue,
                .white: color.white,
            ]
        }

        return result
    }
}
