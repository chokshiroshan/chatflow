import Foundation
import AVFoundation

/// Captures microphone audio via AVAudioEngine, outputs 24kHz mono PCM16.
///
/// The OpenAI Realtime API expects:
/// - Format: PCM16 (signed 16-bit LE)
/// - Sample rate: 24000 Hz
/// - Channels: 1 (mono)
///
/// Apple Silicon hardware captures at 48kHz natively, so we convert.
final class AudioCapture {
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var chunkCount = 0

    /// Whether the audio engine is currently capturing.
    var isRunning: Bool {
        engine?.isRunning ?? false
    }

    /// Target format: 24kHz mono PCM16 (what OpenAI Realtime expects)
    static let targetSampleRate: Double = 24000.0
    static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: targetSampleRate,
        channels: 1,
        interleaved: true
    )!

    /// Called with PCM16 audio data (24kHz mono, little-endian).
    var onAudioData: ((Data) -> Void)?

    /// Start capturing audio from default microphone.
    func start() async throws {
        // Request microphone permission first
        let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }

        guard granted else {
            throw AudioError.permissionDenied
        }

        let engine = AVAudioEngine()
        self.engine = engine

        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        
        print("🎤 Input format: \(hardwareFormat.sampleRate)Hz, \(hardwareFormat.channelCount) channels, \(hardwareFormat.commonFormat)")
        
        if hardwareFormat.sampleRate == 0 {
            print("❌ No audio input device detected! Mac minis need an external mic.")
            throw AudioError.noInputDevice
        }

        let targetFormat = Self.targetFormat

        // Create converter from hardware format to target format
        guard let newConverter = AVAudioConverter(from: hardwareFormat, to: targetFormat) else {
            throw AudioError.unsupportedFormat
        }
        self.converter = newConverter

        // Connect input → mainMixer so the graph is active
        let mixer = engine.mainMixerNode
        engine.connect(inputNode, to: mixer, format: hardwareFormat)
        mixer.outputVolume = 0  // Mute to prevent feedback

        // Start engine FIRST, then install tap
        try engine.start()
        print("🎙️ Engine started. Installing tap...")
        
        // Install tap AFTER engine start — macOS requirement
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
            self?.processBuffer(buffer, sourceFormat: hardwareFormat)
        }
        
        print("🎙️ Tap installed on input node (format: \(Int(hardwareFormat.sampleRate))Hz, \(hardwareFormat.channelCount)ch)")
        
        // Verify tap is active
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            print("🎙️ After 0.5s: \(self.chunkCount) chunks received, engine running: \(self.engine?.isRunning ?? false)")
        }
    }

    /// Stop capturing audio.
    func stop() {
        print("🛑 Audio capture stopped. Sent \(chunkCount) chunks total.")
        chunkCount = 0
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        converter = nil
    }

    // MARK: - Processing

    private func processBuffer(_ buffer: AVAudioPCMBuffer, sourceFormat: AVAudioFormat) {
        guard let converter = self.converter else { return }
        let targetFormat = Self.targetFormat

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCount
        ) else { return }

        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        if let error = error {
            print("⚠️ Audio conversion error: \(error)")
            return
        }

        let outFrames = Int(outputBuffer.frameLength)
        if outFrames == 0 { return }

        if let channelData = outputBuffer.int16ChannelData {
            let channels = Int(targetFormat.channelCount)
            let bytesToCopy = outFrames * channels * MemoryLayout<Int16>.size
            let data = Data(bytes: channelData[0], count: bytesToCopy)
            chunkCount += 1
            if chunkCount == 1 {
                print("🎙️ First audio chunk: \(data.count) bytes (\(outFrames) frames)")
            }
            onAudioData?(data)
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
        case .unsupportedFormat: return "Cannot convert to 24kHz PCM16"
        case .permissionDenied: return "Microphone permission denied. Grant in System Settings → Privacy."
        case .notRunning: return "Audio capture not running"
        case .noInputDevice: return "No microphone detected. Connect an external mic or headset (Mac minis have no built-in mic)."
        }
    }
}
