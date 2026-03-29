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
    let testAudioService = TestAudioService()
    let telemetryRecorder = TelemetryRecorder()
    let dmxController = DMXControllerService()

    var isRunning = false
    var isStageWindowOpen = false
    private var manualRefreshTimer: Timer?

    /// Cached scene snapshots for the autonomous choreographer pipeline.
    /// Updated from the DMX controller view when scenes change.
    private(set) var cachedSceneSnapshots: [SceneSnapshot] = []

    init() {
        // Wire audio sources → analysis pipeline (shared handler)
        let audioHandler = audioAnalysisService.makeAudioBufferHandler()
        audioCaptureService.onAudioBuffer = audioHandler
        testAudioService.onAudioBuffer = audioHandler

        // Wire analysis → decision engine → virtual output pipeline
        let engine = decisionEngine
        let fixtures = fixtureManager
        let virtual = virtualOutput
        let cues = cueService
        let recorder = telemetryRecorder
        audioAnalysisService.onMusicalStateUpdate = { [weak self] musicalState in
            engine.activePalette = cues.activePalette
            let currentFixtures = fixtures.fixtures
            engine.autonomousScenes = self?.cachedSceneSnapshots ?? []
            engine.update(musicalState: musicalState, fixtures: currentFixtures)
            virtual.update(fixtureStates: engine.fixtureStates, fixtures: currentFixtures)
            recorder.tick(
                musicalState: musicalState,
                mood: engine.currentMood,
                scenario: engine.currentScenario,
                slots: engine.activeSlotDescriptions
            )
        }
    }

    /// Refresh the cached scene snapshots for the choreographer pipeline.
    /// Call when scenes are created, deleted, or their tags change.
    func refreshSceneSnapshots(from scenes: [DMXScene]) {
        cachedSceneSnapshots = scenes
            .filter(\.isAutonomousEnabled)
            .map { $0.toSnapshot() }
    }

    /// Start or stop the manual refresh timer based on DMX controller state.
    func updateManualRefreshTimer() {
        if dmxController.isActive && manualRefreshTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.dmxController.isActive else { return }
                    self.dmxController.tickCrossfade(engine: self.decisionEngine)
                    self.dmxController.pushAllOverrides(engine: self.decisionEngine)
                    self.virtualOutput.update(
                        fixtureStates: self.decisionEngine.fixtureStates,
                        fixtures: self.fixtureManager.fixtures
                    )
                }
            }
            // Use .common mode so the timer fires during drag gesture tracking
            RunLoop.main.add(timer, forMode: .common)
            manualRefreshTimer = timer
        } else if !dmxController.isActive, let timer = manualRefreshTimer {
            timer.invalidate()
            manualRefreshTimer = nil
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
