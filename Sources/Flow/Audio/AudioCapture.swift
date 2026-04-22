import Foundation
import AVFoundation

/// Captures microphone audio via AVAudioEngine, outputs 24kHz mono PCM16.
///
/// Strategy: Tap inputNode with nil format (uses its native format),
/// then manually convert float32 → int16 and downsample 48kHz → 24kHz.
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
        let hwFormat = inputNode.outputFormat(forBus: 0)

        guard hwFormat.sampleRate > 0 else {
            throw AudioError.noInputDevice
        }

        print("🎤 Hardware format: \(hwFormat.sampleRate)Hz, \(hwFormat.channelCount)ch, \(hwFormat.commonFormat)")
        print("🎤 Is interleaved: \(hwFormat.isInterleaved)")

        // Tap with nil format = use the node's own format (no format conversion at tap level)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: nil) { [weak self] buffer, time in
            self?.handleBuffer(buffer)
        }

        try engine.start()
        print("🎙️ Engine started. Waiting for audio...")
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
            print("🎙️ TAP FIRED! frames=\(buffer.frameLength), channels=\(buffer.format.channelCount), format=\(buffer.format.commonFormat)")
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        // Get float32 channel data (non-interleaved: each channel is a separate array)
        guard let floatData = buffer.floatChannelData else {
            print("⚠️ No float channel data")
            return
        }

        // Channel 0 (mono)
        let samples = floatData[0]
        let sampleCount = frameLength

        // Downsample 48kHz → 24kHz by dropping every other sample
        let srcRate = buffer.format.sampleRate
        let ratio = Self.targetSampleRate / srcRate  // 0.5 for 48→24
        let outputCount = Int(Double(sampleCount) * ratio)
        guard outputCount > 0 else { return }

        var pcm16Data = Data(capacity: outputCount * 2)

        for i in 0..<outputCount {
            let srcIdx = Int(Double(i) / ratio)
            guard srcIdx < sampleCount else { break }
            let sample = samples[srcIdx]
            // Clamp to [-1.0, 1.0] then convert to Int16
            let clamped = max(-1.0, min(1.0, sample))
            let intSample = Int16(clamped * 32767.0)
            pcm16Data.append(contentsOf: withUnsafeBytes(of: intSample.littleEndian) { Array($0) })
        }

        guard !pcm16Data.isEmpty else { return }

        chunkCount += 1
        if chunkCount == 1 {
            print("🎙️ First audio chunk! \(pcm16Data.count) bytes (\(outputCount) samples)")
        }
        onAudioData?(pcm16Data)
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
