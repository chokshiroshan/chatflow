import Foundation
import AppKit

/// Lightweight sound effects for recording state transitions.
///
/// Uses NSSound for system sounds — simple, doesn't interfere with audio capture.
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
        NSSound(named: NSSound.Name(sound.rawValue))?.play()
    }
}
