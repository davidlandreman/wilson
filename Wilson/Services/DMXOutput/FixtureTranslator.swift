import Foundation

/// Translates abstract behavior output (virtual intent) into fixture-specific DMX-ready attributes.
/// Sits between the decision engine and DMX frame builder.
///
/// Behaviors think in terms of intent: "be bright red", "strobe on beat", "sweep left".
/// The translator converts that into what each physical fixture needs to achieve the effect.
enum FixtureTranslator {

    /// Translate a virtual FixtureState into DMX-ready attributes for a specific fixture.
    static func translate(state: FixtureState, fixture: StageFixture) -> FixtureState {
        let attrs = fixture.attributes

        // Dispatch based on fixture capabilities
        if attrs.contains(.colorWheel) && !attrs.contains(.red) {
            return translateColorWheelSpot(state: state, fixture: fixture)
        }
        if attrs.contains(.red) && !attrs.contains(.dimmer) {
            return translateDimmerlessRGBW(state: state, fixture: fixture)
        }
        if attrs.contains(.red) && attrs.contains(.dimmer) && attrs.contains(.strobe) && !attrs.contains(.pan) {
            return translateRGBWStrobe(state: state, fixture: fixture)
        }

        // Generic: pass through, just ensure shutter open on movers
        return ensureShutterOpen(state: state, fixture: fixture)
    }

    // MARK: - Color Wheel Spot (MINGJIE 60W)

    /// Moving head with color wheel instead of RGB mixing.
    /// Maps RGB intent → nearest color wheel position, uses shutter for strobe.
    /// Respects manually set values (colorWheel, gobo, speed, mode, strobe) — if they're
    /// already in the state (from the DMX controller), pass them through untouched.
    private static func translateColorWheelSpot(state: FixtureState, fixture: StageFixture) -> FixtureState {
        var out = FixtureState(fixtureID: state.fixtureID)

        // Pass through dimmer
        if let dimmer = state.attributes[.dimmer] {
            out.attributes[.dimmer] = dimmer
        }

        // Pass through pan/tilt
        for attr: FixtureAttribute in [.pan, .tilt, .panFine, .tiltFine] {
            if let v = state.attributes[attr] { out.attributes[attr] = v }
        }

        // Pass through manually set channels (speed, mode, custom)
        for attr: FixtureAttribute in [.speed, .mode, .custom] {
            if let v = state.attributes[attr] { out.attributes[attr] = v }
        }

        // Gobo: if already set as a raw DMX value (manual control), pass through.
        // Otherwise map from gobo intent (0.0=open, 0.2=subtle, etc.)
        if let goboVal = state.attributes[.gobo] {
            // Values matching GoboIntent thresholds get mapped; raw fader values pass through
            out.attributes[.gobo] = goboIntentToDMX(goboVal)
        }

        // Color wheel: if already set directly (manual control), pass through.
        // Otherwise map from RGB intent.
        if let manualCW = state.attributes[.colorWheel] {
            out.attributes[.colorWheel] = manualCW
        } else {
            let r = state.attributes[.red] ?? 0
            let g = state.attributes[.green] ?? 0
            let b = state.attributes[.blue] ?? 0
            if r + g + b > 0.01 {
                out.attributes[.colorWheel] = rgbToColorWheel(r: r, g: g, b: b)
            }
            // else: don't set — buildDMXFrame uses defaultValue (0 = open white)
        }

        // Strobe: if already set (manual or behavior), pass through.
        if let strobeVal = state.attributes[.strobe], strobeVal > 0.01 {
            out.attributes[.strobe] = strobeVal
        }
        // else: don't set — buildDMXFrame uses defaultValue (0 = open)

        return out
    }

    // MARK: - Dimmerless RGBW (Betopper LF4808 4ch)

    /// RGBW fixture with no master dimmer. Brightness controlled by scaling color channels.
    private static func translateDimmerlessRGBW(state: FixtureState, fixture: StageFixture) -> FixtureState {
        var out = FixtureState(fixtureID: state.fixtureID)

        let dimmerIntent = state.attributes[.dimmer] ?? 1.0

        // Scale color channels by dimmer intent
        for attr: FixtureAttribute in [.red, .green, .blue, .white] {
            if let v = state.attributes[attr] {
                out.attributes[attr] = v * dimmerIntent
            }
        }

        return out
    }

