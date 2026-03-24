# LightMaestro — Development Overview

**An autonomous, music-reactive DMX lighting controller for macOS**

*Inspired by MaestroDMX's "lighting designer in a box" concept — reimagined as a native software solution.*

---

## 1. Vision

A native macOS application that listens to system audio in real time, understands musical structure (not just volume), and autonomously drives a full DMX lighting rig — from simple RGB pars to moving heads, pixel bars, lasers, and effects. The software replaces the need for a dedicated hardware controller while delivering the same "set it and forget it" intelligence that makes MaestroDMX compelling.

**Target user:** Venue operators and lighting professionals who want intelligent, autonomous lighting control without manual per-song programming.

**Commercial goal:** Designed from day one for eventual distribution and sale.

---

## 2. Core Architecture

```
┌──────────────────────────────────────────────────────────┐
│                     macOS Application                     │
│                       (SwiftUI)                           │
│                                                          │
│  ┌─────────────┐   ┌──────────────┐   ┌───────────────┐ │
│  │ Audio Engine │──▶│ Analysis Core│──▶│ Decision Engine│ │
│  │ (CoreAudio)  │   │ (DSP + ML)   │   │ (Lighting AI)  │ │
│  └─────────────┘   └──────────────┘   └───────┬───────┘ │
│                                                │         │
│  ┌─────────────┐   ┌──────────────┐   ┌───────▼───────┐ │
│  │ Fixture Mgr  │◀──│  Cue System   │◀──│  DMX Renderer │ │
│  │ (Profiles,   │   │ (Palettes,    │   │ (Channel      │ │
│  │  Patching)   │   │  Scenes)      │   │  Output)      │ │
│  └─────────────┘   └──────────────┘   └───────┬───────┘ │
│                                                │         │
└────────────────────────────────────────────────┼─────────┘
                                                 │
                                          USB-to-DMX Dongle
                                          (e.g. ENTTEC Pro)
                                                 │
                                            DMX Fixtures
```

The application is composed of six major subsystems, described below.

---

## 3. Subsystem Breakdown

### 3.1 Audio Capture Engine

**What it does:** Captures system audio output in real time using macOS audio APIs.

**Key technical considerations:**

- **macOS system audio loopback** is not natively supported by CoreAudio. This is the single biggest platform constraint. Solutions include:
  - Requiring a virtual audio driver (e.g., BlackHole, Loopback by Rogue Amoeba) — simplest for v1
  - Building a Core Audio HAL plugin (AudioServerPlugin) — complex but removes third-party dependency
  - Using ScreenCaptureKit (macOS 13+) which can capture system audio without a virtual driver — modern and Apple-sanctioned, but relatively new API
- Target latency: < 20ms from audio event to DMX output
- Audio buffer management: 256–1024 sample frames at 44.1/48kHz
- Must handle hot-plug scenarios (audio device changes mid-show)

**Recommended approach for v1:** ScreenCaptureKit for system audio capture (no third-party dependency, Apple-supported), with fallback support for audio interface line-in via CoreAudio.

**Technology:** Swift, CoreAudio, AVFoundation, ScreenCaptureKit


### 3.2 Audio Analysis Core (Hybrid DSP + ML)

**What it does:** Extracts musical features from the raw audio stream in real time. This is the brain that separates this software from simple "sound-active" modes.

**Two-layer architecture:**

#### Layer 1 — Classical DSP (real-time, every frame)
Runs on every audio buffer with sub-10ms latency:

- **Beat detection** — onset detection via spectral flux, autocorrelation for tempo (BPM) estimation
- **Frequency band energy** — split spectrum into sub-bass, bass, mids, highs, presence; track energy per band
- **Spectral centroid & rolloff** — brightness/warmth indicators
- **RMS energy & dynamics** — overall loudness envelope, transient detection
- **Silence/speech detection** — distinguish music from spoken word or silence

