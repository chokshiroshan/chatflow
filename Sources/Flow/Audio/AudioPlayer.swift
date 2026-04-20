import Foundation
import AVFoundation

/// Plays audio received from the Realtime API (voice chat mode).
///
/// Receives PCM16 audio chunks from the server and plays them through
/// the default output device with minimal latency.
final class AudioPlayer {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let format: AVAudioFormat

    /// PCM16 24kHz mono — matches what the Realtime API sends
    static let playbackFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24000.0,
        channels: 1,
        interleaved: true
    )!

    init() {
        self.format = Self.playbackFormat
    }

    /// Start the audio player.
    func start() throws {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        try engine.start()
        playerNode.play()
        print("🔊 Audio playback ready")
    }

    /// Play a chunk of PCM16 audio data.
    func play(_ pcm16Data: Data) {
        // Convert PCM16 Data → AVAudioPCMBuffer
        let frameCount = UInt32(pcm16Data.count) / 2 // 2 bytes per Int16 sample

        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
              ) else { return }

        pcm16Data.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress {
                memcpy(buffer.int16ChannelData![0], baseAddress, pcm16Data.count)
            }
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        playerNode.scheduleBuffer(buffer) { }
    }

    /// Stop all playback.
    func stop() {
        playerNode.stop()
        engine.stop()
        print("🔇 Audio playback stopped")
    }

    /// Check if currently playing.
    var isPlaying: Bool {
        engine.isRunning && playerNode.isPlaying
    }
}
