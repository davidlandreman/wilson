import SwiftUI

struct DashboardView: View {
    @Environment(\.appState) private var appState
    @State private var captureError: String?
    @State private var tapError: String?
    @State private var testAudioError: String?
    @State private var dmxDevices: [String] = []
    @State private var selectedDMXDevice: String?
    @State private var dmxError: String?

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

            GroupBox("Apple Music (Audio Tap)") {
                VStack(spacing: 12) {
                    HStack {
                        Label(
                            appState.coreAudioTapService.isCapturing
                                ? "Capturing \(appState.coreAudioTapService.targetProcessName ?? "Music")"
                                : "Stopped",
                            systemImage: appState.coreAudioTapService.isCapturing
                                ? "music.note.list" : "music.note"
                        )
                        .foregroundStyle(
                            appState.coreAudioTapService.isCapturing ? .green : .secondary
                        )

                        Spacer()

                        Button(appState.coreAudioTapService.isCapturing ? "Stop" : "Start") {
                            Task {
                                await toggleAudioTap()
                            }
                        }
                    }

                    if appState.coreAudioTapService.isCapturing {
                        HStack(spacing: 8) {
                            Text("Level")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ProgressView(value: min(Double(appState.coreAudioTapService.audioLevel * 3), 1.0))
                                .animation(.linear(duration: 0.05), value: appState.coreAudioTapService.audioLevel)
                            Text(String(format: "%.3f", appState.coreAudioTapService.audioLevel))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let error = tapError {
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
                        // Center fixtures — white, pointing straight down
                        for def in FixtureCatalog.all {
                            let fixture = appState.fixtureManager.addFixture(
                                definition: def,
                                label: "Test \(def.name)",
                                persist: false
                            )
                            var state = FixtureState(fixtureID: fixture.id)
                            state.attributes[.dimmer] = 1.0
                            if fixture.attributes.contains(.red) {
                                state.attributes[.red] = 1.0
                                state.attributes[.green] = 1.0
                                state.attributes[.blue] = 1.0
                            }
                            appState.decisionEngine.setOverride(for: fixture.id, state: state)
                        }

                        // Edge wash fixtures — blue, angled 45° toward audience
                        for i in 1...2 {
                            let fixture = appState.fixtureManager.addFixture(
                                definition: FixtureCatalog.genericRGBPar,
                                label: "Test Blue Wash \(i)",
                                persist: false
                            )
                            var state = FixtureState(fixtureID: fixture.id)
                            state.attributes[.dimmer] = 1.5
                            state.attributes[.red] = 0.05
                            state.attributes[.green] = 0.15
                            state.attributes[.blue] = 1.0
                            state.attributes[.tilt] = -0.25 // 45° toward audience
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
                VStack(spacing: 12) {
                    HStack {
                        Label(
                            appState.dmxOutput.isConnected
                                ? "Connected"
                                : "Disconnected",
                            systemImage: appState.dmxOutput.isConnected
                                ? "cable.connector" : "cable.connector.slash"
                        )
                        .foregroundStyle(
                            appState.dmxOutput.isConnected ? .green : .secondary
                        )

                        Spacer()

                        if appState.dmxOutput.isConnected {
                            Button("Disconnect") {
                                appState.dmxOutput.disconnect()
                            }
                        }
                    }

                    if !appState.dmxOutput.isConnected {
                        HStack(spacing: 8) {
                            Picker("Device", selection: $selectedDMXDevice) {
                                Text("Select device...").tag(nil as String?)
                                ForEach(dmxDevices, id: \.self) { device in
                                    Text(device.replacingOccurrences(of: "/dev/tty.", with: ""))
                                        .tag(device as String?)
                                }
                            }
                            .frame(maxWidth: .infinity)

                            Button("Scan") {
                                dmxDevices = appState.dmxOutput.scanForDevices()
                                if selectedDMXDevice == nil {
                                    selectedDMXDevice = dmxDevices.first
                                }
                            }

                            Button("Connect") {
                                guard let device = selectedDMXDevice else { return }
                                dmxError = nil
                                do {
                                    try appState.dmxOutput.connect(devicePath: device)
                                } catch {
                                    dmxError = error.localizedDescription
                                }
                            }
                            .disabled(selectedDMXDevice == nil)
                        }
                    }

                    if appState.dmxOutput.isConnected {
                        HStack(spacing: 8) {
                            if let path = appState.dmxOutput.connectedDevicePath {
                                Text(path.replacingOccurrences(of: "/dev/tty.", with: ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "%.1f Hz", appState.dmxOutput.frameRate))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let error = dmxError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(8)
            }
            .frame(maxWidth: 400)
            .onAppear {
                dmxDevices = appState.dmxOutput.scanForDevices()
                selectedDMXDevice = dmxDevices.first
            }

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Stop all audio sources except the one about to start.
    private func stopOtherSources(except: String) async {
        if except != "capture" && appState.audioCaptureService.isCapturing {
            await appState.audioCaptureService.stopCapture()
        }
        if except != "tap" && appState.coreAudioTapService.isCapturing {
            await appState.coreAudioTapService.stopCapture()
        }
        if except != "test" && appState.testAudioService.isPlaying {
            appState.testAudioService.stop()
        }
    }

    private func toggleCapture() async {
        captureError = nil
        if appState.audioCaptureService.isCapturing {
            await appState.audioCaptureService.stopCapture()
        } else {
            await stopOtherSources(except: "capture")
            do {
                try await appState.audioCaptureService.startCapture()
            } catch {
                captureError = error.localizedDescription
            }
        }
    }

    private func toggleAudioTap() async {
        tapError = nil
        if appState.coreAudioTapService.isCapturing {
            await appState.coreAudioTapService.stopCapture()
        } else {
            await stopOtherSources(except: "tap")
            do {
                try await appState.coreAudioTapService.startCapture()
            } catch {
                tapError = error.localizedDescription
            }
        }
    }

    private func toggleTestAudio() async {
        testAudioError = nil
        if appState.testAudioService.isPlaying {
            appState.testAudioService.stop()
        } else {
            await stopOtherSources(except: "test")
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
