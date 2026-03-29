import SwiftData
import SwiftUI

/// Root view for the manual DMX controller board.
struct DMXControllerView: View {
    @Environment(\.appState) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var viewMode: ViewMode = .fixtures
    @State private var sceneName = ""

    @Query(sort: \DMXScene.createdAt, order: .reverse) private var scenes: [DMXScene]

    enum ViewMode: String, CaseIterable {
        case fixtures = "Fixtures"
        case channels = "Channels"
    }

    private var controller: DMXControllerService { appState.dmxController }
    private var fixtures: [StageFixture] { appState.fixtureManager.fixtures }

    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar
            ControllerToolbarView(
                isActive: Binding(
                    get: { controller.isActive },
                    set: { _ in }
                ),
                grandMaster: Binding(
                    get: { controller.grandMaster },
                    set: { controller.grandMaster = $0 }
                ),
                isBlackout: Binding(
                    get: { controller.isBlackout },
                    set: { controller.isBlackout = $0 }
                ),
                crossfadeDuration: Binding(
                    get: { controller.crossfadeDuration },
                    set: { controller.crossfadeDuration = $0 }
                )
            )

            Divider()

            // Mode picker
            HStack {
                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                Spacer()

                if viewMode == .channels {
                    bankNavigation
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // Main fader area
            if fixtures.isEmpty {
                ContentUnavailableView(
                    "No Fixtures",
                    systemImage: "lightbulb.slash",
                    description: Text("Add fixtures in the Light Designer to control them here.")
                )
            } else if !controller.isActive {
                ContentUnavailableView(
                    "Controller Inactive",
                    systemImage: "slider.horizontal.3",
                    description: Text("Activate the controller to take manual control of fixtures.")
                )
            } else {
                switch viewMode {
                case .fixtures:
                    fixtureFadersView
                case .channels:
                    ChannelFaderView(
                        controller: controller,
                        fixtures: fixtures,
                        engine: appState.decisionEngine,
                        currentBank: Binding(
                            get: { controller.currentBank },
                            set: { controller.currentBank = $0 }
                        )
                    )
                }
            }

            Divider()

            // Scene management panel
            scenePanel
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
    }

    // MARK: - Fixture Faders

    private var fixtureFadersView: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: 8) {
                ForEach(fixtures) { fixture in
                    FixtureFaderStripView(
                        fixture: fixture,
                        values: Binding(
                            get: { controller.fixtureValues[fixture.id] ?? [:] },
                            set: { _ in }  // Individual fader changes handled via onFaderChanged
                        ),
                        onFaderChanged: { attr, value in
                            controller.setFader(
                                fixtureID: fixture.id,
                                attribute: attr,
                                value: value,
                                engine: appState.decisionEngine
                            )
                        },
                        onFlashDown: {
                            controller.flashDown(
                                fixtureID: fixture.id,
                                attribute: .dimmer,
                                engine: appState.decisionEngine
                            )
                        },
                        onFlashUp: {
                            controller.flashUp(
                                fixtureID: fixture.id,
                                attribute: .dimmer,
                                engine: appState.decisionEngine
                            )
                        }
                    )
                }
            }
            .padding(12)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Bank Navigation

    private var bankNavigation: some View {
        let totalChannels = fixtures.reduce(0) { $0 + $1.definition.channels.count }
        let totalBanks = max(1, Int(ceil(Double(totalChannels) / Double(DMXControllerService.channelsPerBank))))

        return HStack(spacing: 8) {
            Button {
                controller.currentBank = max(0, controller.currentBank - 1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(controller.currentBank == 0)

            Text("Bank \(controller.currentBank + 1)/\(totalBanks)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            Button {
                controller.currentBank = min(totalBanks - 1, controller.currentBank + 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(controller.currentBank >= totalBanks - 1)
        }
    }

    // MARK: - Scene Panel

    private var scenePanel: some View {
        VStack(spacing: 8) {
            // Record row
            HStack(spacing: 8) {
                Text("Scenes")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)

                TextField("Scene name", text: $sceneName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)

                Button("Record") {
                    recordScene()
                }
                .disabled(sceneName.isEmpty || !controller.isActive)

                Spacer()
            }

            // Scene list
            if !scenes.isEmpty {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 12) {
                        ForEach(scenes) { scene in
                            SceneCardView(
                                scene: scene,
                                submasterLevel: Binding(
                                    get: { controller.submasterLevels[scene.name] ?? 0 },
                                    set: { newValue in
                                        appState.dmxController.submasterLevels[scene.name] = newValue
                                        if controller.isActive {
                                            appState.dmxController.submasterScenes = scenes
                                            appState.dmxController.pushAllOverrides(engine: appState.decisionEngine)
                                        }
                                    }
                                ),
                                onRecall: {
                                    controller.recallScene(
                                        scene,
                                        crossfade: controller.crossfadeDuration > 0,
                                        engine: appState.decisionEngine
                                    )
                                },
                                onDelete: {
                                    modelContext.delete(scene)
                                    appState.refreshSceneSnapshots(from: scenes.filter { $0 !== scene })
                                },
                                onTagsChanged: {
                                    appState.refreshSceneSnapshots(from: scenes)
                                }
                            )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.15))
    }

    private func recordScene() {
        guard controller.isActive, !sceneName.isEmpty else { return }
        let scene = controller.recordScene(name: sceneName)
        modelContext.insert(scene)
        sceneName = ""
        // Refresh snapshots after SwiftData processes the insert
        DispatchQueue.main.async {
            appState.refreshSceneSnapshots(from: scenes)
        }
    }
}

// MARK: - Scene Card

private struct SceneCardView: View {
    let scene: DMXScene
    @Binding var submasterLevel: Double
    let onRecall: () -> Void
    let onDelete: () -> Void
    let onTagsChanged: () -> Void
    @State private var showTagging = false

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(scene.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                Button {
                    showTagging.toggle()
                } label: {
                    Image(systemName: "tag")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(scene.isAutonomousEnabled ? .blue : .secondary)
                .popover(isPresented: $showTagging) {
                    SceneTaggingView(scene: scene, onChanged: onTagsChanged)
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            // Tag pills
            HStack(spacing: 3) {
                TagPill(scene.energyLevel.rawValue.capitalized, color: energyColor)
                TagPill(scene.mood.rawValue.capitalized, color: moodColor)
                if scene.isAutonomousEnabled {
                    TagPill("\(Int(scene.reactivity * 100))%", color: .blue)
                }
            }

            Button("Recall") {
                onRecall()
            }
            .font(.system(size: 10, weight: .medium))
            .buttonStyle(.bordered)
            .controlSize(.small)

            // Submaster fader
            HStack(spacing: 4) {
                Text("Sub")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Slider(value: $submasterLevel, in: 0...1)
                    .controlSize(.mini)
            }
        }
        .padding(8)
        .frame(width: 160)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.2))
        )
    }

    private var energyColor: Color {
        switch scene.energyLevel {
        case .low: .green
        case .medium: .yellow
        case .high: .red
        case .any: .gray
        }
    }

    private var moodColor: Color {
        switch scene.mood {
        case .calm: .teal
        case .uplifting: .orange
        case .intense: .red
        case .dark: .purple
        case .any: .gray
        }
    }
}

private struct TagPill: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .medium))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
