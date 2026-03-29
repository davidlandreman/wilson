import Testing
@testable import Wilson

@Suite("AdaptiveEnergyNormalizer")
struct AdaptiveEnergyNormalizerTests {

    private func makeNormalizer(
        analysisRate: Double = 47.0,
        windowSeconds: Double = 12.0,
        defaultCeiling: Double = 0.15
    ) -> AdaptiveEnergyNormalizer {
        AdaptiveEnergyNormalizer(
            analysisRate: analysisRate,
            windowSeconds: windowSeconds,
            defaultCeiling: defaultCeiling
        )
    }

    /// Feed N frames at a constant RMS, return the last output.
    private func feedConstant(
        _ normalizer: inout AdaptiveEnergyNormalizer,
        rms: Float,
        frames: Int
    ) -> Double {
        var last = 0.0
        for _ in 0..<frames {
            last = normalizer.normalize(rms)
        }
        return last
    }

    @Test func silenceStaysZero() {
        var norm = makeNormalizer()
        for _ in 0..<100 {
            let out = norm.normalize(0.0)
            #expect(out == 0.0)
        }
    }

    @Test func belowFloorIsZero() {
        var norm = makeNormalizer()
        let out = norm.normalize(0.0005) // below 0.001 floor
        #expect(out == 0.0)
    }

    @Test func coldStartUsesDefaultCeiling() {
        var norm = makeNormalizer(defaultCeiling: 0.15)
        // First non-silent frame at RMS 0.11
        // Expected: 0.11 / 0.15 * 0.85 ≈ 0.623 (ceiling jumps toward 0.11 on fast attack)
        let out = norm.normalize(0.11)
        #expect(out > 0.4)
        #expect(out < 0.9)
    }

    @Test func convergesOnSteadySignal() {
        var norm = makeNormalizer()
        // Feed 600 frames at RMS 0.10 — window fills, 95th percentile = 0.10
        // Ceiling converges to ~0.10. Output ≈ 0.10 / 0.10 * 0.85 = 0.85
        let last = feedConstant(&norm, rms: 0.10, frames: 600)
        #expect(last > 0.75)
        #expect(last < 0.95)
    }

    @Test func preservesDynamicRange() {
        var norm = makeNormalizer()
        // Fill with alternating 0.05 and 0.10 — establish ceiling
        for i in 0..<600 {
            let rms: Float = i.isMultiple(of: 2) ? 0.10 : 0.05
            _ = norm.normalize(rms)
        }

        // Now measure the ratio
        let high = norm.normalize(0.10)
        let low = norm.normalize(0.05)

        // High should be roughly double the low
        #expect(high > low * 1.5)
        #expect(high > 0.6)
        #expect(low > 0.2)
        #expect(low < 0.6)
    }

    @Test func fastAttackOnVolumeIncrease() {
        var norm = makeNormalizer()
        // Stabilize at RMS 0.05
        _ = feedConstant(&norm, rms: 0.05, frames: 600)
        let before = norm.normalize(0.05)

        // Jump to RMS 0.15 — ceiling should rise quickly
        _ = norm.normalize(0.15)
        _ = norm.normalize(0.15)
        _ = norm.normalize(0.15)
        let after = norm.normalize(0.15)

        // Output should not exceed 1.0 even with 3x volume jump
        #expect(after <= 1.0)
        // And should be in reasonable range (ceiling has caught up)
        #expect(after > 0.5)
        // Before value at 0.05 should have been reasonable (ceiling ~0.075 after convergence)
        #expect(before > 0.5)
    }

    @Test func slowDecayOnVolumeDecrease() {
        var norm = makeNormalizer()
        // Stabilize at RMS 0.15
        _ = feedConstant(&norm, rms: 0.15, frames: 600)

        // Drop to RMS 0.05 — ceiling should hold for a while
        let immediateAfterDrop = norm.normalize(0.05)
        // With the old ceiling still at ~0.15, 0.05 should read as low
        #expect(immediateAfterDrop < 0.4)
        #expect(immediateAfterDrop > 0.1)

        // After 100 more frames (~2s) at 0.05, ceiling should still be elevated
        let later = feedConstant(&norm, rms: 0.05, frames: 100)
        #expect(later < 0.5) // still reads as low relative to old ceiling
    }

    @Test func outputNeverExceedsOne() {
        var norm = makeNormalizer()
        // Stabilize at low level then spike high
        _ = feedConstant(&norm, rms: 0.02, frames: 600)
        let spike = norm.normalize(0.50) // 25x the established ceiling
        #expect(spike <= 1.0)
        #expect(spike > 0.9) // should be near 1.0 via soft clip
    }

    @Test func sandstormSimulation() {
        var norm = makeNormalizer()

        // Intro: ~50 frames at RMS 0.02 (quiet pads)
        let introEnd = feedConstant(&norm, rms: 0.02, frames: 50)

        // Build: ramp from 0.02 to 0.11 over 100 frames
        var buildValues: [Double] = []
        for i in 0..<100 {
            let rms = Float(0.02 + 0.09 * Double(i) / 100.0)
            buildValues.append(norm.normalize(rms))
        }
        let buildEnd = buildValues.last!

        // Drop: 300 frames at RMS 0.11 (sustained energy)
        let dropEnd = feedConstant(&norm, rms: 0.11, frames: 300)

        // Breakdown: 100 frames at RMS 0.02
        let breakdownEnd = feedConstant(&norm, rms: 0.02, frames: 100)

        // Intro should be relatively low (ceiling is default 0.15)
        #expect(introEnd < 0.3)

        // Build should be increasing
        #expect(buildEnd > introEnd)

        // Drop (after convergence) should be high
        #expect(dropEnd > 0.70)

        // Breakdown should read as low relative to drop
        #expect(breakdownEnd < dropEnd * 0.4)
    }
}
