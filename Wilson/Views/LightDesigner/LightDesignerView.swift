import SwiftUI

struct LightDesignerView: View {
    @Environment(\.appState) private var appState
    @State private var showingCatalog = false
    @State private var showingClearConfirmation = false

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

                Button(role: .destructive) {
                    showingClearConfirmation = true
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
                .disabled(appState.fixtureManager.fixtures.isEmpty)

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
                        StageFixtureRow(fixture: fixture) {
                            removeFixture(id: fixture.id)
                        }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { appState.fixtureManager.fixtures[$0].id }
                        for id in ids {
                            removeFixture(id: id)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showingCatalog) {
            FixtureCatalogSheet()
        }
        .alert("Clear All Fixtures?", isPresented: $showingClearConfirmation) {
            Button("Clear All", role: .destructive) {
                clearAllFixtures()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all \(appState.fixtureManager.fixtures.count) fixtures from the stage.")
        }
    }

    private func clearAllFixtures() {
        for fixture in appState.fixtureManager.fixtures {
            appState.decisionEngine.removeOverride(for: fixture.id)
        }
        appState.fixtureManager.removeAll()
    }

    private func removeFixture(id: UUID) {
        appState.decisionEngine.removeOverride(for: id)
        appState.fixtureManager.removeFixture(id: id)
    }

    private func applyPreset(_ preset: FixturePreset) {
        clearAllFixtures()

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
    @Environment(\.appState) private var appState
    let fixture: StageFixture
    var onDelete: (() -> Void)?
    @State private var isExpanded = false
    @State private var dmxAddressText = ""

    var body: some View {
        VStack(spacing: 0) {
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
                } else if let addr = fixture.dmxAddress {
                    Text("DMX \(addr)")
                        .font(.caption.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.15))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                }

                Button {
                    isExpanded.toggle()
                    if isExpanded {
                        dmxAddressText = fixture.dmxAddress.map(String.init) ?? ""
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Patch settings")

                if let onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove fixture")
                }
            }
            .padding(.vertical, 2)

            if isExpanded {
                HStack(spacing: 12) {
                    Toggle("DMX Output", isOn: Binding(
                        get: { !fixture.isVirtual },
                        set: { enabled in
                            let addr = Int(dmxAddressText)
                            appState.fixtureManager.patchFixture(
                                id: fixture.id,
                                dmxAddress: enabled ? (addr ?? 1) : nil,
                                isVirtual: !enabled
                            )
                            if enabled && dmxAddressText.isEmpty {
                                dmxAddressText = "1"
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    HStack(spacing: 4) {
                        Text("Addr:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("1", text: $dmxAddressText)
                            .frame(width: 45)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption.monospacedDigit())
                            .onSubmit {
                                if let addr = Int(dmxAddressText), addr >= 1 && addr <= 512 {
                                    appState.fixtureManager.patchFixture(
                                        id: fixture.id,
                                        dmxAddress: addr,
                                        isVirtual: false
                                    )
                                }
                            }
                    }
                    .disabled(fixture.isVirtual)

                    Text("\(fixture.definition.channelCount)ch")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Spacer()
                }
                .padding(.leading, 32)
                .padding(.vertical, 4)
            }
        }
    }

    private var iconName: String {
        if fixture.attributes.contains(.pan) || fixture.attributes.contains(.tilt) {
            return "arrow.up.and.down.and.arrow.left.and.right"
        }
        if fixture.attributes.contains(.red) {
            return "light.max"
        }
        return "bolt.fill"
    }
}