    // MARK: - RGBW + Dimmer + Strobe (Betopper LF4808 15ch)

    /// RGBW fixture with master dimmer, strobe, patterns, and speed (Betopper LF4808 15ch).
    private static func translateRGBWStrobe(state: FixtureState, fixture: StageFixture) -> FixtureState {
        var out = FixtureState(fixtureID: state.fixtureID)

        let dimmer = state.attributes[.dimmer] ?? 0

        // Blinder-class: aggressive blackout threshold.
        if dimmer < 0.05 {
            out.attributes[.dimmer] = 0
            return out
        }

        // Blinder response curve:
        //   Flash peak (>70%): full blast — white + color at full intensity
        //   Decay (15-70%):    drop white immediately, dim color softly
        //   Tail (5-15%):      very soft color glow, no white
        let r = state.attributes[.red] ?? 0
        let g = state.attributes[.green] ?? 0
        let b = state.attributes[.blue] ?? 0
        let w = state.attributes[.white] ?? 0
        let (snapR, snapG, snapB, snapW) = snapToSaturated(r: r, g: g, b: b, w: w)

        if dimmer > 0.7 {
            // Flash peak: everything at full
            out.attributes[.dimmer] = dimmer
            out.attributes[.red] = snapR
            out.attributes[.green] = snapG
            out.attributes[.blue] = snapB
            out.attributes[.white] = snapW
        } else if dimmer > 0.15 {
            // Decay: drop white, soften color
            let colorScale = (dimmer - 0.15) / (0.7 - 0.15) // 0→1 over the range
            out.attributes[.dimmer] = dimmer * 0.5 // Aggressive dimmer reduction
            out.attributes[.red] = snapR * colorScale
            out.attributes[.green] = snapG * colorScale
            out.attributes[.blue] = snapB * colorScale
            out.attributes[.white] = 0 // White bar off immediately after flash
        } else {
            // Tail: very soft glow
            out.attributes[.dimmer] = dimmer * 0.3
            out.attributes[.red] = snapR * 0.15
            out.attributes[.green] = snapG * 0.15
            out.attributes[.blue] = snapB * 0.15
            out.attributes[.white] = 0
        }

        // Strobe: hardware speed control (0=off, 1-255=slow→fast).
        // The Betopper's strobe channel needs a SUSTAINED speed value.
        // StrobeBehavior's per-frame toggling doesn't work here — use the
        // scene-based strobe speed from the LookGenerator instead.
        // If manually set (DMX controller), pass through directly.
        if let strobeVal = state.attributes[.strobe], strobeVal > 0.01 {
            out.attributes[.strobe] = strobeVal
        }

        // Pattern: drives RGB pattern (CH7), W pattern (CH9), RGBW pattern (CH12)
        // All share .custom attribute so one value controls all pattern channels
        if let pattern = state.attributes[.custom] {
            out.attributes[.custom] = pattern
        }

        // Speed: drives RGB velocity (CH8), W velocity (CH10), RGBW velocity (CH13)
        // All share .speed attribute
        if let speed = state.attributes[.speed] {
            out.attributes[.speed] = speed
        }

        return out
    }

    // MARK: - Generic (pass-through with shutter safety)

    private static func ensureShutterOpen(state: FixtureState, fixture: StageFixture) -> FixtureState {
        // No special handling needed — strobe channel defaultValue (0) = open on most fixtures.
        // Only intervene if a strobe intent is present.
        return state
    }

    // MARK: - Gobo Intent

    // MARK: - Betopper Color Snapping

