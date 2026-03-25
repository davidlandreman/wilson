import Foundation

extension LightColor {
    // MARK: - HSB Conversion

    /// Hue (0–360), saturation (0–1), brightness (0–1) from RGB.
    var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let r = red, g = green, b = blue
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC

        let brightness = maxC

        guard delta > 0.001 else {
            return (hue: 0, saturation: 0, brightness: brightness)
        }

        let saturation = delta / maxC
        var hue: Double

        if r == maxC {
            hue = 60.0 * (((g - b) / delta).truncatingRemainder(dividingBy: 6))
        } else if g == maxC {
            hue = 60.0 * (((b - r) / delta) + 2)
        } else {
            hue = 60.0 * (((r - g) / delta) + 4)
        }

        if hue < 0 { hue += 360 }
        return (hue: hue, saturation: saturation, brightness: brightness)
    }

    /// Create a LightColor from HSB values. Hue 0–360, saturation/brightness 0–1.
    static func fromHSB(hue: Double, saturation: Double, brightness: Double, white: Double = 0) -> LightColor {
        let h = hue.truncatingRemainder(dividingBy: 360)
        let s = max(0, min(1, saturation))
        let b = max(0, min(1, brightness))

        let c = b * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = b - c

        let (r1, g1, b1): (Double, Double, Double)
        switch h {
        case 0..<60:    (r1, g1, b1) = (c, x, 0)
        case 60..<120:  (r1, g1, b1) = (x, c, 0)
        case 120..<180: (r1, g1, b1) = (0, c, x)
        case 180..<240: (r1, g1, b1) = (0, x, c)
        case 240..<300: (r1, g1, b1) = (x, 0, c)
        default:        (r1, g1, b1) = (c, 0, x)
        }

        return LightColor(red: r1 + m, green: g1 + m, blue: b1 + m, white: white)
    }

    // MARK: - Interpolation

    /// Linear interpolation between two colors. t = 0 returns self, t = 1 returns `to`.
    func lerp(to other: LightColor, t: Double) -> LightColor {
        let t = max(0, min(1, t))
        return LightColor(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t,
            white: white + (other.white - white) * t
        )
    }

    // MARK: - Warm/Cool Shifting

    /// Shift color toward warm (bias=1) or cool (bias=0). 0.5 = no shift.
    func warmCoolShifted(warmBias: Double) -> LightColor {
        let shift = (warmBias - 0.5) * 0.3 // ±15% max shift
        return LightColor(
            red: max(0, min(1, red + shift)),
            green: green,
            blue: max(0, min(1, blue - shift)),
            white: white
        )
    }

    /// Multiply color intensity by a scalar.
    func scaled(by factor: Double) -> LightColor {
        LightColor(
            red: max(0, min(1, red * factor)),
            green: max(0, min(1, green * factor)),
            blue: max(0, min(1, blue * factor)),
            white: max(0, min(1, white * factor))
        )
    }

    /// Whether this color is effectively black/off.
    var isOff: Bool {
        red < 0.01 && green < 0.01 && blue < 0.01 && white < 0.01
    }
}
