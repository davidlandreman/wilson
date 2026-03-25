# Decision Engine Architecture

The decision engine transforms `MusicalState` into per-fixture lighting output (`FixtureState`). It is the core creative system — the part that makes Wilson produce light shows rather than just sound-activated flashing.

The engine operates as a layered system where each layer runs at a different time scale, from fast per-frame attribute calculation down to slow emotional state tracking. The separation of time scales is what gives the output a sense of intentionality: behaviors react instantly to beats while the overall mood, grouping, and behavior selection evolve gradually, creating the perception of a curated show.

---

## Pipeline Position

```
AudioCaptureService → AudioAnalysisService → DecisionEngineService → DMXOutputService
     (48kHz audio)      (MusicalState ~47Hz)    (FixtureState ~47Hz)   (DMX frames ~44Hz)
                                                        │
                                                        └──→ VirtualOutputService
                                                              (SceneKit rendering)
```

The engine receives `MusicalState` at ~47Hz via the `onMusicalStateUpdate` callback wired in `AppState`. It also receives the current fixture list from `FixtureManager` and the active `ColorPalette` from `CueService`. It outputs a `[UUID: FixtureState]` dictionary consumed by both the DMX and virtual output services.

---

## Layered Architecture

```
Layer            Rate            Responsibility
─────────────────────────────────────────────────────────────────
Behaviors        ~47Hz           Per-frame attribute calculation
Choreographer    ~1-4Hz          Reassign behaviors, regroup fixtures
MoodEngine       ~0.1-0.5Hz      Emotional state from sustained features
CueService       Event-driven    User-triggered palette/parameter changes
```

Each frame, the engine executes this sequence:

1. **Tick clock** — update monotonic time and delta
2. **Update mood** — EMA-smooth emotional dimensions from musical state
3. **Evaluate choreographer** — check if scenario changed or phrase boundary hit; if so, reassign behaviors and fixture groups
4. **Sync bar counter** — pass downbeat count from MoodEngine to Choreographer for phrase tracking
5. **Resolve palette** — compute warm/cool bias from mood + musical key, wrap raw `ColorPalette` into `ResolvedPalette`
6. **Run behaviors** — for each active `BehaviorSlot`, evaluate its behavior against its assigned fixture group
7. **Composite** — merge all behavior outputs using HTP (highest takes precedence)
8. **Apply movement limiting** — slew-rate limit pan/tilt to prevent jerky motion
9. **Apply silence safety** — force dimmer to 0 during silence
10. **Apply overrides** — manual per-fixture overrides bypass all computed state

---

## Mood Engine

**File:** `Wilson/Services/DecisionEngine/MoodEngine.swift`

The MoodEngine tracks five emotional dimensions, each derived from a specific musical feature and smoothed with an exponential moving average (EMA) at a different time constant. The different time constants are deliberate — excitement should respond quickly to a drum fill, while valence (happy/sad from key detection) should change slowly because musical key perception is inherently gradual.

### Emotional Dimensions

| Dimension | Musical Source | EMA Time Constant | Range |
|-----------|---------------|-------------------|-------|
| `excitement` | `energy` (60%) + normalized BPM (40%) | 2 seconds | 0 = calm, 1 = energetic |
| `valence` | `detectedKey` major/minor | 8 seconds | 0 = sad/dark, 1 = happy/bright |
| `brightness` | `spectralCentroid` (500–5000 Hz → 0–1) | 3 seconds | 0 = dark/heavy, 1 = bright/airy |
| `chaos` | `spectralFlatness` | 4 seconds | 0 = ordered/tonal, 1 = chaotic/noisy |
| `intensity` | `energy` (raw) | 2 seconds | 0 = quiet, 1 = loud |

The EMA alpha is computed frame-rate-independently: `alpha = 1 - exp(-deltaTime / timeConstant)`. This ensures consistent smoothing regardless of actual frame timing.

### Valence and Key Confidence

Valence only tracks toward major/minor targets when `keyConfidence > 0.4`. Below that threshold, it drifts slowly (10x slower) toward neutral (0.5). This prevents uncertain key detection from whipsawing the mood.

### Energy Trajectory

