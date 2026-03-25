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
        .sheet(isPresented: $showingCatalog) {
            FixtureCatalogSheet()
        }
    }
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
