import Foundation
import AVFoundation

/// Captures microphone audio via AVAudioEngine, outputs 24kHz mono PCM16.
///
/// Strategy: Start engine first, wait for hardware to settle, then install tap.
/// Manual float32→int16 + downsampling (no AVAudioConverter — it silently drops frames).
final class AudioCapture {
    private var engine: AVAudioEngine?
    private var chunkCount = 0
    private var tapFired = false

    /// Whether the audio engine is currently capturing.
    var isRunning: Bool {
        engine?.isRunning ?? false
    }

    /// Target: 24kHz mono PCM16 for Realtime API
    static let targetSampleRate: Double = 24000.0

    /// Called with PCM16 audio data (24kHz mono, little-endian).
    var onAudioData: ((Data) -> Void)?

    /// Start capturing audio from default microphone.
    func start() async throws {
        // Request microphone permission
        let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        guard granted else { throw AudioError.permissionDenied }

        let engine = AVAudioEngine()
        self.engine = engine

        let inputNode = engine.inputNode

        // Start the engine FIRST so hardware is active and format is stable
        try engine.start()
        print("🎙️ Engine started")

        // Wait for hardware to settle (avoids 0-chunk issue on 48kHz devices)
        try await Task.sleep(for: .milliseconds(200))

        // NOW read the actual active format
        let hwFormat = inputNode.outputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0 else {
            throw AudioError.noInputDevice
        }

        print("🎤 Hardware format: \(hwFormat.sampleRate)Hz, \(hwFormat.channelCount)ch, \(hwFormat.commonFormat)")

        // Install tap with the hardware's actual active format
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: hwFormat) { [weak self] buffer, time in
            self?.handleBuffer(buffer)
        }

        chunkCount = 0
        tapFired = false
        print("🎙️ Tap installed on inputNode (\(Int(hwFormat.sampleRate))Hz, bufferSize: 1024)")

        // Verify tap fires within 2 seconds
        try await Task.sleep(for: .milliseconds(500))
        if !tapFired {
            print("⚠️ Tap hasn't fired yet after 500ms — waiting longer...")
            try await Task.sleep(for: .milliseconds(1500))
            if !tapFired {
                print("❌ Tap never fired after 2s — audio device may be unavailable")
                engine.inputNode.removeTap(onBus: 0)
                engine.stop()
                self.engine = nil
                throw AudioError.noInputDevice
            }
        }
    }

    /// Stop capturing audio.
    func stop() {
        print("🛑 Audio capture stopped. Sent \(chunkCount) chunks total.")
        chunkCount = 0
        tapFired = false
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    // MARK: - Buffer Processing

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        if !tapFired {
            tapFired = true
            print("🎙️ TAP FIRED! frames=\(buffer.frameLength), rate=\(buffer.format.sampleRate)Hz")
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        guard let floatData = buffer.floatChannelData else { return }
        let samples = floatData[0]
        let srcRate = buffer.format.sampleRate
        let srcCount = frameLength

        // Downsample to 24kHz by dropping samples
        let ratio = Self.targetSampleRate / srcRate
        let outputCount = Int(Double(srcCount) * ratio)
        guard outputCount > 0 else { return }

        var pcm16 = Data(capacity: outputCount * 2)
        for i in 0..<outputCount {
            let srcIdx = min(Int(Double(i) / ratio), srcCount - 1)
            let sample = samples[srcIdx]
            let clamped = max(-1.0, min(1.0, sample))
            let intSample = Int16(clamped * 32767.0)
            pcm16.append(contentsOf: withUnsafeBytes(of: intSample.littleEndian) { Array($0) })
        }

        guard !pcm16.isEmpty else { return }

        chunkCount += 1
        if chunkCount == 1 {
            print("🎙️ First chunk: \(pcm16.count) bytes (\(outputCount) samples from \(srcCount) @ \(Int(srcRate))Hz)")
        }
        onAudioData?(pcm16)
    }
}

enum AudioError: LocalizedError {
    case unsupportedFormat
    case permissionDenied
    case notRunning
    case noInputDevice

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "Cannot convert to 24kHz PCM16"
        case .permissionDenied: return "Microphone permission denied. Grant in System Settings → Privacy."
        case .notRunning: return "Audio capture not running"
        case .noInputDevice: return "No microphone detected. Connect an external mic or headset."
        }
    }
}
