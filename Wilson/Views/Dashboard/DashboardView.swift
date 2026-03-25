import SwiftUI

struct DashboardView: View {
    @Environment(\.appState) private var appState
    @State private var captureError: String?
    @State private var testAudioError: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Wilson")
                .font(.largeTitle.bold())

            Text("Autonomous Music-Reactive DMX Lighting")
                .font(.headline)
                .foregroundStyle(.secondary)

            GroupBox("Audio Capture") {
                VStack(spacing: 12) {
                    HStack {
                        Label(
                            appState.audioCaptureService.isCapturing ? "Capturing" : "Stopped",
                            systemImage: appState.audioCaptureService.isCapturing
                                ? "waveform.circle.fill" : "waveform.circle"
                        )
                        .foregroundStyle(
                            appState.audioCaptureService.isCapturing ? .green : .secondary
                        )

                        Spacer()

                        Button(appState.audioCaptureService.isCapturing ? "Stop" : "Start") {
                            Task {
                                await toggleCapture()
                            }
                        }
                    }

                    if appState.audioCaptureService.isCapturing {
                        HStack(spacing: 8) {
                            Text("Level")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ProgressView(value: min(Double(appState.audioCaptureService.audioLevel * 3), 1.0))
                                .animation(.linear(duration: 0.05), value: appState.audioCaptureService.audioLevel)
                            Text(String(format: "%.3f", appState.audioCaptureService.audioLevel))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let error = captureError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(8)
            }
            .frame(maxWidth: 400)

            GroupBox("Test Audio") {
                VStack(spacing: 12) {
                    HStack {
                        Label(
                            appState.testAudioService.isPlaying ? "Playing" : "Stopped",
                            systemImage: appState.testAudioService.isPlaying
                                ? "metronome.fill" : "metronome"
                        )
                        .foregroundStyle(
                            appState.testAudioService.isPlaying ? .green : .secondary
                        )

                        Spacer()

                        Button(appState.testAudioService.isPlaying ? "Stop" : "Start") {
                            Task {
                                await toggleTestAudio()
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        @Bindable var testAudio = appState.testAudioService
                        Text("BPM")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $testAudio.bpm, in: 60...200, step: 1)
                        Text("\(Int(appState.testAudioService.bpm))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .trailing)
                    }

                    if let error = testAudioError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(8)
            }
            .frame(maxWidth: 400)

            GroupBox("Light Test") {
                HStack {
                    let hasTestFixtures = appState.fixtureManager.fixtures.contains { $0.label.hasPrefix("Test ") }

                    Button("Add Test Fixtures") {
                        for def in FixtureCatalog.all {
                            let fixture = appState.fixtureManager.addFixture(
                                definition: def,
                                label: "Test \(def.name)"
                            )
                            // Override to full brightness so they're always on
                            var state = FixtureState(fixtureID: fixture.id)
                            state.attributes[.dimmer] = 1.0
                            if fixture.attributes.contains(.red) {
                                state.attributes[.red] = 1.0
                                state.attributes[.green] = 1.0
                                state.attributes[.blue] = 1.0
                            }
                            appState.decisionEngine.setOverride(for: fixture.id, state: state)
                        }
                        // Push to virtual output so lights appear without audio
                        appState.virtualOutput.update(
                            fixtureStates: appState.decisionEngine.fixtureStates,
                            fixtures: appState.fixtureManager.fixtures
                        )
                    }
                    .disabled(hasTestFixtures)

                    Button("Remove Test Fixtures") {
                        let testIDs = appState.fixtureManager.fixtures
                            .filter { $0.label.hasPrefix("Test ") }
                            .map(\.id)
                        for id in testIDs {
                            appState.decisionEngine.removeOverride(for: id)
                            appState.fixtureManager.removeFixture(id: id)
                        }
                    }
                    .disabled(!hasTestFixtures)

                    Spacer()

                    if hasTestFixtures {
                        Text("\(appState.fixtureManager.fixtures.filter { $0.label.hasPrefix("Test ") }.count) fixtures")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
            }
            .frame(maxWidth: 400)

            GroupBox("DMX Output") {
                HStack {
                    Label(
                        appState.dmxOutput.isConnected ? "Connected" : "Disconnected",
                        systemImage: appState.dmxOutput.isConnected
                            ? "cable.connector" : "cable.connector.slash"
                    )
                    .foregroundStyle(
                        appState.dmxOutput.isConnected ? .green : .secondary
                    )
                    Spacer()
                }
                .padding(8)
            }
            .frame(maxWidth: 400)

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toggleCapture() async {
        captureError = nil
        if appState.audioCaptureService.isCapturing {
            await appState.audioCaptureService.stopCapture()
        } else {
            // Stop test audio if running — sources are mutually exclusive
            if appState.testAudioService.isPlaying {
                appState.testAudioService.stop()
            }
            do {
                try await appState.audioCaptureService.startCapture()
            } catch {
                captureError = error.localizedDescription
            }
        }
    }

    private func toggleTestAudio() async {
        testAudioError = nil
        if appState.testAudioService.isPlaying {
            appState.testAudioService.stop()
        } else {
            // Stop screen capture if running — sources are mutually exclusive
            if appState.audioCaptureService.isCapturing {
                await appState.audioCaptureService.stopCapture()
            }
            do {
                try appState.testAudioService.start()
            } catch {
                testAudioError = error.localizedDescription
            }
        }
    }
}

#Preview {
    DashboardView()
        .environment(\.appState, AppState())
}
