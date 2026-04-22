import Foundation
import AVFoundation

/// Captures microphone audio via AVAudioEngine, outputs 24kHz mono PCM16.
///
/// Uses AVAudioFormat(standardFormatWithSampleRate:) for the tap — this is the
/// non-interleaved float32 format that AVAudioEngine internally uses, which avoids
/// the "format mismatch" crash that happens with outputFormat on some devices.
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

        // Use standard format (non-interleaved float32) at hardware sample rate.
        // This is what AVAudioEngine uses internally — avoids format mismatch crashes.
        let tapFormat = AVAudioFormat(
            standardFormatWithSampleRate: hwFormat.sampleRate,
            channels: hwFormat.channelCount
        )!

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self] buffer, _ in
            self?.handleBuffer(buffer)
        }

        chunkCount = 0
        tapFired = false
        print("🎙️ Tap installed (standardFormat \(Int(hwFormat.sampleRate))Hz, \(hwFormat.channelCount)ch)")

        // Verify tap fires
        try await Task.sleep(for: .milliseconds(500))
        if !tapFired {
            print("⚠️ Tap hasn't fired after 500ms...")
            try await Task.sleep(for: .milliseconds(1500))
            if !tapFired {
                print("❌ Tap never fired")
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

enum AudioError: LocalizedError {
    case unsupportedFormat
    case permissionDenied
    case notRunning
    case noInputDevice

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "Cannot create audio tap"
        case .permissionDenied: return "Microphone permission denied"
        case .notRunning: return "Audio capture not running"
        case .noInputDevice: return "No microphone detected"
        }
    }
}
