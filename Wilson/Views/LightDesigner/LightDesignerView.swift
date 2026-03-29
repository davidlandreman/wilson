import SwiftUI

struct LightDesignerView: View {
    @Environment(\.appState) private var appState
    @State private var showingCatalog = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Stage Fixtures")
                    .font(.headline)
                Spacer()

                Menu("Presets") {
                    ForEach(FixturePreset.all) { preset in
                        Button(preset.name) {
                            applyPreset(preset)
                        }
                    }
                }

                Button {
                    showingCatalog = true
                } label: {
                    Label("Add Fixture", systemImage: "plus")
                }
            }
            .padding()

            Divider()

            if appState.fixtureManager.fixtures.isEmpty {
                ContentUnavailableView {
                    Label("No Fixtures", systemImage: "lightbulb")
                } description: {
                    Text("Add fixtures from the catalog to get started.")
                } actions: {
                    Button("Add Fixture") {
                        showingCatalog = true
                    }
                }
            } else {
                List {
                    ForEach(appState.fixtureManager.fixtures) { fixture in
                        StageFixtureRow(fixture: fixture)
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { appState.fixtureManager.fixtures[$0].id }
                        for id in ids {
                            appState.fixtureManager.removeFixture(id: id)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showingCatalog) {
            FixtureCatalogSheet()
        }
    }

    private func applyPreset(_ preset: FixturePreset) {
        // Clear existing fixtures
        for fixture in appState.fixtureManager.fixtures {
            appState.decisionEngine.removeOverride(for: fixture.id)
        }
        appState.fixtureManager.removeAll()

        // Add preset fixtures
        for entry in preset.fixtures {
            appState.fixtureManager.addFixture(
                definition: entry.definition,
                label: entry.label
            )
        }
    }
}

// MARK: - Fixture Presets

struct FixturePresetEntry {
    let definition: FixtureDefinition
    let label: String
}

struct FixturePreset: Identifiable {
    let id = UUID()
    let name: String
    let fixtures: [FixturePresetEntry]

    static let all: [FixturePreset] = [
        FixturePreset(
            name: "RGB, Strobe, RGB",
            fixtures: [
                FixturePresetEntry(definition: FixtureCatalog.genericRGBPar, label: "RGB Par L"),
                FixturePresetEntry(definition: FixtureCatalog.genericStrobe, label: "Strobe C"),
                FixturePresetEntry(definition: FixtureCatalog.genericRGBPar, label: "RGB Par R"),
            ]
        ),
        FixturePreset(
            name: "4x RGB Par",
            fixtures: (1...4).map {
                FixturePresetEntry(definition: FixtureCatalog.genericRGBPar, label: "RGB Par \($0)")
            }
        ),
        FixturePreset(
            name: "6x RGB Par",
            fixtures: (1...6).map {
                FixturePresetEntry(definition: FixtureCatalog.genericRGBPar, label: "RGB Par \($0)")
            }
        ),
        FixturePreset(
            name: "2x Strobe + 4x RGB",
            fixtures: [
                FixturePresetEntry(definition: FixtureCatalog.genericRGBPar, label: "RGB Par 1"),
                FixturePresetEntry(definition: FixtureCatalog.genericStrobe, label: "Strobe L"),
                FixturePresetEntry(definition: FixtureCatalog.genericRGBPar, label: "RGB Par 2"),
                FixturePresetEntry(definition: FixtureCatalog.genericRGBPar, label: "RGB Par 3"),
                FixturePresetEntry(definition: FixtureCatalog.genericStrobe, label: "Strobe R"),
                FixturePresetEntry(definition: FixtureCatalog.genericRGBPar, label: "RGB Par 4"),
            ]
        ),
        FixturePreset(
            name: "8x RGB Par",
            fixtures: (1...8).map {
                FixturePresetEntry(definition: FixtureCatalog.genericRGBPar, label: "RGB Par \($0)")
            }
        ),
        FixturePreset(
            name: "4x Moving Head",
            fixtures: (1...4).map {
                FixturePresetEntry(definition: FixtureCatalog.genericMovingHeadRGB, label: "Mover \($0)")
            }
        ),
        FixturePreset(
            name: "2x Mover + Strobe + 2x Mover",
            fixtures: [
                FixturePresetEntry(definition: FixtureCatalog.genericMovingHeadRGB, label: "Mover L1"),
                FixturePresetEntry(definition: FixtureCatalog.genericMovingHeadRGB, label: "Mover L2"),
                FixturePresetEntry(definition: FixtureCatalog.genericStrobe, label: "Strobe C"),
                FixturePresetEntry(definition: FixtureCatalog.genericMovingHeadRGB, label: "Mover R1"),
                FixturePresetEntry(definition: FixtureCatalog.genericMovingHeadRGB, label: "Mover R2"),
            ]
        ),
        FixturePreset(
            name: "Full Rig: 4x Par + 4x Mover",
            fixtures: [
                FixturePresetEntry(definition: FixtureCatalog.genericMovingHeadRGB, label: "Mover 1"),
                FixturePresetEntry(definition: FixtureCatalog.genericRGBPar, label: "Par 1"),
                FixturePresetEntry(definition: FixtureCatalog.genericMovingHeadRGB, label: "Mover 2"),
                FixturePresetEntry(definition: FixtureCatalog.genericRGBPar, label: "Par 2"),
                FixturePresetEntry(definition: FixtureCatalog.genericRGBPar, label: "Par 3"),
                FixturePresetEntry(definition: FixtureCatalog.genericMovingHeadRGB, label: "Mover 3"),
                FixturePresetEntry(definition: FixtureCatalog.genericRGBPar, label: "Par 4"),
                FixturePresetEntry(definition: FixtureCatalog.genericMovingHeadRGB, label: "Mover 4"),
            ]
        ),
    ]
}

struct StageFixtureRow: View {
    let fixture: StageFixture

    var body: some View {
        HStack {
            Image(systemName: iconName)
                .frame(width: 24)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading) {
                Text(fixture.label)
                    .font(.body)
                Text(fixture.definition.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if fixture.isVirtual {
                Text("Virtual")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.15))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }

            if let addr = fixture.dmxAddress {
                Text("DMX \(addr)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var iconName: String {
        if fixture.attributes.contains(.red) {
            return "light.max"
        }
        return "bolt.fill"
    }
}
