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

        // Pass through manually set channels (gobo, speed, mode, custom)
        for attr: FixtureAttribute in [.gobo, .speed, .mode, .custom] {
            if let v = state.attributes[attr] { out.attributes[attr] = v }
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

    /// RGBW fixture with master dimmer and strobe channel.
    private static func translateRGBWStrobe(state: FixtureState, fixture: StageFixture) -> FixtureState {
        var out = FixtureState(fixtureID: state.fixtureID)

        // Pass through dimmer and color
        if let v = state.attributes[.dimmer] { out.attributes[.dimmer] = v }
        for attr: FixtureAttribute in [.red, .green, .blue, .white] {
            if let v = state.attributes[attr] { out.attributes[attr] = v }
        }

        // Map strobe intent to strobe channel
        if let strobeIntent = state.attributes[.strobe], strobeIntent > 0.01 {
            out.attributes[.strobe] = strobeIntent
        }

        return out
    }

    // MARK: - Generic (pass-through with shutter safety)

    private static func ensureShutterOpen(state: FixtureState, fixture: StageFixture) -> FixtureState {
        // No special handling needed — strobe channel defaultValue (0) = open on most fixtures.
        // Only intervene if a strobe intent is present.
        return state
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
