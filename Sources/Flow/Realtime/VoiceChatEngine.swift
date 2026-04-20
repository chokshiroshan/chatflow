import Foundation

/// The voice chat mode engine — real-time voice conversation with ChatGPT.
///
/// Flow:
/// 1. User activates voice chat
/// 2. Connects to Realtime API with audio+text modalities
/// 3. Server-side VAD detects when user speaks
/// 4. Audio continuously streamed in both directions
/// 5. Model responds with voice + transcript
/// 6. Natural back-and-forth conversation
@MainActor
final class VoiceChatEngine {
    var onStateChanged: ((FlowState) -> Void)?
    var onUserTranscript: ((String) -> Void)?
    var onAssistantTranscript: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private let auth: ChatGPTAuth
    private let config: FlowConfig
    private let audioCapture = AudioCapture()
    private let audioPlayer = AudioPlayer()
    private var client: RealtimeClient?
    private var isActive = false
    private var currentResponseText = ""
    private var currentRole: Role = .idle

    private enum Role {
        case idle
        case user
        case assistant
    }

    init(auth: ChatGPTAuth, config: FlowConfig) {
        self.auth = auth
        self.config = config
    }

    /// Start a voice chat session.
    func start() async {
        guard !isActive else { return }
        onStateChanged?(.connecting)
        print("💬 Starting voice chat...")

        do {
            let token = try await auth.getAccessToken()
            let client = RealtimeClient()
            self.client = client

            // Wire callbacks
            client.onPartialTranscript = { [weak self] text in
                Task { @MainActor in self?.handlePartialTranscript(text) }
            }
            client.onFinalTranscript = { [weak self] text in
                Task { @MainActor in self?.handleFinalTranscript(text) }
            }
            client.onAudioResponse = { [weak self] data in
                Task { @MainActor in self?.audioPlayer.play(data) }
            }
            client.onSpeechStarted = { [weak self] in
                Task { @MainActor in
                    self?.currentRole = .user
                    self?.onStateChanged?(.recording)
                }
            }
            client.onSpeechEnded = { [weak self] in
                Task { @MainActor in
                    self?.currentRole = .assistant
                    self?.onStateChanged?(.speaking)
                }
            }
            client.onResponseComplete = { [weak self] in
                Task { @MainActor in
                    self?.currentRole = .idle
                    self?.onStateChanged?(.idle)
                }
            }
            client.onError = { [weak self] err in
                Task { @MainActor in
                    self?.onError?(err)
                    self?.stop()
                }
            }
            client.onDisconnected = { [weak self] in
                Task { @MainActor in
                    self?.isActive = false
                    self?.onStateChanged?(.idle)
                }
            }

            // Connect in voice chat mode
            try await client.connect(
                accessToken: token,
                model: config.realtimeModel,
                mode: .voiceChat(voice: config.voiceChatVoice)
            )

            // Start audio capture (continuous)
            audioCapture.onAudioData = { [weak client] data in
                client?.sendAudio(data)
            }
            try audioCapture.start()

            // Start audio player
            try audioPlayer.start()

            isActive = true
            onStateChanged?(.idle)
            print("💬 Voice chat active. Speak naturally.")

        } catch {
            onError?(error.localizedDescription)
            stop()
        }
    }

    /// Stop the voice chat session.
    func stop() {
        audioCapture.stop()
        audioPlayer.stop()
        client?.disconnect()
        client = nil
        isActive = false
        currentResponseText = ""
        currentRole = .idle
        onStateChanged?(.idle)
        print("💬 Voice chat stopped.")
    }

    /// Interrupt the model's current response (barge-in).
    func interrupt() {
        client?.cancelResponse()
        audioPlayer.stop()
    }

    // MARK: - Transcript Handling

    private func handlePartialTranscript(_ text: String) {
        currentResponseText = text
        switch currentRole {
        case .user:   onUserTranscript?(text)
        case .assistant: onAssistantTranscript?(text)
        case .idle:   break
        }
    }

    private func handleFinalTranscript(_ text: String) {
        currentResponseText = text
        switch currentRole {
        case .user:   onUserTranscript?(text)
        case .assistant: onAssistantTranscript?(text)
        case .idle:   break
        }
    }
}
