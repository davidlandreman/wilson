---
name: generate-light-script
description: Generate a .wilsonscript JSON file that pre-choreographs a DMX light show for a specific song
user-invocable: true
tools:
  - WebSearch
  - WebFetch
  - Write
---

# Generate Light Script for Wilson

You are generating a `.wilsonscript` JSON file that pre-choreographs a complete light show for a specific song. This file will be loaded into Wilson, an autonomous music-reactive DMX lighting controller, and will begin playback automatically when it detects the song starting.

## Step 1: Research the Song

Use web search to find the following about the requested song:

- **BPM** (tempo)
- **Musical key** (e.g. C minor, A major)
- **Genre/subgenre** (e.g. house, rock, pop ballad)
- **Song structure with timestamps** — intro, verse, pre-chorus, chorus, bridge, build, drop, breakdown, outro. Convert timestamps to bar numbers using the BPM.
- **Notable moments** — big hits, drops, breakdowns, vocal entries, drum fills, key changes, tempo changes, silence gaps
- **Energy arc** — how intensity builds and releases across the song
- **Duration** in seconds (convert to total bars)

**Converting timestamps to bars:**
```
bar = floor(timestamp_seconds * BPM / 60 / beats_per_bar) + 1
```
For 4/4 time at 128 BPM: bar = floor(seconds * 128 / 60 / 4) + 1

## Step 2: Understand the Rig

The venue has **5 fixtures** in two categories:

### 4x MINGJIE 60W Spot Moving Heads (11-channel mode)
- **Capabilities:** Pan/tilt (with fine control), color wheel (8 colors), gobo wheel, shutter strobe, dimmer
- **Role in scripts:** `"movement"` group. These are your movers — they do sweeps, patterns, and position changes.
- **Color wheel colors:** White, Red, Yellow-Green, Blue, Green, Orange, Pink, Sky Blue. The system maps RGB palette values to the nearest color wheel slot automatically.
- **Gobo options:** Open (default), Radial Dots, Triangle, Hexagon, Swirl, Jigsaw. Controlled via gobo attribute in scene snapshots, not via behaviors.

### 1x Betopper LF4808 Matrix Strobe (15-channel mode)
- **Capabilities:** Master dimmer, RGBW color, hardware strobe, RGB patterns, white bar patterns, background color
- **Role in scripts:** `"primary"` or `"effect"` group. This is your blinder/wash — it does color washes, beat pulses, and strobe effects.
- **Blinder response curve:** Above 70% dimmer it fires a full white+color flash. 15-70% is the decay zone. Below 15% is a soft color tail. This means `beatPulse` at high intensity creates dramatic flash-to-black blinder hits.
- **Color snapping:** The fixture snaps colors to bold saturated primaries automatically. Pastel palettes still produce punchy output.

### Grouping Strategies

When `"capabilitySplit"` is used (the most common), the system automatically creates:
- `"movement"` group = the 4 movers
- `"primary"` group = the Betopper (color/wash fixtures)
- `"effect"` group = dimmer-only fixtures (if any)

Other strategies:
| Strategy | What it does |
|---|---|
| `"allUnison"` | All 5 fixtures in one `"all"` group — synchronized moments |
| `"capabilitySplit"` | Movers vs color vs effect — most versatile, use as default |
| `"moverPairSplit"` | Splits the 4 movers into 2 pairs + keeps Betopper separate |
| `"spatialSplit"` | Left vs right halves — `"primary"` and `"accent"` groups |
| `"alternating"` | Even/odd fixtures — `"primary"` and `"accent"` groups |
| `"soloBackground"` | Center fixture solos, rest as background |

## Step 3: Choose Behaviors

Each cue assigns behaviors to group roles. Here are all available behaviors and when to use them:

### Dimmer Behaviors
| ID | What it does | Best for |
|---|---|---|
| `"beatPulse"` | Flash on beat with decay. Variant 0=every beat, 1=alternating (even beats only, use offset:1.0 for odd) | Verses, choruses, drops — the workhorse |
| `"breathe"` | Smooth sinusoidal pulsing | Intros, breakdowns, ambient sections |
| `"chase"` | Sequential fixture activation along truss | Builds, transitions, high-energy sections |
| `"blackoutAccent"` | Brief blackout on phrase boundaries for drama | Builds, pre-drops |