**Libraries/frameworks to evaluate:** Accelerate (Apple's vDSP for FFT), Essentia (C++ audio analysis, extensive MIR features), aubio (lightweight beat/onset detection), or custom Swift DSP built on vDSP.

#### Layer 2 — ML Structure Analysis (slower, contextual)
Runs on longer windows (2–8 seconds) to understand song-level structure:

- **Segment classification** — intro, verse, chorus, bridge, build, drop, breakdown, outro
- **Energy curve prediction** — anticipate upcoming energy changes
- **Genre/mood estimation** — inform color palette and movement style choices
- **Transition detection** — identify DJ transitions, song changes, key moments

**ML approach:**
- Core ML models running on-device for inference (Apple Neural Engine / GPU)
- Training data: labeled music datasets (e.g., SALAMI for structure, Million Song Dataset features)
- Consider starting with pre-trained models and fine-tuning (e.g., adapting open-source MIR models to Core ML)
- Fallback to heuristic rules when ML confidence is low

**Output:** A continuously updated "musical state" object containing BPM, current beat position, energy level (0–1), spectral profile, detected segment type, and transition probability.


### 3.3 Decision Engine (Lighting AI)

**What it does:** Translates the musical state into lighting decisions. This is the "designer brain" — the part that makes choices a human lighting designer would make.

**Core responsibilities:**

- **Energy-to-intensity mapping** — higher musical energy → more saturated colors, faster movement, brighter output; low energy → subtle washes, slow fades
- **Beat-synchronized timing** — color changes, movement cues, and effects snap to beats and musical phrases (4-bar, 8-bar, 16-bar phrase awareness)
- **Segment-aware behavior:**
  - Verse → restrained, warm palette, minimal movement
  - Chorus → full saturation, coordinated movement, higher intensity
  - Build → progressive increase in rate, brightness, and color spread
  - Drop → maximum impact: fast color changes, full movement, strobe-eligible
  - Breakdown → strip back to single color or slow wash
  - Silence/speech → dim to static ambient look
- **Fixture coordination** — ensure all fixtures work together as a cohesive show, not independently
- **Randomization with taste** — introduce variation so the show doesn't look robotic, while keeping choices aesthetically coherent
- **Cooldown logic** — avoid constant maximum intensity; create contrast and dynamics

**Design pattern:** A rule-based engine with weighted randomization, parameterized by the active cue/palette. This is more predictable and debuggable than a pure ML approach for lighting decisions, while the ML handles the music understanding upstream.

**Configuration surface:** Users should be able to tune the "personality" — e.g., reactivity slider (subtle ↔ aggressive), color temperature preference, movement intensity cap.


### 3.4 Fixture Management

**What it does:** Models the physical lighting rig — what fixtures exist, what channels they use, what they can do.

**Key components:**

- **Fixture profiles** — define a fixture type's DMX channel layout (which channel controls pan, tilt, red, green, blue, dimmer, gobo, strobe, etc.). Support importing/exporting profiles. Consider compatibility with Open Fixture Library (open-fixture-library.org) JSON format.
- **Patching** — assign fixture instances to DMX start addresses (1–512 for a single universe)
- **Fixture groups** — group fixtures logically (e.g., "front wash," "back movers," "effect lights") for coordinated control
- **Attribute classification:**
  - *Dynamic attributes* — controlled autonomously by the decision engine (color, dimmer, pan, tilt, speed)
  - *Static attributes* — set once by the user and left alone (e.g., gobo selection, prism mode, DMX mode channel)
- **Layout/mapping** — define physical positions (linear, grid, arc) so pixel-mapped effects and movement patterns make spatial sense
- **Capability discovery** — the system should know what each fixture *can* do (has pan/tilt? has UV? how many color channels?) to make appropriate decisions

**Data storage:** JSON or SQLite for fixture profiles and stage configurations. Allow import/export for sharing.


### 3.5 Cue System

**What it does:** Provides a layer of user-defined creative direction on top of the autonomous engine.

**Key concepts:**

- **Color palettes** — curated sets of colors for different moods (warm wedding, high-energy club, cool corporate, custom). The decision engine picks from the active palette.
- **Scenes** — a snapshot of all fixture states; can be static (no music reactivity) or a starting point for autonomous behavior
- **Cues** — combine a color palette + behavior parameters + fixture group assignments. Examples: "Ceremony" (static warm white wash), "Dance Floor" (full autonomous, vivid palette), "Speeches" (dim ambient, no reactivity)
- **Cue triggering** — manual trigger via UI, MIDI input, or timeline-based (for events with a known schedule)
- **Cue transitions** — smooth crossfade between cues over configurable duration
- **Timeline mode** — optional: sequence cues on a timeline for events with a known run-of-show

**MIDI support:** Accept MIDI note/CC messages to trigger cues, override colors, or bump effects — useful for performers or operators who want tactile control.


### 3.6 DMX Output

**What it does:** Renders the final 512-channel DMX frame and sends it to the physical lights.

**Key considerations:**

- **USB-to-DMX protocol:** Support ENTTEC DMX USB Pro (and Pro Mk2) as the primary target. The ENTTEC Pro uses a serial protocol over FTDI USB — well-documented, with open-source driver examples.
- **Frame rate:** DMX standard is ~44Hz (one frame every ~23ms). The render loop should run at this rate.
- **Channel merging:** Combine autonomous output with any manual overrides, applying HTP (highest-takes-precedence) or LTP (latest-takes-precedence) merge rules.
- **Smoothing/interpolation:** Fade between DMX values to avoid harsh jumps, especially on dimmer and color channels. 16-bit fine channels for pan/tilt smoothness.
- **Blackout & safety:** Instant blackout function, panic button, and startup-safe defaults (all channels to 0 on launch).

**Future expansion:** ArtNet/sACN output over network for multi-universe support. Architect the DMX output layer as a protocol-agnostic interface so adding ArtNet later is straightforward.

---

## 4. Technology Stack

| Component | Technology | Rationale |
|---|---|---|
| Language | Swift | Native macOS, strong Apple framework integration, good performance |
| UI Framework | SwiftUI | Modern, declarative, macOS-native; pairs well with Combine for reactive data |
| Audio Capture | ScreenCaptureKit + CoreAudio | System audio loopback without third-party drivers |
| DSP | Accelerate (vDSP) + custom Swift | Apple-optimized FFT and vector math, minimal dependencies |
| ML Inference | Core ML | On-device, leverages Neural Engine, no cloud dependency |
| Data Storage | SQLite (via SwiftData or GRDB) | Fixture profiles, cue library, settings |
| DMX Protocol | Custom Swift serial driver (IOKit / ORSSerialPort) | Direct FTDI communication with ENTTEC dongles |
| MIDI | CoreMIDI | Native macOS MIDI support for external controllers |
| Build / Distribution | Xcode, Swift Package Manager | Standard macOS app toolchain; future Mac App Store or direct distribution |

---

## 5. Development Phases

### Phase 1 — Audio Analysis Proof of Concept (Weeks 1–4)
**Goal:** Capture system audio and visualize real-time musical features in a debug UI.

- Set up Xcode project, SwiftUI app scaffold
- Implement ScreenCaptureKit audio capture
- Build DSP pipeline: FFT, beat detection, energy bands, onset detection
- Create a debug visualization (waveform, spectrum, beat indicator, energy meter)
- Validate latency is < 20ms end-to-end

**Milestone:** A macOS app that listens to any music playing on the system and shows real-time beat markers, energy level, and spectral breakdown.


### Phase 2 — DMX Output & Basic Fixture Control (Weeks 5–8)
**Goal:** Send DMX data to real lights based on audio analysis.

- Implement ENTTEC DMX USB Pro serial protocol
- Build fixture profile data model (channel map, attribute types)
- Create basic patching UI (add fixtures, assign addresses)
- Wire audio energy → dimmer, spectral bands → RGB color
- Simple beat-synced effects (strobe on beat, color change every 4 bars)

**Milestone:** Lights physically respond to music with basic but correctly timed color and intensity changes.


### Phase 3 — Intelligent Decision Engine (Weeks 9–14)
**Goal:** Move beyond simple mapping to intelligent, coordinated lighting design.

- Implement song structure detection (ML model training + Core ML integration)
- Build the decision engine rules (segment-aware behavior, phrase-aligned changes)
- Add fixture grouping and coordinated output
- Implement color palette system
- Add spatial awareness (fixture layout → directional effects, chases, waves)
- Tune the "personality" — make it look like a real lighting designer, not a robot

**Milestone:** The software creates a compelling, varied light show that responds to musical structure — builds get brighter, drops hit hard, verses breathe, silence dims.


### Phase 4 — Cue System & User Interface (Weeks 15–20)
**Goal:** Give users creative control over the autonomous system.

- Build cue creation/editing UI (palette picker, parameter sliders, group assignments)
- Implement cue triggering (manual, MIDI)
- Add scene snapshots (static looks)
- Cue crossfade engine
- Fixture profile editor UI (create/import/export profiles)
- Stage layout editor (visual fixture positioning)
- Settings and preferences

**Milestone:** A user can configure their rig, build cues for different event moments, and switch between them during a show.


### Phase 5 — Polish, Testing & Distribution Prep (Weeks 21–26)
**Goal:** Production-ready quality for real-world use and commercial release.

- Extensive real-world testing across music genres and fixture types
- Performance optimization (CPU/GPU usage, thermal management for long shows)
- Error handling and recovery (USB disconnect, audio source changes)
- Crash recovery and auto-save
- Open Fixture Library integration
- App icon, onboarding flow, documentation
- Licensing / DRM strategy
- Code signing, notarization, distribution packaging (direct or Mac App Store)
- Beta testing program

**Milestone:** v1.0 release candidate ready for distribution.

---

## 6. AI-Assisted Development Strategy

Since this is a solo build with AI-assisted coding, here's how to maximize leverage:

- **Claude Code / Cursor** for day-to-day Swift development — especially useful for boilerplate (CoreAudio setup, serial protocol implementation, SwiftUI views), and for translating DSP algorithms from academic papers into Swift
- **ML model development** — use AI to help architect Core ML model pipelines, write training scripts (likely Python for training, then convert to Core ML), and debug inference integration
- **DSP algorithm implementation** — beat detection and onset detection algorithms are well-documented but tricky to implement correctly; AI can help translate reference implementations (often in Python/C++) to Swift/Accelerate
- **Testing** — generate test fixtures, mock DMX output, simulate various audio scenarios
- **Documentation** — API docs, user manual, architecture decision records

**Where AI won't help much:** Tuning the decision engine's "taste" — making the lighting look *good* requires iterating with real music and real lights. This is the artistic core that needs human judgment and lots of live testing.

---

## 7. Key Technical Risks

| Risk | Impact | Mitigation |
|---|---|---|
| **macOS audio loopback reliability** | System audio capture could break across macOS versions | Use Apple-sanctioned ScreenCaptureKit; monitor macOS betas; support line-in as fallback |
| **Beat detection accuracy** | Poor beat tracking makes the whole show look bad | Use multiple detection algorithms and vote; allow manual BPM override/tap-tempo |
| **Decision engine "taste"** | Lighting looks robotic, repetitive, or chaotic | Invest heavily in testing with real music; parameterize everything; get feedback from working LDs |
| **ENTTEC driver stability** | USB serial can be flaky on macOS (especially with sleep/wake) | Implement robust reconnection logic; monitor FTDI driver health |
| **ML model training data** | Song structure detection needs labeled data | Start with open datasets (SALAMI, Harmonix Set); augment with manual labeling; heuristic fallback |
| **Real-time performance** | Audio analysis + ML + DMX rendering must all stay within frame budget | Profile early and often; offload ML to Neural Engine; keep DSP on CPU via Accelerate |
| **App Store restrictions** | ScreenCaptureKit requires special entitlements; USB access may be sandboxing-unfriendly | Plan for direct distribution (outside App Store) as primary path; notarize for Gatekeeper |

---

## 8. Competitive Landscape & Differentiation

| Product | Approach | Limitation Your Software Solves |
|---|---|---|
| **MaestroDMX** | Dedicated hardware box | Requires purchasing hardware; limited to 1 universe; no extensibility |
| **SoundSwitch** | DJ software plugin | Requires Denon/Engine DJ ecosystem; pre-analysis of tracks; subscription |
| **Rekordbox Lighting** | Pioneer DJ integration | Pioneer ecosystem lock-in; needs RB-DMX1 hardware; laptop required |
| **QLC+** | Open-source DMX controller | No autonomous/intelligent mode; manual programming only |
| **Your Software** | Native macOS app, autonomous AI | No hardware dependency; works with any audio source; one-time purchase; extensible |

---

## 9. Estimated Effort

For a solo developer working full-time with heavy AI-assisted coding:

- **Phase 1 (Audio Analysis):** 3–4 weeks
- **Phase 2 (DMX Output):** 3–4 weeks
- **Phase 3 (Decision Engine):** 5–6 weeks — *the hardest phase; most iteration*
- **Phase 4 (Cue System & UI):** 5–6 weeks
- **Phase 5 (Polish & Ship):** 5–6 weeks
- **Total: ~6 months to v1.0**

With part-time effort, estimate 9–12 months.

---

## 10. Open Questions for Future Decisions

- **Naming & branding** — project name, visual identity (needed before distribution)
- **Pricing model** — one-time purchase vs. subscription vs. freemium with pro features
- **Multi-universe support** — when to add ArtNet/sACN (v1.5? v2?)
- **Fixture library strategy** — build your own vs. integrate Open Fixture Library vs. community-contributed
- **Remote control** — companion iOS app for wireless cue triggering? (v2 feature)
- **Plugin / extension API** — allow third-party effects or analysis modules? (v2+)

---

*Document generated March 24, 2026. This is a living document — update as decisions are made and the project evolves.*
