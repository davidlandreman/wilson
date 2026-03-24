# DSP Audio Analysis Architecture

Wilson's real-time audio analysis pipeline extracts musical features from system audio at ~47 frames/second, feeding the Decision Engine and Debug UI.

---

## Pipeline Overview

```
48 kHz system audio (ScreenCaptureKit)
    │
    ▼
┌──────────────────────────────────────────────────────────┐
│  AudioCaptureService                                      │
│  Converts CMSampleBuffer → AVAudioPCMBuffer              │
│  Runs on dedicated DispatchQueue(.userInteractive)        │
└──────────────┬───────────────────────────────────────────┘
               │ onAudioBuffer callback (audio queue)
               ▼
┌──────────────────────────────────────────────────────────┐
│  DSPPipeline                                              │
│  Orchestrates all analysis on the audio queue             │
│                                                           │
│  ┌─────────────┐                                          │
│  │ RingBuffer   │ ← accumulates samples (4096 capacity)  │
│  │ hop = 1024   │   triggers analysis every 1024 samples  │
│  └──────┬──────┘                                          │
│         │ every ~21ms                                     │
│         ▼                                                 │
│  ┌─────────────┐                                          │
│  │ FFTEngine    │ Hann window → vDSP FFT → magnitudes    │
│  │ 2048-pt FFT  │ → 1024 magnitude bins                  │
│  └──────┬──────┘                                          │
│         │                                                 │
│         ├──▶ SpectralAnalyzer → bands, centroid,          │
│         │                       flatness, flux, dominant  │
│         ├──▶ EnergyAnalyzer   → RMS, peak, crest, silence│
│         ├──▶ OnsetDetector    → onset flag + strength     │
│         ├──▶ BeatTracker      → BPM, phase, bar position │
│         └──▶ ChromagramAnalyzer → 12 pitch classes, key   │
│                                                           │
│  Assembles MusicalState snapshot                          │
└──────────────┬───────────────────────────────────────────┘
               │ Task { @MainActor } via StateUpdater
               ▼
┌──────────────────────────────────────────────────────────┐
│  AudioAnalysisService (@Observable)                       │
│  musicalState: MusicalState  ← read by SwiftUI views     │
└──────────────────────────────────────────────────────────┘
```

---

## Key Parameters

| Parameter | Value | Notes |
|-----------|-------|-------|
| Sample rate | 48,000 Hz | ScreenCaptureKit default |
| FFT size | 2,048 samples | 42.7ms window |
| Hop size | 1,024 samples | 21.3ms, 50% overlap |
| Frequency resolution | 23.4 Hz/bin | 48000 / 2048 |
| Analysis rate | ~46.9 Hz | 48000 / 1024 |
| Magnitude bins | 1,024 | FFT size / 2 |
| Waveform buffer | 2,400 samples | ~50ms at 48kHz |

---

## Components

### RingBuffer

Circular buffer accumulating audio samples with hop-size tracking.

- **Capacity:** `fftSize × 2` (4096 samples)
- **Hop tracking:** Counts new samples written; signals when 1024 new samples ready
- **Not thread-safe** by design — single dispatch queue access only
- **Read:** Returns most recent N samples linearized (handles wrap-around)

### FFTEngine

Hardware-accelerated FFT via Apple's Accelerate framework.

**Processing chain:**
1. Apply Hann window (`vDSP_hann_window`, `vDSP_vmul`)
2. Pack real samples into split complex format (even→real, odd→imag)
3. Forward real-to-complex FFT (`vDSP_fft_zrip`)
4. Compute magnitudes (`vDSP_zvabs` → √(re² + im²))
5. Normalize by 1/binCount (`vDSP_vsmul`)

**Output:** 1024 magnitude bins (linear scale), 0 Hz to 24 kHz.

### SpectralAnalyzer

Extracts spectral features from the magnitude spectrum.

**Band energies** (RMS of magnitude bins per band):

| Band | Frequency Range | Bin Range |
|------|----------------|-----------|
| Sub-bass | 20–60 Hz | 1–3 |
| Bass | 60–250 Hz | 3–11 |
| Mids | 250–2,000 Hz | 11–85 |
| Highs | 2,000–6,000 Hz | 85–256 |
| Presence | 6,000–20,000 Hz | 256–853 |

**Spectral centroid:** Weighted mean frequency — a single number for "brightness."
```
centroid = Σ(freq[k] × mag[k]) / Σ(mag[k])
```

