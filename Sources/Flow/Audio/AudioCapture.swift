import Foundation
import AVFoundation

/// Captures microphone audio via AVAudioEngine, outputs 24kHz mono PCM16.
///
/// Strategy: Insert a mixer node between input and mainMixer to force format conversion,
/// then tap the mixer node. This works regardless of hardware sample rate (24kHz or 48kHz).
final class AudioCapture {
    private var engine: AVAudioEngine?
    private var mixer: AVAudioMixerNode?
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

        let hwFormat = inputNode.outputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0 else { throw AudioError.noInputDevice }
        print("🎤 Hardware: \(hwFormat.sampleRate)Hz, \(hwFormat.channelCount)ch")

        // Create a mixer node to handle format conversion
        let mixer = AVAudioMixerNode()
        engine.attach(mixer)
        self.mixer = mixer

        // Connect input → mixer with our desired format (24kHz non-interleaved float32)
        // The mixer handles the hardware→24kHz conversion automatically
        let targetFormat = AVAudioFormat(
            standardFormatWithSampleRate: Self.targetSampleRate,
            channels: 1
        )!

        engine.connect(inputNode, to: mixer, format: targetFormat)

        // Mute mainMixer so mic audio doesn't play through speakers
        engine.mainMixerNode.outputVolume = 0

        // Start the engine
        try engine.start()
        print("🎙️ Engine started with mixer (input → mixer @ \(Int(Self.targetSampleRate))Hz)")

        // Install tap on the mixer node (not inputNode!) — this always works
        // because we control the mixer's format
        mixer.installTap(onBus: 0, bufferSize: 1024, format: targetFormat) { [weak self] buffer, _ in
            self?.handleBuffer(buffer)
        }

        chunkCount = 0
        tapFired = false
        print("🎙️ Tap installed on mixerNode")

        // Verify tap fires within 2s
        try await Task.sleep(for: .milliseconds(500))
        if !tapFired {
            print("⚠️ Tap hasn't fired after 500ms...")
            try await Task.sleep(for: .milliseconds(1500))
            if !tapFired {
                print("❌ Tap never fired after 2s")
                mixer.removeTap(onBus: 0)
                engine.stop()
                self.engine = nil
                self.mixer = nil
                throw AudioError.noInputDevice
            }
        }
    }

    func stop() {
        print("🛑 Audio stopped. \(chunkCount) chunks sent.")
        chunkCount = 0
        tapFired = false
        mixer?.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        mixer = nil
    }

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        if !tapFired {
            tapFired = true
            print("🎙️ TAP FIRED! frames=\(buffer.frameLength), rate=\(buffer.format.sampleRate)Hz")
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0, let floatData = buffer.floatChannelData else { return }

        // Buffer is already 24kHz non-interleaved float32 from the mixer
        let samples = floatData[0]

        var pcm16 = Data(capacity: frameLength * 2)
        for i in 0..<frameLength {
            let clamped = max(-1.0, min(1.0, samples[i]))
            let intSample = Int16(clamped * 32767.0)
            pcm16.append(contentsOf: withUnsafeBytes(of: intSample.littleEndian) { Array($0) })
        }

        guard !pcm16.isEmpty else { return }
        chunkCount += 1
        if chunkCount == 1 {
            print("🎙️ First chunk: \(pcm16.count) bytes (\(frameLength) frames @ \(Int(buffer.format.sampleRate))Hz)")
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
