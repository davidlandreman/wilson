import Foundation

/// Lock-free circular buffer for accumulating audio samples on the audio queue.
/// Not thread-safe by design — used exclusively from a single dispatch queue.
final class RingBuffer: @unchecked Sendable {
    private var storage: [Float]
    private let capacity: Int
    private var writePos: Int = 0
    private var totalWritten: Int = 0
    private let hopSize: Int
    private var samplesUntilHop: Int

    init(capacity: Int, hopSize: Int) {
        self.capacity = capacity
        self.hopSize = hopSize
        self.samplesUntilHop = hopSize
        self.storage = [Float](repeating: 0, count: capacity)
    }

    /// Append samples to the buffer, wrapping around as needed.
    func write(_ samples: UnsafeBufferPointer<Float>) {
        let count = samples.count
        guard count > 0, let src = samples.baseAddress else { return }

        storage.withUnsafeMutableBufferPointer { dst in
            guard let dstBase = dst.baseAddress else { return }
            if writePos + count <= capacity {
                dstBase.advanced(by: writePos).update(from: src, count: count)
            } else {
                let first = capacity - writePos
                dstBase.advanced(by: writePos).update(from: src, count: first)
                dstBase.update(from: src.advanced(by: first), count: count - first)
            }
        }

        writePos = (writePos + count) % capacity
        totalWritten += count
        samplesUntilHop -= count
    }

    /// Copy the most recent `count` samples into the output buffer.
    func read(count: Int, into output: UnsafeMutablePointer<Float>) {
        let readStart = ((writePos - count) % capacity + capacity) % capacity

        storage.withUnsafeBufferPointer { src in
            guard let srcBase = src.baseAddress else { return }
            if readStart + count <= capacity {
                output.update(from: srcBase.advanced(by: readStart), count: count)
            } else {
                let first = capacity - readStart
                output.update(from: srcBase.advanced(by: readStart), count: first)
                output.advanced(by: first).update(from: srcBase, count: count - first)
            }
        }
    }

    /// True when enough new samples have accumulated for the next FFT hop.
    var isHopReady: Bool { samplesUntilHop <= 0 }

    /// Number of samples currently available (up to capacity).
    var availableSamples: Int { min(totalWritten, capacity) }

    /// Mark the current hop as consumed and reset the counter.
    func consumeHop() {
        samplesUntilHop += hopSize
    }
}
