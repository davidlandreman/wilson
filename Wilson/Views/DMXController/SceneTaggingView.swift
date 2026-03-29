import SwiftUI

/// Popover for tagging a scene with energy/mood metadata and choreographer settings.
struct SceneTaggingView: View {
    let scene: DMXScene
    let onChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scene Settings")
                .font(.system(size: 12, weight: .bold))

            // Autonomous toggle
            Toggle("Available to choreographer", isOn: Binding(
                get: { scene.isAutonomousEnabled },
                set: { scene.isAutonomousEnabled = $0; onChanged() }
            ))
            .font(.system(size: 11))

            Divider()

            // Reactivity
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Reactivity")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(scene.reactivity * 100))%")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(
                    get: { scene.reactivity },
                    set: { scene.reactivity = $0; onChanged() }
                ), in: 0...1)
                HStack {
                    Text("Static look")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("Full behavior")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            // Energy level
            VStack(alignment: .leading, spacing: 4) {
                Text("Energy Level")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Picker("Energy", selection: Binding(
                    get: { scene.energyLevel },
                    set: { scene.energyLevel = $0; onChanged() }
                )) {
                    Text("Low").tag(SceneEnergyLevel.low)
                    Text("Medium").tag(SceneEnergyLevel.medium)
                    Text("High").tag(SceneEnergyLevel.high)
                    Text("Any").tag(SceneEnergyLevel.any)
                }
                .pickerStyle(.segmented)
            }

            // Mood
            VStack(alignment: .leading, spacing: 4) {
                Text("Mood")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Picker("Mood", selection: Binding(
                    get: { scene.mood },
                    set: { scene.mood = $0; onChanged() }
                )) {
                    Text("Calm").tag(SceneMood.calm)
                    Text("Uplifting").tag(SceneMood.uplifting)
                    Text("Intense").tag(SceneMood.intense)
                    Text("Dark").tag(SceneMood.dark)
                    Text("Any").tag(SceneMood.any)
                }
                .pickerStyle(.segmented)
            }

            Divider()

            // Transition
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Transition")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker("Style", selection: Binding(
                        get: { scene.transitionStyle },
                        set: { scene.transitionStyle = $0; onChanged() }
                    )) {
                        Text("Crossfade").tag(SceneTransitionStyle.crossfade)
                        Text("Snap").tag(SceneTransitionStyle.snap)
                        Text("Slow").tag(SceneTransitionStyle.slowDissolve)
                    }
                    .pickerStyle(.segmented)
                }

                if scene.transitionStyle != .snap {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Duration")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Slider(value: Binding(
                                get: { scene.transitionDuration },
                                set: { scene.transitionDuration = $0; onChanged() }
                            ), in: 0.5...8.0, step: 0.5)
                            Text("\(scene.transitionDuration, specifier: "%.1f")s")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 30)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 320)
    }
}
