import Foundation
import os

// MARK: - Errors

enum DMXOutputError: Error, LocalizedError {
    case deviceNotFound(String)
    case openFailed(String, Int32)
    case configurationFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .deviceNotFound(let path):
            "DMX device not found at \(path)"
        case .openFailed(let path, let errno):
            "Failed to open \(path) (errno \(errno))"
        case .configurationFailed(let errno):
            "Failed to configure serial port (errno \(errno))"
        }
    }
}

// MARK: - DMXOutputService

/// Sends DMX frames to an ENTTEC DMX USB Pro via serial.
@Observable
final class DMXOutputService {
    private(set) var isConnected = false
    private(set) var connectedDevicePath: String?
    private(set) var frameRate: Double = 0

    private var fileDescriptor: Int32 = -1
    private let serialQueue = DispatchQueue(label: "com.landreman.Wilson.dmxoutput", qos: .userInteractive)
    private var lastSendTime: Double = 0
    private var frameRateAccumulator: Double = 0
    private var frameRateCount: Int = 0
    private static let logger = Logger(subsystem: "com.landreman.Wilson", category: "DMXOutput")

    // MARK: - Device Enumeration

    /// Scan for connected USB serial devices (ENTTEC and compatible).
    /// Returns cu.* paths (calling-unit) — correct for output on macOS.
    func scanForDevices() -> [String] {
        let devPath = "/dev"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: devPath) else {
            return []
        }
        return entries
            .filter { $0.hasPrefix("cu.usbserial") }
            .map { "\(devPath)/\($0)" }
            .sorted()
    }

    // MARK: - Connection

    /// Connect to an ENTTEC DMX USB Pro at the given device path.
    func connect(devicePath: String) throws {
        guard FileManager.default.fileExists(atPath: devicePath) else {
            throw DMXOutputError.deviceNotFound(devicePath)
        }

        // Use cu.* for output (doesn't wait for carrier detect like tty.*)
        // O_NONBLOCK prevents blocking on open; O_NOCTTY prevents becoming controlling terminal
        let fd = Darwin.open(devicePath, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            throw DMXOutputError.openFailed(devicePath, errno)
        }

        // Set baud rate via IOSSIOSPEED ioctl — the macOS way for FTDI serial ports.
        // tcsetattr/cfsetspeed often fails with EINVAL on FTDI drivers.
        var speed: speed_t = 57600
        if ioctl(fd, 0x80045402 /* IOSSIOSPEED */, &speed) != 0 {
            Self.logger.warning("IOSSIOSPEED failed (errno \(errno)) — using default baud rate")
        }

        fileDescriptor = fd
        isConnected = true
        connectedDevicePath = devicePath
        lastSendTime = 0
        frameRate = 0
        frameRateAccumulator = 0
        frameRateCount = 0

        Self.logger.info("Connected to ENTTEC DMX USB Pro at \(devicePath, privacy: .public)")
    }

    /// Disconnect from the device.
    func disconnect() {
        let fd = fileDescriptor
        fileDescriptor = -1
        isConnected = false
        connectedDevicePath = nil
        frameRate = 0

        if fd >= 0 {
            // Send blackout before disconnecting
            let blackoutMessage = Self.buildENTTECMessage(frame: .blackout)
            serialQueue.sync {
                blackoutMessage.withUnsafeBufferPointer { ptr in
                    if let base = ptr.baseAddress {
                        Darwin.write(fd, base, ptr.count)
                    }
                }
                Darwin.close(fd)
            }
        }

        Self.logger.info("Disconnected from ENTTEC DMX USB Pro")
    }

    // MARK: - DMX Output

    /// Send a DMX frame to the connected ENTTEC device.
    /// Safe to call at any rate — writes happen on a dedicated serial queue.
    func send(frame: DMXFrame) {
        let fd = fileDescriptor
        guard fd >= 0 else { return }

        let message = Self.buildENTTECMessage(frame: frame)

        serialQueue.async {
            message.withUnsafeBufferPointer { ptr in
                guard let base = ptr.baseAddress else { return }
                var written = 0
                while written < ptr.count {
                    let result = Darwin.write(fd, base + written, ptr.count - written)
                    if result <= 0 {
                        Self.logger.error("Serial write failed (errno \(errno))")
                        Darwin.close(fd)
                        return
                    }
                    written += result
                }
            }
        }

        // Frame rate tracking (called from main actor context)
        let now = ProcessInfo.processInfo.systemUptime
        if lastSendTime > 0 {
            let interval = now - lastSendTime
            if interval > 0 {
                frameRateAccumulator += 1.0 / interval
                frameRateCount += 1
                if frameRateCount >= 20 {
                    frameRate = frameRateAccumulator / Double(frameRateCount)
                    frameRateAccumulator = 0
                    frameRateCount = 0
                }
            }
        }
        lastSendTime = now
    }

    // MARK: - ENTTEC Protocol

    /// Build an ENTTEC DMX USB Pro message for sending a DMX frame.
    /// Format: [0x7E] [Label=6] [LenLo] [LenHi] [StartCode=0x00] [512 channels] [0xE7]
    private static func buildENTTECMessage(frame: DMXFrame) -> [UInt8] {
        let dataLength: UInt16 = 513 // 1 start code + 512 channels
        var message = [UInt8]()
        message.reserveCapacity(Int(dataLength) + 5)

        message.append(0x7E)                          // Start of message
        message.append(0x06)                          // Label: Send DMX Packet
        message.append(UInt8(dataLength & 0xFF))      // Length LSB
        message.append(UInt8(dataLength >> 8))        // Length MSB
        message.append(0x00)                          // DMX start code
        message.append(contentsOf: frame.channels)    // 512 channel values
        message.append(0xE7)                          // End of message

        return message
    }

    // MARK: - Fixture Reset

    /// Send a DMX reset command to all patched fixtures.
    /// Sets channels with `.custom` attribute (typically the reset channel) to DMX 255,
    /// holds for the specified duration, then returns to blackout.
    func resetFixtures(_ fixtures: [StageFixture], holdDuration: Double = 3.0) {
        guard isConnected else { return }

        var frame = DMXFrame.blackout
        for fixture in fixtures {
            guard let dmxAddress = fixture.dmxAddress, dmxAddress >= 1 else { continue }
            for channel in fixture.definition.channels {
                let dmxChannel = dmxAddress + channel.offset
                guard dmxChannel >= 1 && dmxChannel <= 512 else { continue }
                if channel.attribute == .custom {
                    // Reset channels: send 255 to trigger reset
                    frame[dmxChannel] = 255
                } else {
                    frame[dmxChannel] = channel.defaultValue
                }
            }
        }

        // Send reset frame repeatedly for the hold duration, then blackout.
        let resetFrame = frame
        let queue = serialQueue
        let fd = fileDescriptor
        queue.async {
            guard fd >= 0 else { return }
            let start = DispatchTime.now()
            let holdNanos = UInt64(holdDuration * 1_000_000_000)
            while DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds < holdNanos {
                let message = DMXOutputService.buildENTTECMessage(frame: resetFrame)
                message.withUnsafeBytes { ptr in
                    _ = Darwin.write(fd, ptr.baseAddress!, ptr.count)
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            // Send blackout
            let blackout = DMXOutputService.buildENTTECMessage(frame: .blackout)
            blackout.withUnsafeBytes { ptr in
                _ = Darwin.write(fd, ptr.baseAddress!, ptr.count)
            }
        }
    }

    // MARK: - FixtureState → DMX Conversion

    /// Build a DMXFrame from decision engine fixture states and fixture definitions.
    /// Maps normalized 0.0–1.0 attribute values to DMX 0–255 bytes at the correct addresses.
    static func buildDMXFrame(
        fixtureStates: [UUID: FixtureState],
        fixtures: [StageFixture]
    ) -> DMXFrame {
        var frame = DMXFrame.blackout

        for fixture in fixtures {
            guard let dmxAddress = fixture.dmxAddress, dmxAddress >= 1 else { continue }
            guard let rawState = fixtureStates[fixture.id] else { continue }

            // Translate virtual intent → fixture-specific DMX values
            let state = FixtureTranslator.translate(state: rawState, fixture: fixture)

            for channel in fixture.definition.channels {
                let dmxChannel = dmxAddress + channel.offset
                guard dmxChannel >= 1 && dmxChannel <= 512 else { continue }

                if let value = state.attributes[channel.attribute] {
                    // Normalize 0.0–1.0 → 0–255
                    let clamped = min(max(value, 0), 1)
                    frame[dmxChannel] = UInt8(clamped * 255)
                } else {
                    frame[dmxChannel] = channel.defaultValue
                }
            }
        }

        return frame
    }

    deinit {
        let fd = fileDescriptor
        if fd >= 0 {
            Darwin.close(fd)
        }
    }
}
