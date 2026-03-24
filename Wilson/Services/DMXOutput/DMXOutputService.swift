import Foundation

/// Renders DMX frames and sends them to USB-to-DMX hardware.
/// Primary target: ENTTEC DMX USB Pro.
@Observable
final class DMXOutputService {
    private(set) var isConnected = false
    private(set) var frameRate: Double = 0

    /// Target DMX frame rate (~44Hz per DMX standard).
    static let targetFrameRate: Double = 44

    /// Send a DMX frame to the connected device.
    func send(frame: DMXFrame) {
        // TODO: Phase 2 — Implement ENTTEC Pro serial protocol:
        // 1. Open serial port (FTDI USB)
        // 2. Frame with ENTTEC message header (0x7E)
        // 3. Send 512 channel bytes
        // 4. Close with end-of-message (0xE7)
    }

    /// Scan for connected ENTTEC USB devices.
    func scanForDevices() async -> [String] {
        // TODO: Phase 2 — Enumerate /dev/tty.usbserial-* devices
        return []
    }

    /// Connect to a specific serial device path.
    func connect(devicePath: String) async throws {
        // TODO: Phase 2 — Open serial connection
        isConnected = true
    }

    func disconnect() {
        isConnected = false
    }
}
