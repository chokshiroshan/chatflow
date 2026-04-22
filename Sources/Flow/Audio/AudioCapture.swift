import Foundation
import AVFoundation

/// Captures microphone audio via AVAudioEngine, outputs 24kHz mono PCM16.
///
/// Strategy: Connect inputNode → mixer at HARDWARE format (avoids connect crash),
/// then tap the mixer node at hardware format (mixer is not an IO node, so taps work),
/// then downsample to 24kHz in the callback.
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

        // Read hardware format BEFORE starting
        let hwFormat = inputNode.outputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0 else { throw AudioError.noInputDevice }
        print("🎤 Hardware: \(hwFormat.sampleRate)Hz, \(hwFormat.channelCount)ch, interleaved=\(hwFormat.isInterleaved)")

        // Create mixer and connect input → mixer at HARDWARE format
        // (can't use 24kHz here — "Input HW format and tap format not matching" crash)
        let mixer = AVAudioMixerNode()
        engine.attach(mixer)
        self.mixer = mixer
        engine.connect(inputNode, to: mixer, format: hwFormat)

        // Mute output so mic doesn't play through speakers
        engine.mainMixerNode.outputVolume = 0

        // Start engine
        try engine.start()
        print("🎙️ Engine started (input → mixer @ \(Int(hwFormat.sampleRate))Hz)")

        // Small settle delay
        try await Task.sleep(for: .milliseconds(200))

        // Read mixer's actual output format after engine is running
        let mixerFormat = mixer.outputFormat(forBus: 0)
        print("🎤 Mixer output: \(mixerFormat.sampleRate)Hz, \(mixerFormat.channelCount)ch, interleaved=\(mixerFormat.isInterleaved)")

        // Tap the mixer node at its own output format
        mixer.installTap(onBus: 0, bufferSize: 1024, format: mixerFormat) { [weak self] buffer, _ in
            self?.handleBuffer(buffer)
        }

        chunkCount = 0
        tapFired = false
        print("🎙️ Tap installed on mixer (\(Int(mixerFormat.sampleRate))Hz)")

        // Verify tap fires
        try await Task.sleep(for: .milliseconds(500))
        if !tapFired {
            print("⚠️ Tap hasn't fired after 500ms...")
            try await Task.sleep(for: .milliseconds(1500))
            if !tapFired {
                print("❌ Tap never fired")
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
            print("🎙️ First chunk: \(pcm16.count) bytes (\(outputCount) samples from \(frameLength) @ \(Int(srcRate))Hz → \(Int(Self.targetSampleRate))Hz)")
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
