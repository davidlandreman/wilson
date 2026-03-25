import SwiftUI

struct FixtureCatalogSheet: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Fixture Catalog")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            List(FixtureCatalog.all) { definition in
                Button {
                    let count = appState.fixtureManager.fixtures
                        .filter { $0.definition.id == definition.id }
                        .count
                    let label = "\(definition.name) \(count + 1)"
                    appState.fixtureManager.addFixture(
                        definition: definition,
                        label: label
                    )
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(definition.name)
                                .font(.body)
                            Text("\(definition.channelCount)ch - \(definition.manufacturer)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(attributeSummary(definition))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minWidth: 350, minHeight: 250)
    }

    private func attributeSummary(_ def: FixtureDefinition) -> String {
        def.channels.map(\.attribute.rawValue).joined(separator: ", ")
    }
}