### Color Behaviors
| ID | What it does | Best for |
|---|---|---|
| `"colorWash"` | Slowly rotates through palette colors. Variant 0=unison, 1=rainbow spread per fixture | Everything — primary color behavior |
| `"colorSplit"` | Each fixture gets a different palette color | Contrast moments, visual variety |
| `"spectralColor"` | Colors react to frequency content of audio | High-energy reactive sections |

### Movement Behaviors (movers only)
| ID | What it does | Best for |
|---|---|---|
| `"movementPattern"` | Programmed patterns. Variant 0=sweep, 1=figure8, 2=circle, 3=ballyhoo | Main movement behavior |
| `"panSweep"` | Horizontal sweep synced to bars | Verses, medium energy |
| `"tiltSweep"` | Vertical sweep | Alternative to panSweep |
| `"tiltBounce"` | Tilt bounces on beats | Pair with panSweep for 2D motion |
| `"randomLook"` | Snap to random positions on beats | High energy, chaotic moments |

### Effect Behaviors
| ID | What it does | Best for |
|---|---|---|
| `"strobe"` | Hardware strobe. Variant 0=onsetReactive, 1=halfTime, 2=subdivision, 3=punchy (downbeat only) | Drops, peaks, builds |

### Behavior Parameters
Every behavior assignment accepts these optional parameters:
- `speed` (default 1.0) — timing multiplier. 0.5 = half speed, 2.0 = double speed
- `intensity` (default 1.0) — output strength 0.0-1.0
- `offset` (default 0.0) — phase offset for staggering groups
- `variant` (default 0) — sub-mode selector (see tables above)
- `weight` (default 1.0) — blend weight when multiple behaviors overlap

## Step 4: Design the Color Palette Arc

Colors should evolve with the song's emotional arc. Each cue can override the palette.

Palette colors use RGBW (0.0-1.0):
```json
{"red": 1.0, "green": 0.0, "blue": 0.0, "white": 0.0}
```

**Guidelines:**
- **Intros/outros:** Cool, subdued colors. Blues, deep purples. 1-2 colors.
- **Verses:** Moderate palette, 2-3 colors. Shift toward the song's mood.
- **Choruses:** Bold, saturated palette, 3-4 colors. Higher contrast.
- **Drops/peaks:** Maximum saturation. Reds, whites, hot colors. Add white channel for punch.
- **Breakdowns:** Pull back to cool/ambient. Single color or complementary pair.
- **Builds:** Transition palette from cool to hot across cues.
- **Key changes:** Shift palette to reflect new tonality.

Remember: The movers have a color wheel (8 fixed colors), so the system maps your palette to the nearest wheel color. The Betopper renders RGBW directly but snaps to saturated primaries.

## Step 5: Generate the Script

### File Structure

```json
{
  "version": 1,
  "metadata": {
    "title": "Song Title",
    "artist": "Artist Name",
    "bpm": 128.0,
    "timeSignature": [4, 4],
    "key": "cMinor",
    "genre": "house",
    "durationBars": 200
  },
  "defaultState": {
    "palette": [
      {"red": 0.2, "green": 0.3, "blue": 0.8, "white": 0.0},
      {"red": 0.6, "green": 0.1, "blue": 0.9, "white": 0.0}
    ],
    "groupingStrategy": "capabilitySplit",
    "reactivity": 0.5,
    "movementIntensity": 0.5
  },
  "cues": [ ... ],
  "events": [ ... ]
}
```

### Cue Rules