The engine maintains a windowed history of energy values (~100 frames, ~2 seconds at 47Hz) and computes the trajectory by comparing the average of the most recent 20 frames against the oldest 20 frames:

| Condition | Trajectory |
|-----------|-----------|
| Recent avg > older avg + 0.1 | `.building` |
| Recent avg < older avg - 0.1 | `.declining` |
| Recent avg > 0.6 (but stable) | `.sustaining` |
| Otherwise | `.stable` |

Energy trajectory is the primary signal the Choreographer uses to classify scenarios, since song segment detection (Core ML) is not yet implemented.

### Bar Counter

The MoodEngine counts downbeats (`musicalState.isDownbeat`) to maintain a running bar counter. This counter is synced to the Choreographer for phrase boundary detection (every 4 bars = 1 phrase).

---

## Color Engine

**File:** `Wilson/Services/DecisionEngine/ColorEngine.swift`

The ColorEngine transforms a raw `ColorPalette` (user-curated list of `LightColor` values) into a `ResolvedPalette` with mood-influenced warm/cool bias.

### Warm/Cool Bias Computation

The bias is a blend of two signals:

1. **Spectral centroid** (via `mood.brightness`) — bass-heavy music shifts cool, treble-heavy shifts warm
2. **Musical key warmth** (when `keyConfidence > 0.4`) — keys are mapped to warm/cool via the circle-of-fifths color wheel

The blend is 60% centroid, 40% key warmth. An additional ±5% nudge is applied for major (warmer) vs minor (cooler) keys.

### Key-to-Color Mapping

**File:** `Wilson/Models/MusicalKey+Color.swift`

Musical keys are mapped to hue angles using the circle of fifths projected onto the color wheel. Musically related keys (a fifth apart) get adjacent colors:

```
Key:  C    G    D    A    E    B    F#   Db   Ab   Eb   Bb   F
Hue:  0°   30°  60°  90°  120° 150° 180° 210° 240° 270° 300° 330°
      red  ---  yel  ---  grn  ---  cyn  ---  blu  ---  pur  ---
```

This is inspired by Scriabin's synesthetic color mappings but adapted to follow the circle of fifths, which ensures that keys commonly used together in music (C and G, A and E, etc.) get harmonious adjacent colors.

