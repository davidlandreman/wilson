import SwiftUI
import AppKit

/// Compact debug HUD overlaid on the virtual stage (bottom-left).
/// Shows energy pipeline, scenario, trajectory, and active behaviors.
struct EngineDebugOverlay: View {
    @Environment(\.appState) private var appState

    var body: some View {
        let recorder = appState.telemetryRecorder
        let ms = appState.audioAnalysisService.musicalState
        let mood = appState.decisionEngine.currentMood
        let scenario = appState.decisionEngine.currentScenario
        let groups = appState.decisionEngine.activeGroups
        let slots = appState.decisionEngine.activeSlotDescriptions
        let fixtures = appState.fixtureManager.fixtures

        VStack(alignment: .leading, spacing: 6) {
            // Recording controls
            HStack(spacing: 8) {
                Button {
                    if recorder.isRecording {
                        recorder.stop()
                        saveRecording()
                    } else {
                        recorder.start()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(recorder.isRecording ? .red : .gray)
                            .frame(width: 8, height: 8)
                        Text(recorder.isRecording ? "Stop" : "Record")
                    }
                }
                .buttonStyle(.plain)

                if recorder.isRecording {
                    Text(formatDuration(recorder.elapsed))
                        .foregroundStyle(.red)
                    Text("\(recorder.samples.count) samples")
                        .foregroundStyle(.secondary)
                }
            }

            Divider().overlay(Color.white.opacity(0.2))

            // Energy pipeline
            HStack(spacing: 12) {
                label("Energy", value: ms.energy, color: .blue)
                label("Peak", value: mood.peakEnergy, color: .cyan)
                label("Intensity", value: mood.intensity, color: .green)
            }

            // Bars for energy pipeline
            HStack(spacing: 4) {
                bar(value: ms.energy, color: .blue)
                bar(value: mood.peakEnergy, color: .cyan)
                bar(value: mood.intensity, color: .green)
            }
            .frame(height: 6)

            // Normalization debug
            HStack(spacing: 12) {
                label("Raw", value: ms.rawEnergy, color: .gray)
                label("Ceil", value: ms.normalizationCeiling, color: .gray)
            }

            Divider().overlay(Color.white.opacity(0.2))

            // Mood dimensions
            HStack(spacing: 12) {
                label("Excite", value: mood.excitement, color: .orange)
                label("Bright", value: mood.brightness, color: .yellow)
                label("Chaos", value: mood.chaos, color: .red)
            }

            Divider().overlay(Color.white.opacity(0.2))

            // Scenario + trajectory
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("Scenario")
                        .foregroundStyle(.secondary)
                    Text(scenarioLabel(scenario))
                        .foregroundStyle(scenarioColor(scenario))
                        .fontWeight(.bold)
                }
                HStack(spacing: 4) {
                    Text(trajectoryArrow(mood.energyTrajectory))
                    Text(trajectoryLabel(mood.energyTrajectory))
                        .foregroundStyle(trajectoryColor(mood.energyTrajectory))
                }
            }

            // Active scene
            if let sceneName = appState.decisionEngine.activeSceneName {
                HStack(spacing: 4) {
                    Text("Scene")
                        .foregroundStyle(.secondary)
                    Text(sceneName)
                        .foregroundStyle(.mint)
                        .fontWeight(.bold)
                }
            }

            // BPM
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("BPM")
                        .foregroundStyle(.secondary)
                    Text(ms.bpm > 0 ? String(format: "%.0f", ms.bpm) : "--")
                        .fontWeight(.bold)
                }
                if ms.isBeat {
                    Circle()
                        .fill(.white)
                        .frame(width: 6, height: 6)
                }
                if ms.isSilent {
                    Text("SILENT")
                        .foregroundStyle(.red)
                        .fontWeight(.bold)
                }
            }

            Divider().overlay(Color.white.opacity(0.2))

            // Active behaviors per group
            behaviorSection(groups: groups, slots: slots, fixtures: fixtures)
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.white)
        .padding(10)
        .background(.black.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helpers

    private func label(_ name: String, value: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(name)
                .foregroundStyle(.secondary)
            Text(String(format: "%.2f", value))
                .foregroundStyle(color)
        }
    }

    private func bar(value: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(0.2))
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
    }

    private func behaviorSection(
        groups: [FixtureGroup],
        slots: [String],
        fixtures: [StageFixture]
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(groups) { group in
                let groupSlots = slots.filter { $0.hasSuffix(group.id.uuidString.prefix(4).description) }
                let behaviorNames = groupSlots.compactMap { $0.split(separator: " ").first.map(String.init) }
                let fixtureLabels = fixtures
                    .filter { group.fixtureIDs.contains($0.id) }
                    .map(\.label)

                HStack(spacing: 4) {
                    Text(group.name)
                        .foregroundStyle(roleColor(group.role))
                        .fontWeight(.medium)
                    Text(behaviorNames.joined(separator: "+"))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                    Spacer()
                    Text(fixtureLabels.joined(separator: ","))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Formatting

    private func scenarioLabel(_ scenario: Choreographer.Scenario) -> String {
        switch scenario {
        case .lowEnergy: "Low"
        case .mediumEnergy: "Med"
        case .highEnergy: "High"
        case .building: "Build"
        case .peakDrop: "Peak"
        case .declining: "Decline"
        }
    }

    private func scenarioColor(_ scenario: Choreographer.Scenario) -> Color {
        switch scenario {
        case .lowEnergy: .blue
        case .mediumEnergy: .yellow
        case .highEnergy: .orange
        case .building: .cyan
        case .peakDrop: .red
        case .declining: .purple
        }
    }

    private func trajectoryLabel(_ trajectory: EnergyTrajectory) -> String {
        switch trajectory {
        case .building: "Building"
        case .sustaining: "Sustaining"
        case .declining: "Declining"
        case .stable: "Stable"
        }
    }

    private func trajectoryArrow(_ trajectory: EnergyTrajectory) -> String {
        switch trajectory {
        case .building: "\u{2197}"     // ↗
        case .sustaining: "\u{2192}"   // →
        case .declining: "\u{2198}"    // ↘
        case .stable: "\u{2014}"       // —
        }
    }

    private func trajectoryColor(_ trajectory: EnergyTrajectory) -> Color {
        switch trajectory {
        case .building: .green
        case .sustaining: .orange
        case .declining: .red
        case .stable: .gray
        }
    }

    private func roleColor(_ role: FixtureGroup.GroupRole) -> Color {
        switch role {
        case .primary: .cyan
        case .accent: .yellow
        case .movement: .green
        case .effect: .orange
        case .all: .white
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func saveRecording() {
        guard let data = appState.telemetryRecorder.exportJSON() else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "wilson-telemetry-\(Date().ISO8601Format().prefix(16)).json"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }
}
