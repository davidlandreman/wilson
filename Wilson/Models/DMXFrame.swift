import Foundation

/// A single DMX universe frame — 512 channels of data.
struct DMXFrame: Sendable {
    /// Channel values, indexed 0–511 (DMX channels 1–512).
    var channels: [UInt8]

    /// All channels at zero.
    static let blackout = DMXFrame(channels: [UInt8](repeating: 0, count: 512))

    init(channels: [UInt8] = [UInt8](repeating: 0, count: 512)) {
        precondition(channels.count == 512)
        self.channels = channels
    }

    subscript(dmxChannel: Int) -> UInt8 {
        get { channels[dmxChannel - 1] }
        set { channels[dmxChannel - 1] = newValue }
    }
}
