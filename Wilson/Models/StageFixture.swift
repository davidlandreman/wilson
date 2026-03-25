import Foundation

/// A fixture instance placed on the virtual or physical stage.
/// `dmxAddress == nil` means virtual-only (no DMX output).
struct StageFixture: Identifiable, Sendable {
    let id: UUID
    var label: String
    let definition: FixtureDefinition
    var dmxAddress: Int?
    var isVirtual: Bool
    var position: SIMD2<Double>

    var attributes: Set<FixtureAttribute> { definition.attributes }

    init(
        id: UUID = UUID(),
        label: String,
        definition: FixtureDefinition,
        dmxAddress: Int? = nil,
        isVirtual: Bool = true,
        position: SIMD2<Double> = SIMD2(0.5, 0.5)
    ) {
        self.id = id
        self.label = label
        self.definition = definition
        self.dmxAddress = dmxAddress
        self.isVirtual = isVirtual
        self.position = position
    }
}
