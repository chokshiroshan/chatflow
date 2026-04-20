import Foundation

/// Voice chat mode engine using dual-path Realtime API.
///
/// Full voice conversation with ChatGPT:
/// - Continuous audio capture → API
/// - Server-side VAD detects when you speak
/// - Model responds with voice + text
/// - Natural back-and-forth conversation
///
/// Uses ChatGPT backend path (free with subscription) when available.
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
    private var client: DualPathRealtimeClient?
    private var isActive = false
    private var currentRole: Role = .idle
    private var responseText = ""

    private enum Role { case idle, user, assistant }

    init(auth: ChatGPTAuth, config: FlowConfig) {
        self.auth = auth
        self.config = config
    }

    func start() async {
        guard !isActive else { return }
        onStateChanged?(.connecting)
        print("💬 Starting voice chat...")

        do {
            let dualClient = DualPathRealtimeClient(auth: auth, config: config)
            self.client = dualClient

            dualClient.onPartialTranscript = { [weak self] text in
                Task { @MainActor in self?.handlePartial(text) }
            }
            dualClient.onFinalTranscript = { [weak self] text in
                Task { @MainActor in self?.handleFinal(text) }
            }
            dualClient.onAudioResponse = { [weak self] data in
                Task { @MainActor in self?.audioPlayer.play(data) }
            }
            dualClient.onSpeechStarted = { [weak self] in
                Task { @MainActor in
                    self?.currentRole = .user
                    self?.onStateChanged?(.recording)
                }
            }
            dualClient.onSpeechEnded = { [weak self] in
                Task { @MainActor in
                    self?.currentRole = .assistant
                    self?.onStateChanged?(.speaking)
                }
            }
            dualClient.onResponseComplete = { [weak self] in
                Task { @MainActor in
                    self?.currentRole = .idle
                    self?.onStateChanged?(.idle)
                }
            }
            dualClient.onError = { [weak self] err in
                Task { @MainActor in
                    self?.onError?(err)
                    self?.stop()
                }
            }
            dualClient.onBackendPathUsed = { backend in
                print(backend ? "💰 Voice chat: free path" : "💳 Voice chat: developer API")
            }

            try await dualClient.connect(mode: .voiceChat(voice: config.voiceChatVoice))

            audioCapture.onAudioData = { [weak dualClient] data in
                dualClient?.sendAudio(data)
            }
            try audioCapture.start()
            try audioPlayer.start()

            isActive = true
            onStateChanged?(.idle)
            print("💬 Voice chat active. Speak naturally.")

        } catch {
            onError?(error.localizedDescription)
            stop()
        }
    }

    func stop() {
        audioCapture.stop()
        audioPlayer.stop()
        client?.disconnect()
        client = nil
        isActive = false
        responseText = ""
        currentRole = .idle
        onStateChanged?(.idle)
    }

    func interrupt() {
        client?.cancelResponse()
    }

    // MARK: - Transcripts

    private func handlePartial(_ text: String) {
        responseText = text
        switch currentRole {
        case .user: onUserTranscript?(text)
        case .assistant: onAssistantTranscript?(text)
        case .idle: break
        }
    }

    private func handleFinal(_ text: String) {
        responseText = text
        switch currentRole {
        case .user: onUserTranscript?(text)
        case .assistant: onAssistantTranscript?(text)
        case .idle: break
        }
    }
}
