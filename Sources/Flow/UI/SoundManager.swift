import Foundation
import AVFoundation
import AppKit

/// Lightweight sound effects for recording state transitions.
///
/// Uses system audio (not the AVAudioEngine we use for capture)
/// so sounds don't get captured by the mic.
final class SoundManager {
    static let shared = SoundManager()

    private init() {}

    enum Sound: String {
        case startRecording = "Tink"       // Recording started
        case stopRecording = "Tock"        // Recording stopped
        case success = "Hero"              // Text injected
        case error = "Basso"               // Something went wrong
    }

    /// Play a system sound.
    func play(_ sound: Sound) {
        // Use NSSound for system sounds — simple, reliable, doesn't interfere with audio capture
        if let nsSound = NSSound(named: NSSound.Name(sound.rawValue)) {
            nsSound.play()
            return
        }

        // Fallback: play via file URL
        let soundPath: String
        switch sound {
        case .startRecording:
            soundPath = "/System/Library/Sounds/Tink.aiff"
        case .stopRecording:
            soundPath = "/System/Library/Sounds/Tock.aiff"
        case .success:
            soundPath = "/System/Library/Sounds/Hero.aiff"
        case .error:
            soundPath = "/System/Library/Sounds/Basso.aiff"
        }

        let url = URL(fileURLWithPath: soundPath)
        guard let audioFile = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: AVAudioFrameCount(audioFile.length)) else { return }
        try? audioFile.read(into: buffer)

        // Play via a separate audio player (not the capture engine)
        Task.detached {
            let engine = AVAudioEngine()
            let playerNode = AVAudioPlayerNode()
            engine.attach(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: buffer.format)
            try? engine.start()
            playerNode.scheduleBuffer(buffer, at: nil, options: [])
            playerNode.play()

            // Keep alive while playing
            let duration = Double(buffer.frameLength) / buffer.format.sampleRate
            try? await Task.sleep(for: .seconds(duration + 0.1))
            engine.stop()
        }
    }
}
