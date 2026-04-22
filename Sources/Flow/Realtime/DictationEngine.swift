import Foundation

/// Dictation mode engine using dual-path Realtime API.
///
/// Flow:
/// 1. Hotkey pressed → connect to Realtime API + start audio capture
/// 2. Audio chunks streamed to API in real-time
/// 3. Partial transcripts shown as visual feedback
/// 4. Hotkey released → commit audio → get final transcript
/// 5. Inject final text into focused text field
/// 6. Disconnect
///
/// Connection path: ChatGPT backend (free with sub) → Developer API (fallback) → Groq (last resort)
@MainActor
final class DictationEngine {
    var onStateChanged: ((FlowState) -> Void)?
    var onPartialTranscript: ((String) -> Void)?

    private let auth: ChatGPTAuth
    private let config: FlowConfig
    private let audioCapture = AudioCapture()
    private let hotkey: HotkeyManager
    private var client: DualPathRealtimeClient?
    private var groqClient: GroqWhisperClient?
    private var isConnected = false
    private var fallbackMode = false

    init(auth: ChatGPTAuth, config: FlowConfig) {
        self.auth = auth
        self.config = config

        self.hotkey = HotkeyManager(key: config.hotkey, mode: config.hotkeyMode)
        self.hotkey.onStart = { [weak self] in Task { @MainActor in await self?.startDictation() } }
        self.hotkey.onStop = { [weak self] in Task { @MainActor in await self?.finishDictation() } }
    }

    func activate() {
        hotkey.start()
        onStateChanged?(.idle)
        print("🎤 Dictation active. Press \(config.hotkey) to start.")
    }

    func deactivate() {
        hotkey.stop()
        audioCapture.stop()
        client?.disconnect()
        client = nil
        groqClient?.reset()
        groqClient = nil
        isConnected = false
    }

    // MARK: - Dictation Lifecycle

    private func startDictation() async {
        guard !isConnected else { return }
        onStateChanged?(.connecting)
        onPartialTranscript?("")

        print("🎤 Starting dictation...")

        do {
            // Ensure we have a valid token (auto-refreshes if expired)
            guard let token = await auth.ensureValidToken() else {
                print("⚠️ No valid token — please sign in again")
                onStateChanged?(.error("Session expired. Please sign in again."))
                return
            }
            _ = token // Token is now set on auth.accessToken

            let dualClient = DualPathRealtimeClient(auth: auth, config: config)
            self.client = dualClient

            // Wire callbacks
            dualClient.onPartialTranscript = { [weak self] text in
                Task { @MainActor in self?.onPartialTranscript?(text) }
            }
            dualClient.onFinalTranscript = { [weak self] text in
                Task { @MainActor in self?.handleFinalTranscript(text) }
            }
            dualClient.onBackendPathUsed = { backend in
                print(backend ? "💰 Free path (ChatGPT sub)" : "💳 Developer API path")
            }
            dualClient.onError = { [weak self] err in
                Task { @MainActor in
                    print("⚠️ Realtime error: \(err)")
                    // Try Groq fallback
                    Task { await self?.tryGroqFallback() }
                }
            }

            // Connect
            try await dualClient.connect(mode: .dictation(language: config.language))
            isConnected = true

            // Start audio capture
            audioCapture.onAudioData = { [weak self] data in
                guard let self, !self.fallbackMode else { return }
                if let groq = self.groqClient {
                    groq.appendAudio(data)
                } else {
                    dualClient.sendAudio(data)
                }
            }
            try await audioCapture.start()
            onStateChanged?(.recording)
            print("🎙️ Audio capture started — streaming to Realtime API")

        } catch {
            print("⚠️ Connect failed: \(error)")
            await tryGroqFallback()
        }
    }

    private var transcriptReceived = false

    private func finishDictation() async {
        guard isConnected || fallbackMode else { return }
        onStateChanged?(.processing)

        audioCapture.stop()
        print("🛑 Audio capture stopped")

        if fallbackMode, let groq = groqClient {
            await groq.transcribe(language: config.language)
            return
        }

        // Realtime path: commit buffer and request response
        print("📤 Committing audio buffer and requesting transcript...")
        client?.commitAndRespond()

        // Wait for final transcript (max 10s)
        // handleFinalTranscript will set transcriptReceived = true and call cleanup()
        transcriptReceived = false
        for i in 1...100 {
            if transcriptReceived { return }
            try? await Task.sleep(for: .milliseconds(100))
        }

        // Timed out — no transcript
        print("⏰ Timed out waiting for transcript (10s)")
        if isConnected || fallbackMode {
            cleanup()
            onStateChanged?(.idle)
        }
    }

    private func handleFinalTranscript(_ text: String) {
        guard isConnected else { return }
        transcriptReceived = true
        print("📝 Final transcript: \"\(text)\"")
        onStateChanged?(.injecting)

        let success = TextInjector.inject(text)
        print(success ? "✅ Text injected" : "❌ Text injection failed")
        onStateChanged?(success ? .idle : .error("Text injection failed"))
        cleanup()
    }

    // MARK: - Groq Fallback

    private func tryGroqFallback() async {
        guard let groqKey = ProcessInfo.processInfo.environment["GROQ_API_KEY"],
              !groqKey.isEmpty else {
            onStateChanged?(.error("Connection failed. Set GROQ_API_KEY for free fallback."))
            cleanup()
            return
        }

        print("🔄 Falling back to Groq Whisper (free)")
        fallbackMode = true
        isConnected = true

        let groq = GroqWhisperClient(apiKey: groqKey)
        groq.onFinalTranscript = { [weak self] text in
            Task { @MainActor in self?.handleFinalTranscript(text) }
        }
        groq.onError = { [weak self] err in
            Task { @MainActor in
                self?.onStateChanged?(.error(err))
                self?.cleanup()
            }
        }
        self.groqClient = groq

        // Start capturing again if needed
        if !audioCapture.isRunning {
            audioCapture.onAudioData = { [weak self] data in
                self?.groqClient?.appendAudio(data)
            }
            do {
                try await audioCapture.start()
                onStateChanged?(.recording)
            } catch {
                onStateChanged?(.error("Audio capture failed: \(error.localizedDescription)"))
                cleanup()
            }
        } else {
            onStateChanged?(.recording)
        }
    }

    private func cleanup() {
        client?.disconnect()
        client = nil
        groqClient?.reset()
        groqClient = nil
        isConnected = false
        fallbackMode = false
    }
}
