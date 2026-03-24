import SwiftUI

/// Central app state that owns all service instances and coordinates subsystems.
@Observable
final class AppState {
    let audioCaptureService = AudioCaptureService()
    let audioAnalysisService = AudioAnalysisService()
    let decisionEngine = DecisionEngineService()
    let fixtureManager = FixtureManager()
    let cueService = CueService()
    let dmxOutput = DMXOutputService()

    var isRunning = false

    init() {
        // Wire audio capture → analysis pipeline
        audioCaptureService.onAudioBuffer = audioAnalysisService.makeAudioBufferHandler()
    }
}

extension EnvironmentValues {
    @Entry var appState: AppState = AppState()
}
