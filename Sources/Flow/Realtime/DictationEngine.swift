import Foundation

/// The dictation mode engine.
///
/// Flow:
/// 1. Hotkey pressed → start audio capture + connect to Realtime API
/// 2. Audio chunks streamed to API in real-time
/// 3. Partial transcripts shown as feedback
/// 4. Hotkey released → commit audio → get final transcript
/// 5. Inject final text into focused text field
/// 6. Disconnect
@MainActor
final class DictationEngine {
    var onStateChanged: ((FlowState) -> Void)?
    var onPartialTranscript: ((String) -> Void)?

    private let auth: ChatGPTAuth
    private let config: FlowConfig
    private let audioCapture = AudioCapture()
    private let hotkey: HotkeyManager
    private var client: RealtimeClient?
    private var isConnected = false

    init(auth: ChatGPTAuth, config: FlowConfig) {
        self.auth = auth
        self.config = config

        self.hotkey = HotkeyManager(key: config.hotkey, mode: config.hotkeyMode)
        self.hotkey.onStart = { [weak self] in Task { @MainActor in await self?.startDictation() } }
        self.hotkey.onStop = { [weak self] in Task { @MainActor in await self?.finishDictation() } }
    }

    /// Start listening for the hotkey.
    func activate() {
        hotkey.start()
        onStateChanged?(.idle)
        print("🎤 Dictation mode active. Press \(config.hotkey) to start.")
    }

    /// Stop everything.
    func deactivate() {
        hotkey.stop()
        audioCapture.stop()
        client?.disconnect()
        client = nil
        isConnected = false
    }

    // MARK: - Dictation Lifecycle

    private func startDictation() async {
        guard !isConnected else { return }
        onStateChanged?(.connecting)
        onPartialTranscript?("")
        print("🎤 Starting dictation...")

        do {
            let token = try await auth.getAccessToken()
            let client = RealtimeClient()
            self.client = client

            // Wire up callbacks
            client.onPartialTranscript = { [weak self] text in
                Task { @MainActor in self?.onPartialTranscript?(text) }
            }
            client.onFinalTranscript = { [weak self] text in
                Task { @MainActor in self?.handleFinalTranscript(text) }
            }
            client.onError = { [weak self] err in
                Task { @MainActor in
                    self?.onStateChanged?(.error(err))
                    self?.cleanup()
                }
            }

            // Connect to Realtime API in dictation mode
            try await client.connect(
                accessToken: token,
                model: config.realtimeModel,
                mode: .dictation(language: config.language)
            )

            isConnected = true

            // Start audio capture
            audioCapture.onAudioData = { [weak client] data in
                client?.sendAudio(data)
            }
            try audioCapture.start()

            onStateChanged?(.recording)

        } catch {
            onStateChanged?(.error(error.localizedDescription))
            cleanup()
        }
    }

    private func finishDictation() async {
        guard isConnected else { return }
        onStateChanged?(.processing)

        // Stop capturing
        audioCapture.stop()

        // Commit audio buffer and request transcription
        client?.commitAndRespond()

        // Wait for final transcript (handled by handleFinalTranscript callback)
        // Timeout after 5 seconds
        try? await Task.sleep(for: .seconds(5))
        if isConnected {
            // If we didn't get a final transcript, disconnect anyway
            cleanup()
            onStateChanged?(.idle)
        }
    }

    private func handleFinalTranscript(_ text: String) {
        guard isConnected else { return }
        onStateChanged?(.injecting)

        // Inject text into focused field
        let success = TextInjector.inject(text)

        if success {
            onStateChanged?(.idle)
        } else {
            onStateChanged?(.error("Text injection failed"))
        }

        cleanup()
    }

    private func cleanup() {
        client?.disconnect()
        client = nil
        isConnected = false
    }
}
