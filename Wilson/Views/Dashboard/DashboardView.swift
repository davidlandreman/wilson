import SwiftUI

struct DashboardView: View {
    @Environment(\.appState) private var appState
    @State private var captureError: String?

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
            do {
                try await appState.audioCaptureService.startCapture()
            } catch {
                captureError = error.localizedDescription
            }
        }
    }
}

#Preview {
    DashboardView()
        .environment(\.appState, AppState())
}
