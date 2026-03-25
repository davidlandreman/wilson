import SwiftUI

/// Central app state that owns all service instances and coordinates subsystems.
@MainActor @Observable
final class AppState {
    let audioCaptureService = AudioCaptureService()
    let audioAnalysisService = AudioAnalysisService()
    let decisionEngine = DecisionEngineService()
    let fixtureManager = FixtureManager()
    let cueService = CueService()
    let dmxOutput = DMXOutputService()
    let virtualOutput = VirtualOutputService()

    var isRunning = false

    init() {
        // Wire audio capture → analysis pipeline
        audioCaptureService.onAudioBuffer = audioAnalysisService.makeAudioBufferHandler()

        // Wire analysis → decision engine → virtual output pipeline
        let engine = decisionEngine
        let fixtures = fixtureManager
        let virtual = virtualOutput
        audioAnalysisService.onMusicalStateUpdate = { musicalState in
            let currentFixtures = fixtures.fixtures
            engine.update(musicalState: musicalState, fixtures: currentFixtures)
            virtual.update(fixtureStates: engine.fixtureStates, fixtures: currentFixtures)
        }
    }
}

private struct AppStateKey: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue = AppState()
}

extension EnvironmentValues {
    var appState: AppState {
        get { self[AppStateKey.self] }
        set { self[AppStateKey.self] = newValue }
    }
}
