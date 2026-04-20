import Foundation
import AVFoundation

/// Lightweight sound effects for recording state transitions.
///
/// Uses system audio (not the AVAudioEngine we use for capture)
/// so sounds don't get captured by the mic.
final class SoundManager {
    static let shared = SoundManager()

    private var startSound: SystemSoundID?
    private var stopSound: SystemSoundID?
    private var errorSound: SystemSoundID?

    private init() {}

    enum Sound: String {
        case startRecording = "Tink"       // Recording started
        case stopRecording = "Tock"        // Recording stopped
        case success = "Hero"              // Text injected
        case error = "Basso"               // Something went wrong
    }

    /// Play a system sound.
    func play(_ sound: Sound) {
        // Use macOS system sounds
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

        guard let url = URL(string: "file://\(soundPath)"),
              let buffer = try? AVAudioPCMBuffer(url: url) else {
            // Fallback: use NSSound
            if let nsSound = NSSound(named: NSSound.Name(sound.rawValue)) {
                nsSound.play()
            }
            return
        }

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
