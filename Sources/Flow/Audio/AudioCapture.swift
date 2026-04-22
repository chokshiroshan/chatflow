import Foundation
import AVFoundation

/// Captures microphone audio via AVAudioEngine, outputs 24kHz mono PCM16.
///
/// Uses the inputNode's own output format for the tap but wraps in try-catch
/// with fallback to standard format. Manual float32→int16 + downsampling.
final class AudioCapture {
    private var engine: AVAudioEngine?
    private var chunkCount = 0
    private var tapFired = false

    var isRunning: Bool { engine?.isRunning ?? false }
    static let targetSampleRate: Double = 24000.0
    var onAudioData: ((Data) -> Void)?

    func start() async throws {
        let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        guard granted else { throw AudioError.permissionDenied }

        let engine = AVAudioEngine()
        self.engine = engine
        let inputNode = engine.inputNode

        // Start engine first so format is stable
        try engine.start()
        print("🎙️ Engine started")

        // Small delay for hardware to settle
        try await Task.sleep(for: .milliseconds(300))

        let hwFormat = inputNode.outputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0 else { throw AudioError.noInputDevice }
        print("🎤 Hardware: \(hwFormat.sampleRate)Hz, \(hwFormat.channelCount)ch")

        // Try installing tap — wrap in ObjC catch for NSException from AVAudioEngine
        let tapFormat = hwFormat
        let tapBufferSize: AVAudioFrameCount = 1024

        var tapInstalled = false

        // Attempt 1: Use hardware format directly
        do {
            try ObjC.catchException {
                inputNode.installTap(onBus: 0, bufferSize: tapBufferSize, format: tapFormat) { [weak self] buffer, _ in
                    self?.handleBuffer(buffer)
                }
            }
            tapInstalled = true
            print("🎙️ Tap installed with hwFormat (\(Int(tapFormat.sampleRate))Hz)")
        } catch {
            print("⚠️ hwFormat tap failed: \(error.localizedDescription)")
        }

        // Attempt 2: Use standard non-interleaved float32 format at hardware rate
        if !tapInstalled {
            let stdFormat = AVAudioFormat(standardFormatWithSampleRate: hwFormat.sampleRate, channels: hwFormat.channelCount)!
            do {
                try ObjC.catchException {
                    inputNode.installTap(onBus: 0, bufferSize: tapBufferSize, format: stdFormat) { [weak self] buffer, _ in
                        self?.handleBuffer(buffer)
                    }
                }
                tapInstalled = true
                print("🎙️ Tap installed with standardFormat (\(Int(stdFormat.sampleRate))Hz)")
            } catch {
                print("⚠️ standardFormat tap failed: \(error.localizedDescription)")
            }
        }

        // Attempt 3: nil format (uses whatever the node has internally)
        if !tapInstalled {
            inputNode.removeTap(onBus: 0)
            do {
                try ObjC.catchException {
                    inputNode.installTap(onBus: 0, bufferSize: tapBufferSize, format: nil) { [weak self] buffer, _ in
                        self?.handleBuffer(buffer)
                    }
                }
                tapInstalled = true
                print("🎙️ Tap installed with nil format")
            } catch {
                print("⚠️ nil format tap failed: \(error.localizedDescription)")
            }
        }

        guard tapInstalled else {
            engine.stop()
            self.engine = nil
            throw AudioError.noInputDevice
        }

        chunkCount = 0
        tapFired = false

        // Verify tap fires
        try await Task.sleep(for: .milliseconds(500))
        if !tapFired {
            print("⚠️ Tap hasn't fired after 500ms...")
            try await Task.sleep(for: .milliseconds(1500))
            if !tapFired {
                print("❌ Tap never fired — removing and failing")
                inputNode.removeTap(onBus: 0)
                engine.stop()
                self.engine = nil
                throw AudioError.noInputDevice
            }
        }
    }

    func stop() {
        print("🛑 Audio stopped. \(chunkCount) chunks sent.")
        chunkCount = 0
        tapFired = false
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        if !tapFired {
            tapFired = true
            print("🎙️ TAP FIRED! frames=\(buffer.frameLength), rate=\(buffer.format.sampleRate)Hz")
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0, let floatData = buffer.floatChannelData else { return }

        let samples = floatData[0]
        let srcRate = buffer.format.sampleRate
        let ratio = Self.targetSampleRate / srcRate
        let outputCount = Int(Double(frameLength) * ratio)
        guard outputCount > 0 else { return }

        var pcm16 = Data(capacity: outputCount * 2)
        for i in 0..<outputCount {
            let srcIdx = min(Int(Double(i) / ratio), frameLength - 1)
            let clamped = max(-1.0, min(1.0, samples[srcIdx]))
            let intSample = Int16(clamped * 32767.0)
            pcm16.append(contentsOf: withUnsafeBytes(of: intSample.littleEndian) { Array($0) })
        }

        guard !pcm16.isEmpty else { return }
        chunkCount += 1
        if chunkCount == 1 {
            print("🎙️ First chunk: \(pcm16.count) bytes (\(outputCount) samples from \(frameLength) @ \(Int(srcRate))Hz)")
        }
        onAudioData?(pcm16)
    }
}

// MARK: - NSException catcher (AVAudioEngine throws ObjC exceptions)

private class ObjC {
    @objc static func catchException(_ block: () -> Void) throws {
        var exception: NSException?
        let handler: @convention(block) (NSException) -> Void = { e in exception = e }
        let oldHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler(handler)
        block()
        NSSetUncaughtExceptionHandler(oldHandler)
        if let e = exception {
            throw AudioError.unsupportedFormat
        }
    }
}

enum AudioError: LocalizedError {
    case unsupportedFormat
    case permissionDenied
    case notRunning
    case noInputDevice

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "Cannot create audio tap — format mismatch"
        case .permissionDenied: return "Microphone permission denied"
        case .notRunning: return "Audio capture not running"
        case .noInputDevice: return "No microphone detected"
        }
    }
}
