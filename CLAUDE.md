# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build System

This project uses **XcodeGen** to generate the Xcode project from `project.yml`. Never edit `Wilson.xcodeproj` directly — edit `project.yml` and regenerate.

```bash
# Regenerate Xcode project after changing project.yml
xcodegen generate

# Build
xcodebuild build -project Wilson.xcodeproj -scheme Wilson -destination "platform=macOS,arch=arm64"

# Run all tests
xcodebuild test -project Wilson.xcodeproj -scheme Wilson -destination "platform=macOS,arch=arm64"

# Quiet build (errors only)
xcodebuild build -project Wilson.xcodeproj -scheme Wilson -destination "platform=macOS,arch=arm64" -quiet

# Build and run the app
bin/run          # Debug build
bin/run Release  # Release build
```

Tests use Swift's native `@Testing` framework (not XCTest). Use `@Test` and `#expect` macros.

## Architecture

Wilson is an autonomous music-reactive DMX lighting controller. macOS 15+, Swift 6 with strict concurrency, SwiftUI.

**Data flow — a linear pipeline:**

```
AudioCaptureService → AudioAnalysisService → DecisionEngineService → DMXOutputService
     (ScreenCaptureKit)    (vDSP/CoreML)        (rule engine)         (ENTTEC serial)
```

`FixtureManager` and `CueService` feed configuration into `DecisionEngineService` (what fixtures exist, what palette/cue is active).

**State management:** `AppState` is a single `@Observable` class that owns all service instances. Passed to views via `@Environment(\.appState)`. Views never own services directly.

**Persistence:** SwiftData models (`@Model`) for `FixtureProfile`, `PatchedFixture`, `Cue`, `ColorPalette`. Runtime-only structs (`Sendable`) for `MusicalState`, `DMXFrame`, `SpectralProfile`.

## Key Conventions

- All runtime data types flowing through the pipeline (`MusicalState`, `DMXFrame`, `SpectralProfile`, `LightColor`) must be `Sendable`
- `DMXFrame` uses 1-based subscript addressing to match DMX channel numbering (channel 1 = index 0)
- Services are organized under `Wilson/Services/{SubsystemName}/`
- Views go under `Wilson/Views/{FeatureArea}/`
- Entitlements in `Wilson/Wilson.entitlements` — audio capture is required for ScreenCaptureKit
- Direct distribution (not Mac App Store) due to USB serial access and ScreenCaptureKit entitlements