    /// Snap RGB values to the nearest saturated primary/secondary for clean LED output.
    /// The Betopper has discrete R/G/B/W LED groups — blended pastels look washed out.
    /// This keeps only the dominant 1-2 channels active, producing bold colors.
    private static func snapToSaturated(r: Double, g: Double, b: Double, w: Double) -> (Double, Double, Double, Double) {
        let maxC = max(r, g, b)
        guard maxC > 0.01 else { return (0, 0, 0, w) }

        // Normalize to find the color balance
        let nr = r / maxC
        let ng = g / maxC
        let nb = b / maxC

        // Threshold: channels below 40% of max get zeroed, above 60% get boosted to full
        let lo = 0.4
        let hi = 0.6

        let snapR: Double = nr > hi ? 1.0 : (nr < lo ? 0.0 : nr)
        let snapG: Double = ng > hi ? 1.0 : (ng < lo ? 0.0 : ng)
        let snapB: Double = nb > hi ? 1.0 : (nb < lo ? 0.0 : nb)

        // Scale back by original intensity
        return (snapR * maxC, snapG * maxC, snapB * maxC, w)
    }

    /// Abstract gobo categories that the LookGenerator uses.
    /// The FixtureTranslator maps these to fixture-specific DMX positions.
    /// Stored as normalized 0.0–1.0 on the `.gobo` attribute.
    enum GoboIntent {
        static let open: Double     = 0.0   // No gobo
        static let subtle: Double   = 0.2   // Soft texture (dots, radial)
        static let geometric: Double = 0.4  // Hard shapes (triangle, hexagon)
        static let dynamic: Double  = 0.6   // Motion feel (swirl)
        static let complex: Double  = 0.8   // Busy, high-detail (jigsaw)
    }

    /// MINGJIE gobo wheel DMX positions (verified from OFL fixture data).
    /// DMX 0-7: Open, 8-15: Rose, 16-23: Radial Dots, 24-31: Triangle,
    /// 32-39: Hexagon, 40-47: Swirl A, 48-55: Swirl B, 56-63: Jigsaw
    private static func goboIntentToDMX(_ intent: Double) -> Double {
        let dmxCenter: Double
        if intent < 0.1 {
            dmxCenter = 3.5     // Open
        } else if intent < 0.3 {
            dmxCenter = 19.5    // Radial Dots (subtle texture)
        } else if intent < 0.5 {
            // Alternate between triangle and hexagon
            dmxCenter = intent < 0.45 ? 27.5 : 35.5
        } else if intent < 0.7 {
            dmxCenter = 43.5    // Swirl (dynamic)
        } else {
            dmxCenter = 59.5    // Jigsaw (complex)
        }
        return dmxCenter / 255.0
    }

    // MARK: - Color Wheel Mapping

    /// MINGJIE color wheel: 8 colors + white, each occupying a 10-value DMX range.
    /// Order verified by manual testing on the physical fixture.
    private static let colorWheelColors: [(r: Double, g: Double, b: Double, dmxCenter: Double)] = [
        (1.0,  1.0,  1.0,    4.5),  // White (open)    DMX 0-9
        (1.0,  0.0,  0.0,   14.5),  // Red              DMX 10-19
        (0.8,  1.0,  0.0,   24.5),  // Yellow-Green     DMX 20-29
        (0.0,  0.0,  1.0,   34.5),  // Blue             DMX 30-39
        (0.0,  0.69, 0.31,  44.5),  // Green            DMX 40-49
        (1.0,  0.5,  0.0,   54.5),  // Orange           DMX 50-59
        (0.91, 0.55, 0.79,  64.5),  // Pink             DMX 60-69
        (0.0,  0.69, 0.94,  74.5),  // Sky Blue         DMX 70-79
    ]

    /// Find the nearest color wheel position for an RGB value.
    /// Normalizes input to full brightness before matching so dimmed colors
    /// still map to the correct wheel slot.
    private static func rgbToColorWheel(r: Double, g: Double, b: Double) -> Double {
        // Normalize to full brightness for matching
        let maxC = max(r, g, b)
        let nr: Double, ng: Double, nb: Double
        if maxC > 0.01 {
            nr = r / maxC
            ng = g / maxC
            nb = b / maxC
        } else {
            return 4.5 / 255.0 // Near-black → white (open)
        }

        var bestDistance = Double.infinity
        var bestDMX = 4.5 // Default: white

        for entry in colorWheelColors {
            let dr = nr - entry.r
            let dg = ng - entry.g
            let db = nb - entry.b
            let distance = dr * dr + dg * dg + db * db

            if distance < bestDistance {
                bestDistance = distance
                bestDMX = entry.dmxCenter
            }
        }

        return bestDMX / 255.0 // Normalize to 0–1
    }
}