The `warmth` property uses a cosine function to map hue to a 0–1 warm/cool scale: 0° (C, red) = warmest, 180° (F#, cyan) = coolest.

### Palette Resolution

The `ResolvedPalette` struct provides structured access to palette colors:

- **`.primary()`** — first palette color, warm-shifted
- **`.secondary()`** — middle palette color (maximum hue distance from primary)
- **`.accent()`** — last palette color
- **`.colorForIndex(i)`** — wrapping access with warm shift applied
- **`.interpolated(from:to:t)`** — smooth blend between two palette entries

All accessors apply the warm/cool bias via `warmCoolShifted()`, which shifts red up and blue down (or vice versa) by ±15% at maximum bias.

### Default Palette

When no user palette is active, the engine uses a built-in four-color palette: blue, purple, orange-red, teal. This ensures the engine always produces colored output even before the user configures palettes.

---

## Behavior System

### Behavior Protocol

**File:** `Wilson/Services/DecisionEngine/Behavior.swift`

```swift
protocol Behavior: Sendable {
    static var id: String { get }
    var controlledAttributes: Set<FixtureAttribute> { get }
    func evaluate(fixtures: [StageFixture], context: BehaviorContext) -> [UUID: [FixtureAttribute: Double]]
}
```

Behaviors are **stateless structs**. All temporal information — beat phase, bar phase, time, mood — comes through `BehaviorContext`. This design makes behaviors:

- Trivially `Sendable` (Swift 6 strict concurrency)
- Easy to test (pure function of inputs)
- Hot-swappable (the Choreographer replaces them without cleanup)
- Composable (multiple behaviors can run simultaneously on the same fixtures)

### BehaviorContext

**File:** `Wilson/Services/DecisionEngine/BehaviorContext.swift`

Every behavior receives the same context each frame:

| Field | Source | Purpose |
|-------|--------|---------|
| `musicalState` | AudioAnalysisService | Raw musical features |
| `moodState` | MoodEngine | Smoothed emotional dimensions |
| `palette` | ColorEngine | Resolved colors with warm/cool bias |
| `beat` | BeatContext | Structured beat/bar/phrase timing |
| `time` | EngineClock | Monotonic seconds since start |
| `deltaTime` | EngineClock | Frame duration (~0.021s) |
| `reactivity` | Active Cue | 0–1, how aggressive effects should be |
| `movementIntensity` | Active Cue | 0–1, how much pan/tilt movement |
| `parameters` | BehaviorSlot | Per-slot speed, intensity, offset, variant |

### BeatContext

Derived from `MusicalState`, provides hierarchical timing:

- **`phase`** (0→1) — within current beat
- **`barPhase`** (0→1) — within current bar (4 beats)
- **`phrasePhase`** (0→1) — within current phrase (4 bars = 16 beats)
- **`isBeat`**, **`isDownbeat`**, **`isPhraseBoundary`** — edge triggers

The `phrasePhase` is computed from the bar counter: `(barInPhrase + barPhase) / 4.0`, giving behaviors a smooth 16-beat cycle for longer-period effects.

### BehaviorParameters

Each `BehaviorSlot` carries parameters that modify how a behavior runs:

- **`speed`** — multiplier on timing (2.0 = twice as fast)
- **`intensity`** — multiplier on output strength (0.5 = half brightness)
- **`offset`** — phase offset (0–1) for staggering across groups
- **`variant`** — sub-mode selector (e.g., ColorWash variant 0 = unison, variant 1 = rainbow)

---

## Behavior Catalog

All behaviors live under `Wilson/Services/DecisionEngine/Behaviors/`.

### Dimmer Behaviors

#### BeatPulseBehavior

Controls: `.dimmer`

Full brightness on beat, decays between beats. The decay curve adapts to the music:
- **High energy / high crest factor** → cubic decay `(1 - phase)³` — sharp, punchy
- **Low energy** → exponential decay `e^(-4·phase)` — softer, more gradual

The adaptive decay is what makes the pulse feel "right" for different genres — a four-on-the-floor house track gets snappy strobing while a ballad gets gentle pulsing.

#### BreatheBehavior

Controls: `.dimmer`

Smooth sinusoidal dimming with a minimum brightness of 15% (never fully dark). Each fixture gets a phase offset based on its `trussSlot`, creating a visible wave effect across the lighting truss. The period is tied to BPM: one full breath cycle per 2 bars (8 beats).

#### ChaseBehavior

Controls: `.dimmer`

Sequential fixture activation along `trussSlot` ordering. A Gaussian window (not a hard step) moves across the fixtures for smooth spatial blending. Speed adapts to energy:
- `excitement > 0.6` → one chase per beat
- Otherwise → one chase per bar

Direction alternates each bar to prevent visual monotony.

#### StrobeBehavior

Controls: `.dimmer`, `.strobe`

Onset-reactive: only activates when `isOnset` is true AND energy exceeds a threshold. The threshold is gated by `reactivity` — high reactivity means more strobing, low reactivity means only the strongest transients trigger it. Uses the fixture's native `.strobe` channel if available, otherwise rapid dimmer toggling.

#### BlackoutAccentBehavior

Controls: `.dimmer`

Monitors for imminent drops via `transitionProbability > 0.7` combined with `.building` energy trajectory. Triggers a momentary blackout (~80ms) just before the drop for maximum impact. Self-limits to only fire once per transition.

### Color Behaviors

#### ColorWashBehavior

Controls: `.red`, `.green`, `.blue`, `.white`

Slowly rotates through palette colors using sinusoidal interpolation for organic-feeling transitions. The base cycle period is one 4-bar phrase.

Two variants:
- **Variant 0 (unison)**: all fixtures show the same color, rotating together
- **Variant 1 (rainbow)**: each fixture is offset by `index / count`, spreading the full palette across the truss simultaneously

#### SpectralColorBehavior

Controls: `.red`, `.green`, `.blue`, `.white`

Maps frequency band energy to palette color blending:
- **Low frequencies** (subBass + bass) → `palette.primary()` (typically warmer)
- **Mid frequencies** → `palette.secondary()`
- **High frequencies** (highs + presence) → `palette.accent()` (typically cooler)

The weights are normalized so the output is always a valid color blend. The result is scaled by overall energy for reactivity — quiet passages get more muted colors.

#### ColorSplitBehavior

Controls: `.red`, `.green`, `.blue`, `.white`

Assigns different palette colors to different fixtures simultaneously. Colors are distributed evenly by fixture index: with a 4-color palette and 8 fixtures, each pair of fixtures shares a palette color. This creates intentional color contrast across the stage using the user's curated palette relationships.

### Movement Behaviors

#### PanSweepBehavior

Controls: `.pan`, `.panFine`

Sinusoidal horizontal sweep. Default period is one full sweep per 2 bars. Amplitude scales with `movementIntensity` (±30% of range at maximum). Each fixture gets a small phase offset (30% of the cycle spread across fixtures) to create a fan-out effect rather than robotic unison.

Fine pan channel is populated when available for sub-step smooth movement.

#### TiltBounceBehavior

Controls: `.tilt`, `.tiltFine`

Exponential "nod": snaps down on beat, smoothly returns to center between beats. Amplitude scales with both energy and `movementIntensity`. The exponential decay (`e^(-3·phase)`) gives a natural-looking bounce that's fast at the start and slow at the end.

#### MovementPatternBehavior

Controls: `.pan`, `.tilt`, `.panFine`, `.tiltFine`

Parametric movement using Lissajous curves. Four patterns selected by `variant`:

| Variant | Pattern | Pan Formula | Tilt Formula |
|---------|---------|------------|-------------|
| 0 | Sweep | `sin(phase)` | constant 0.5 |
| 1 | Figure-8 | `sin(phase)` | `sin(2·phase)` — 2:1 Lissajous |
| 2 | Circle | `sin(phase)` | `cos(phase)` |
| 3 | Ballyhoo | `sin(phase + sin(0.3·phase)·0.5)` | `sin(1.7·phase + cos(0.5·phase)·0.4)` |

The **ballyhoo** pattern uses incommensurate frequencies and phase modulation to create organic, non-repeating motion that looks hand-operated rather than mechanical.

---

## Fixture Grouping

**File:** `Wilson/Services/DecisionEngine/FixtureGroup.swift`

Fixtures are dynamically grouped, and different groups can run different behaviors simultaneously. This is what enables fixtures to "work together" while also "working independently" — one group might be doing a color wash while another chases.

### Group Roles

Each group is tagged with a role that hints at its intended use:

- **`.primary`** — main wash/color fixtures
- **`.accent`** — highlight/contrast fixtures
- **`.movement`** — moving heads doing sweeps
- **`.effect`** — strobes, special effects
- **`.all`** — everything together (unison moments)

### Grouping Strategies

The `GroupingEngine` implements five strategies:

#### All Unison
Every fixture in one group. Used for maximum-impact moments (drops, chorus peaks, builds). All fixtures do the same thing simultaneously.

#### Capability Split
Groups by what fixtures can physically do: moving heads (have `.pan`/`.tilt`) vs. color-only (have RGB but no movement) vs. dimmer-only. This lets the Choreographer assign movement behaviors only to fixtures that can actually move, while color fixtures do wash effects.

Falls back to All Unison if all fixtures have the same capabilities.

#### Spatial Split
Divides fixtures into left/right halves by `position.x`. Used for alternating effects where the two halves contrast — different colors, different timing offsets, or different behaviors entirely.

#### Alternating
Even/odd `trussSlot` indices create two interleaved groups. Visually similar to spatial split but creates a "every other fixture" pattern rather than left/right. Good for rapid contrast effects.

#### Solo + Background
The center fixture (by `trussSlot`) becomes a solo group; everything else is background. Used during declining energy to create visual focus — the solo runs at higher intensity with different behavior parameters while the background dims down.

---

## Choreographer

**File:** `Wilson/Services/DecisionEngine/Choreographer.swift`

The Choreographer is the meta-decision maker — it decides **which behaviors run on which groups with what parameters**, while the behaviors themselves decide **what the fixtures actually do each frame**.

### When the Choreographer Acts

The Choreographer is evaluated every frame but only makes changes when:

1. **Scenario changes** AND at least 4 seconds have elapsed since the last change (cooldown prevents rapid flipping between scenarios at energy boundaries)
2. **Phrase boundaries** (every 4 bars) when `mood.chaos > 0.4` AND cooldown has elapsed (variety injection — chaotic music gets more frequent visual changes)

### Scenario Classification

The Choreographer classifies the current moment into one of six scenarios based on the MoodEngine's emotional state:

```
Energy Trajectory    →  Scenario
─────────────────────────────────
.building            →  building
.declining           →  declining
.sustaining          →  peakDrop       (if excitement > 0.7)
.sustaining          →  highEnergy     (otherwise)
.stable              →  highEnergy     (if intensity > 0.65)
.stable              →  mediumEnergy   (if intensity > 0.35)
.stable              →  lowEnergy      (otherwise)
```

### Scenario → Behavior + Grouping Mapping

Each scenario configures a complete set of behavior slots and fixture groups:

#### Low Energy
- **Grouping:** All Unison
- **Behaviors:** BreatheBehavior (slow, 70% intensity) + ColorWashBehavior (slow, 80% intensity)
- **Movement:** CirclePattern (slow, 40% intensity) if movers present
- **Character:** Gentle, ambient, meditative

#### Medium Energy
- **Grouping:** Alternates between Capability Split and Spatial Split (variety)
- **Behaviors:** BeatPulseBehavior (70% intensity) + ColorWashBehavior or ColorSplitBehavior (alternates)
- **Movement:** PanSweep (slow) for movers
- **Character:** Rhythmic but restrained, visible structure

#### High Energy
- **Grouping:** Cycles through Spatial Split → Alternating → Capability Split
- **Behaviors:** BeatPulseBehavior (100%) + SpectralColorBehavior or ColorWashBehavior (rainbow, alternates)
- **Movement:** PanSweep + TiltBounce for movers
- **Character:** Full intensity, reactive, dynamic grouping

#### Building
- **Grouping:** All Unison (cohesion during buildup)
- **Behaviors:** BeatPulseBehavior (90%, slightly fast) + ColorWashBehavior (fast, 100%) + BlackoutAccentBehavior
- **Movement:** Figure-8 pattern (fast, 90% intensity) for movers
- **Character:** Intensifying, anticipatory, unified

#### Peak/Drop
- **Grouping:** Alternating (interleaved groups)
- **Behaviors:** Alternates between ChaseBehavior and BeatPulseBehavior + StrobeBehavior. Always SpectralColorBehavior.
- **Movement:** Ballyhoo pattern (fast, 100% intensity) for movers
- **Character:** Maximum energy, chaotic, spectacular

#### Declining
- **Grouping:** Solo + Background
- **Behaviors:** BreatheBehavior + ColorWashBehavior, with the solo fixture at higher intensity (90%) and the background subdued (40%)
- **Movement:** Slow PanSweep for solo mover only
- **Character:** Fading, contemplative, visual focus

### Variety Index

Within a scenario, the `varietyIndex` counter increments on each phrase boundary change. This selects between sub-variants: different grouping strategies, different color behaviors (wash vs. split vs. spectral), different movement patterns. The variety index resets to 0 when the scenario itself changes. This ensures that even within a sustained high-energy section, the visual presentation evolves.

---

## Compositing

When multiple behavior slots write the same attribute for the same fixture, the engine uses **HTP (Highest Takes Precedence)** — the maximum value wins. This is the standard compositing rule in professional lighting:

```swift
composited[fixtureID]?[attr] = max(existing, weighted)
```

Each slot's output is also scaled by its `weight` (0–1) before compositing. Currently all slots snap to weight 1.0; crossfade weight interpolation is a future enhancement.

HTP was chosen over weighted averaging because:
- It prevents behaviors from "fighting" (dimmer averaging creates muddy results)
- It matches industry-standard lighting console behavior
- A strobe flash always punches through a breathe cycle (desired behavior)

---

## Movement Limiting

**File:** `Wilson/Services/DecisionEngine/MovementLimiter.swift`

Pan and tilt values pass through a slew-rate limiter before reaching the output. The limiter caps the rate of change to `0.5` units per second (normalized 0–1 range), meaning a full end-to-end sweep takes at minimum 2 seconds.

This serves two purposes:
1. **Prevents mechanical damage** on real moving heads — motors have physical speed limits
2. **Smooths visual output** — even if a behavior jumps from one position to another, the fixture glides there

The limiter compares the current target against the previous frame's output and caps the delta per frame.

---

## Silence Safety

When `musicalState.isSilent` is true, the engine forces all fixture dimmers to 0 regardless of behavior output. This is a hard safety override — silence means the audio source has stopped and lights should go dark rather than freeze in their last state.

---

## Manual Overrides

Per-fixture overrides (`setOverride` / `removeOverride`) bypass the entire behavior pipeline. When an override is set for a fixture ID, that fixture's state comes directly from the override, ignoring all behaviors, compositing, and silence safety. This allows manual control of individual fixtures during a show.

---

## Observable Debug State

The engine exposes several properties for debug UI:

- **`currentMood: MoodState`** — all five emotional dimensions and energy trajectory
- **`activeGroups: [FixtureGroup]`** — current fixture grouping
- **`activeSlotDescriptions: [String]`** — human-readable list of active behavior→group assignments (e.g., `"beatPulse → 3A2F"`)

---

## File Map

```
Wilson/Services/DecisionEngine/
├── DecisionEngineService.swift      # Orchestrator — the main update loop
├── EngineClock.swift                # Monotonic time tracking
├── MoodState.swift                  # MoodState struct + EnergyTrajectory enum
├── MoodEngine.swift                 # EMA tracking of emotional dimensions
├── ColorEngine.swift                # Palette resolution + key-color bias
├── MovementLimiter.swift            # Slew-rate limiting for pan/tilt
├── Choreographer.swift              # Scenario classification + behavior assignment
├── Behavior.swift                   # Behavior protocol
├── BehaviorSlot.swift               # Behavior + group + weight + parameters
├── BehaviorContext.swift            # BehaviorContext, BeatContext, ResolvedPalette
├── FixtureGroup.swift               # FixtureGroup struct + GroupingEngine
└── Behaviors/
    ├── BeatPulseBehavior.swift       # Beat-reactive dimmer with adaptive decay
    ├── BreatheBehavior.swift         # Sine-wave dimming with spatial wave
    ├── ChaseBehavior.swift           # Sequential activation along truss
    ├── StrobeBehavior.swift          # Onset-reactive flash
    ├── BlackoutAccentBehavior.swift  # Pre-drop momentary blackout
    ├── ColorWashBehavior.swift       # Palette rotation (unison or rainbow)
    ├── SpectralColorBehavior.swift   # Frequency bands → palette color blend
    ├── ColorSplitBehavior.swift      # Different palette colors per fixture
    ├── PanSweepBehavior.swift        # Sinusoidal horizontal sweep
    ├── TiltBounceBehavior.swift      # Beat-reactive tilt nod
    └── MovementPatternBehavior.swift # Lissajous patterns (sweep/figure-8/circle/ballyhoo)

Wilson/Models/
├── LightColor+Interpolation.swift   # HSB conversion, lerp, warm/cool shift
└── MusicalKey+Color.swift           # Circle-of-fifths → color wheel mapping
```

---

## Future Work

### Song Segment Detection
When Core ML-based segment classification is implemented (`MusicalState.segment`), the Choreographer can map segments directly to scenarios instead of inferring them from energy trajectory. The current trajectory-based approach works well but segment labels will enable more precise transitions (e.g., distinguishing a verse from a breakdown, which may have similar energy but different visual treatment).

### Crossfade Weight Management
Currently all behavior slots snap to weight 1.0 when assigned. Implementing gradual crossfades (outgoing slot fades 1.0→0.0 while incoming fades 0.0→1.0 over a configurable beat count) will make scenario transitions smoother.

### Additional Behaviors
The behavior protocol makes it straightforward to add new effects:
- **GoboWheelBehavior** — rotate gobo wheels on fixtures that support `.gobo`
- **PrismBehavior** — engage prism on high energy moments
- **ZoomBehavior** — zoom in on beats, zoom out between
- **ColorWheelBehavior** — for fixtures with physical color wheels instead of RGB mixing

### Cue-Driven Behavior Selection
Currently the Choreographer makes all behavior decisions autonomously. A future enhancement could let Cues specify preferred behaviors and grouping strategies, giving users direct creative control while still allowing the engine to handle timing and musical reactivity.
