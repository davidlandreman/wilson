import Testing
@testable import Wilson

@Suite("Wilson Core Tests")
struct WilsonTests {
    @Test("DMX frame initializes to blackout")
    func dmxFrameBlackout() {
        let frame = DMXFrame.blackout
        #expect(frame.channels.count == 512)
        #expect(frame.channels.allSatisfy { $0 == 0 })
    }

    @Test("DMX frame subscript uses 1-based addressing")
    func dmxFrameSubscript() {
        var frame = DMXFrame.blackout
        frame[1] = 255
        #expect(frame.channels[0] == 255)
        frame[512] = 128
        #expect(frame.channels[511] == 128)
    }

    @Test("Musical state defaults to silent")
    func musicalStateDefaults() {
        let state = MusicalState()
        #expect(state.isSilent)
        #expect(state.bpm == 0)
        #expect(state.energy == 0)
        #expect(state.segment == .unknown)
    }

    @Test("Light color presets")
    func lightColorPresets() {
        let off = LightColor.off
        #expect(off.red == 0)
        #expect(off.green == 0)
        #expect(off.blue == 0)

        let warm = LightColor.warmWhite
        #expect(warm.red == 1.0)
        #expect(warm.white == 1.0)
    }
}