**Spectral flatness:** Geometric mean / arithmetic mean of magnitudes.
- 0.0 = pure tone (all energy in one bin)
- 1.0 = white noise (energy spread evenly)
- Computed via log domain: exp(mean(log(magnitudes))) / mean(magnitudes)

**Spectral flux:** Half-wave rectified difference between current and previous frame magnitudes. Measures the rate of spectral change; feeds the onset detector.

**Dominant frequency:** Bin with the highest magnitude, converted to Hz.

### EnergyAnalyzer

Time-domain energy metrics from raw audio samples.

| Metric | Method | Notes |
|--------|--------|-------|
| RMS | `vDSP_rmsqv` | Overall energy level |
| Peak | `vDSP_maxmgv` | Instantaneous peak absolute value |
| Crest factor | peak / RMS | Normalized to 0–1 (reference max = 15). Higher = punchier transients |
| Silence | RMS < 0.001 | Hysteresis: 5 consecutive frames (~100ms) required |

### OnsetDetector

Detects transient events (drum hits, note attacks, any sudden spectral change) using spectral flux with an adaptive threshold.

**Algorithm:**
1. Maintain sliding window of recent flux values (~23 frames, ~0.5s)
2. Compute adaptive threshold: `median(fluxHistory) × sensitivity + 0.001`
3. Peak-picking: onset fires when `flux > threshold` AND `flux ≥ previousFlux`
4. Minimum inter-onset interval: 3 frames (~64ms) to prevent retriggering

**Parameters:**
- `medianWindow = 23` (~0.5 seconds of history)
- `minimumInterval = 3` frames (~64ms)
- `sensitivity = 1.5` (threshold multiplier on median)

**Output:** `isOnset` (boolean) + `onsetStrength` (0–1, how far above threshold).

### BeatTracker

Estimates tempo and maintains a phase-locked beat clock. The most complex DSP component.

**Two-stage architecture:**

#### Stage A: BPM Estimation (runs every ~500ms)

Uses autocorrelation of the onset strength signal:

1. Buffer ~4 seconds of onset strength values (~188 frames)
2. Compute autocorrelation via FFT: `R(τ) = IFFT(|FFT(x)|²)`
3. Search for peaks at lags corresponding to 60–200 BPM
4. **Octave error correction:** Check 0.5×, 1×, 2× BPM candidates; prefer 90–160 BPM range (most common music tempo)
5. **Hysteresis:** Require 3 consecutive consistent estimates within 5% tolerance before switching BPM. Refine current estimate with EMA (0.9 old + 0.1 new).

**Confidence:** Peak autocorrelation value / mean autocorrelation, normalized to 0–1.

#### Stage B: Phase-Locked Beat Clock (runs every frame)

1. Increment `beatPhase` by `(bpm / 60) × hopDuration` each frame
2. When `beatPhase ≥ 1.0`: wrap to 0, fire `isBeat`, advance `barBeatCount`
3. **Phase correction:** When an onset is detected near an expected beat boundary (within 20% of a beat period), nudge phase toward the onset with correction gain of 0.2
4. `beatPosition = barBeatCount + beatPhase` (0.0→4.0 for 4/4 time)
5. `isDownbeat` fires when `barBeatCount` wraps from 3 to 0

### ChromagramAnalyzer

Maps FFT magnitudes to 12 pitch classes and detects musical key.

**Chromagram computation:**
1. Pre-compute bin-to-pitch-class mapping at init (bins 65 Hz–2100 Hz, C2–C7)
2. For each bin: `midiNote = 69 + 12 × log₂(freq / 440)`, `pitchClass = round(midiNote) % 12`
3. Sum magnitudes per pitch class → raw 12-element chromagram
4. Normalize (max = 1.0) and apply EMA smoothing (α = 0.15)

**Key detection (Krumhansl-Schmuckler algorithm):**
1. Pre-store 24 key profiles (12 major + 12 minor), each a 12-element vector of expected pitch class weights
2. Compute Pearson correlation between smoothed chromagram and each profile
3. Highest correlation → detected key; correlation value → confidence

**Key profiles (Krumhansl-Kessler):**
- Major: `[6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]`
- Minor: `[6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]`

**Stability:** Requires ~2 seconds of consistent detection before reporting a key change (prevents jitter during transitions).

---

## MusicalState

The `MusicalState` struct is the single output of the pipeline — a Sendable snapshot consumed by the Decision Engine and SwiftUI views.