- **bar** is 1-based. **beat** is 1.0-based (1.0 to 4.0 in 4/4 time). Bar 1, beat 1.0 = the very start.
- Cues are **persistent states** — they hold until the next cue overrides them.
- Fields are **sparse** — only specify what changes. Unspecified fields carry forward.
- Always include `behaviors` on every cue (they don't carry forward from the behaviors of the previous cue — only palette, groupingStrategy, reactivity, and movementIntensity carry forward).
- Place cues at every **structural boundary** (verse start, chorus start, build start, drop, breakdown, etc.).
- Add extra cues within long sections every 8-16 bars for variety (change a behavior variant, shift palette slightly).

### Event Rules

Events are one-shot effects that overlay on the current cue:

```json
{"bar": 64, "beat": 4.5, "type": "blackout", "durationBeats": 0.5}
{"bar": 65, "beat": 1.0, "type": "flash", "intensity": 1.0}
{"bar": 65, "beat": 1.0, "type": "strobeBurst", "durationBeats": 4.0, "intensity": 0.9}
```

- **blackout** — kills all lights for `durationBeats`. Use right before a drop (last half-beat of a build).
- **flash** — full-intensity flash on one frame then rapid decay. Use on drop hits, big accents.
- **strobeBurst** — adds strobe to all fixtures for `durationBeats`. Use on drops and peak moments.

**Common combo for a drop:**
```json
{"bar": 64, "beat": 4.5, "type": "blackout", "durationBeats": 0.5},
{"bar": 65, "beat": 1.0, "type": "flash", "intensity": 1.0},
{"bar": 65, "beat": 1.0, "type": "strobeBurst", "durationBeats": 8.0, "intensity": 0.8}
```

### Reactivity and Movement Intensity

These are 0.0-1.0 values set per cue:
- **reactivity** — how aggressively lights respond to audio. 0.3 for ambient, 0.5 for verses, 0.7-0.8 for choruses, 1.0 for drops.
- **movementIntensity** — how much the movers swing. 0.2 for slow ambient, 0.5 for moderate, 0.8-1.0 for peak moments.

## Step 6: Choreography Principles

### Energy Mapping
Match lighting intensity to the song's energy:
- Low energy (intro, breakdown): `breathe`, slow `colorWash`, gentle `movementPattern` (circle or sweep at low speed)
- Medium energy (verse): `beatPulse` at 0.7 intensity, `colorWash`, `panSweep` or `figure8`
- High energy (chorus): `beatPulse` at 1.0, `spectralColor` or fast `colorWash`, `ballyhoo` or `randomLook`
- Peak (drop): Everything at max. `beatPulse` alternating between groups, `strobe`, `randomLook`, `strobeBurst` events

### Variety
- Change grouping strategy every 16-32 bars
- Alternate movement patterns between sections
- Shift between `colorWash` and `colorSplit` across choruses
- Use `moverPairSplit` to give mover pairs different movements in high-energy sections
- Use `allUnison` for big unison moments (first beat of a drop, final chorus hit)

### Transitions
- Use `"transition": "crossfade"` with `"transitionBeats": 4.0` for smooth section changes
- Use `"transition": "snap"` for hard cuts (drops, breakdowns)
- Place a `blackout` event (0.5 beats) right before a snap transition for maximum impact

### Builds
Escalate across a build section using multiple cues:
1. Start with moderate behaviors, low reactivity
2. Every 4-8 bars: increase speed, reactivity, movementIntensity
3. Add `blackoutAccent` behavior in the last 8 bars
4. Add `strobe` (variant 3, punchy) in the last 4 bars
5. End with blackout event on the last half-beat before the drop

## Valid Key Values

Use these exact strings for `metadata.key`:
```
cMajor, cMinor, dbMajor, cSharpMinor, dMajor, dMinor,
ebMajor, dSharpMinor, eMajor, eMinor, fMajor, fMinor,
gbMajor, fSharpMinor, gMajor, gMinor, abMajor, gSharpMinor,
aMajor, aMinor, bbMajor, aSharpMinor, bMajor, bMinor
```

## Output

Output the complete `.wilsonscript` JSON. Aim for 20-60 cues depending on song length and complexity, plus 5-20 events for accent moments. Every structural boundary should have a cue. The script should feel like a professional light show that was programmed by someone who listened to the song and timed every section change, build, and drop.