```
Rhythm
├── bpm: Double                    Estimated tempo
├── bpmConfidence: Double          0–1, autocorrelation peak sharpness
├── beatPhase: Double              0.0→1.0 continuous sawtooth within beat
├── beatPosition: Double           0.0→4.0 position within bar (4/4)
├── isBeat: Bool                   True on beat onset frame
└── isDownbeat: Bool               True on beat 1 of bar

Energy & Dynamics
├── energy: Double                 RMS energy 0–1
├── peakLevel: Double              Instantaneous peak 0–1
└── crestFactor: Double            Peak/RMS normalized 0–1 (punchiness)

Spectral
├── spectralProfile                5-band breakdown (sub-bass→presence)
├── spectralCentroid: Double       Weighted mean frequency (Hz) — brightness
├── spectralFlatness: Double       0 = tonal, 1 = noise
└── dominantFrequency: Double      Loudest frequency (Hz)

Visualization
├── magnitudeSpectrum: [Float]     1024 FFT bins for spectrum display
└── waveformBuffer: [Float]        ~2400 samples (~50ms) for oscilloscope

Onsets
├── isOnset: Bool                  Any transient (superset of isBeat)
└── onsetStrength: Double          0–1, how far above threshold

Key Detection
├── chromagram: [Double]           12 pitch classes (C, C♯, D, ... B)
├── detectedKey: MusicalKey        Detected key (24 options + unknown)
└── keyConfidence: Double          0–1

Structure (Phase 3 — not yet implemented)
├── segment: SongSegment           Verse, chorus, drop, etc.
└── transitionProbability: Double  Likelihood of imminent transition

State
└── isSilent: Bool                 True after ~100ms of silence
```

---

## Concurrency Model

The pipeline has a clean isolation boundary between the audio thread and the main actor:

| Layer | Isolation | Types |
|-------|-----------|-------|
| DSP components | Audio dispatch queue | `@unchecked Sendable` classes |
| MusicalState | Value type | `Sendable` struct |
| AudioAnalysisService | Main actor | `@Observable` class |
| Bridge | `StateUpdater` | `@unchecked Sendable`, `@MainActor` apply method |

**No locks in the hot path.** The audio queue owns all DSP state exclusively. State crosses to main actor as a value-type copy via `Task { @MainActor }`.

---

## Accelerate / vDSP Functions Used

| Function | Component | Purpose |
|----------|-----------|---------|
| `vDSP_hann_window` | FFTEngine | Generate Hann window coefficients |
| `vDSP_vmul` | FFTEngine | Apply window (element-wise multiply) |
| `vDSP_fft_zrip` | FFTEngine, BeatTracker | Real-to-complex in-place FFT |
| `vDSP_zvabs` | FFTEngine | Complex magnitude √(re² + im²) |
| `vDSP_zvmags` | BeatTracker | Squared magnitude (power spectrum) |
| `vDSP_vsmul` | FFTEngine | Scale vector by constant |
| `vDSP_svesq` | SpectralAnalyzer | Sum of squares (band energy) |
| `vDSP_dotpr` | SpectralAnalyzer | Dot product (spectral centroid) |
| `vDSP_sve` | SpectralAnalyzer | Vector sum |
| `vDSP_meanv` | SpectralAnalyzer, BeatTracker | Arithmetic mean |
| `vDSP_maxvi` | SpectralAnalyzer | Max value + index |
| `vDSP_vsub` | SpectralAnalyzer | Vector subtract (spectral flux) |
| `vDSP_vthres` | SpectralAnalyzer | Threshold (half-wave rectify) |
| `vDSP_rmsqv` | EnergyAnalyzer | RMS energy |
| `vDSP_maxmgv` | EnergyAnalyzer | Peak absolute value |
| `vDSP_vsort` | OnsetDetector | Sort for median computation |

---

## File Map

```
Wilson/Services/AudioAnalysis/
├── AudioAnalysisService.swift    @Observable bridge, main-actor state
├── DSPPipeline.swift             Orchestrator — chains all DSP on audio queue
├── RingBuffer.swift              Circular sample buffer with hop tracking
├── FFTEngine.swift               vDSP FFT, Hann window, magnitude spectrum
├── SpectralAnalyzer.swift        Bands, centroid, flatness, flux, dominant freq
├── EnergyAnalyzer.swift          RMS, peak, crest factor, silence
├── OnsetDetector.swift           Spectral flux onset detection
├── BeatTracker.swift             Autocorrelation BPM + PLL beat clock
└── ChromagramAnalyzer.swift      Pitch class mapping, key detection

Wilson/Models/
└── MusicalState.swift            Pipeline output struct + MusicalKey enum
```
