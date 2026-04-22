import Foundation

/// Dictation mode engine using dual-path Realtime API.
///
/// Flow:
/// 1. On activate: pre-connect WebSocket + warm up audio
/// 2. Hotkey pressed → start audio capture (instant, WebSocket already connected)
/// 3. Audio chunks streamed to API in real-time
/// 4. Hotkey released → commit audio → get final transcript
/// 5. Inject final text into focused text field
/// 6. Keep WebSocket alive for next session
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
    private var isPreConnected = false
    private var chunkCount = 0

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

        // Pre-connect WebSocket in background so first dictation is instant
        Task {
            await preConnect()
        }
    }

    func deactivate() {
        hotkey.stop()
        audioCapture.stop()
        client?.disconnect()
        client = nil
        groqClient?.reset()
        groqClient = nil
        isConnected = false
        isPreConnected = false
    }

    // MARK: - Pre-connection

    private func preConnect() async {
        guard !isPreConnected else { return }

        do {
            guard let token = await auth.ensureValidToken() else {
                print("⚠️ No valid token for pre-connect")
                return
            }
            _ = token

            let dualClient = DualPathRealtimeClient(auth: auth, config: config)
            wireClientCallbacks(dualClient)

            try await dualClient.connect(mode: .dictation(language: config.language))
            self.client = dualClient
            isPreConnected = true
            isConnected = true
            print("⚡️ Pre-connected to Realtime API — ready for instant dictation")
        } catch {
            print("⚠️ Pre-connect failed: \(error) — will connect on first hotkey press")
        }
    }

    // MARK: - Dictation Lifecycle

    private func startDictation() async {
        guard !isConnected || !audioCapture.isRunning else { return }
        onPartialTranscript?("")
        chunkCount = 0

        // If not pre-connected, connect now (shows "connecting" state)
        if !isPreConnected {
            onStateChanged?(.connecting)
            print("🎤 Starting dictation (connecting...)")

            do {
                guard let token = await auth.ensureValidToken() else {
                    print("⚠️ No valid token — please sign in again")
                    onStateChanged?(.error("Session expired. Please sign in again."))
                    return
                }
                _ = token

                let dualClient = DualPathRealtimeClient(auth: auth, config: config)
                wireClientCallbacks(dualClient)

                try await dualClient.connect(mode: .dictation(language: config.language))
                self.client = dualClient
                isConnected = true
                isPreConnected = true
            } catch {
                print("⚠️ Connect failed: \(error)")
                await tryGroqFallback()
                return
            }
        } else {
            print("🎤 Starting dictation (instant — already connected)")
        }

        // Start audio capture
        audioCapture.onAudioData = { [weak self] data in
            guard let self, !self.fallbackMode else { return }
            self.chunkCount += 1
            if let groq = self.groqClient {
                groq.appendAudio(data)
            } else {
                self.client?.sendAudio(data)
            }
        }

        do {
            try audioCapture.start()
            onStateChanged?(.recording)
            print("🎙️ Recording started (\(chunkCount) chunks will stream)")
        } catch {
            print("⚠️ Audio capture failed: \(error)")
            onStateChanged?(.error("Audio capture failed: \(error.localizedDescription)"))
            cleanup()
        }
    }

    private var transcriptReceived = false

    private func finishDictation() async {
        guard isConnected || fallbackMode else { return }

        // Stop audio capture first
        audioCapture.stop()
        let chunksSent = chunkCount
        print("🛑 Audio stopped (\(chunksSent) chunks sent)")

        // Guard: if we sent very few chunks, the buffer might be too small
        if chunksSent == 0 {
            print("⚠️ No audio chunks sent — skipping commit")
            cleanup()
            onStateChanged?(.idle)
            // Re-connect for next session since we can't reuse after skipping
            isPreConnected = false
            Task { await preConnect() }
            return
        }

        onStateChanged?(.processing)

        if fallbackMode, let groq = groqClient {
            await groq.transcribe(language: config.language)
            return
        }

        // Give WebSocket a moment to flush pending audio chunks
        try? await Task.sleep(for: .milliseconds(200))

        // Commit buffer and request response
        print("📤 Committing audio buffer and requesting transcript...")
        client?.commitAndRespond()

        // Wait for final transcript (max 10s)
        transcriptReceived = false
        for _ in 1...100 {
            if transcriptReceived { return }
            try? await Task.sleep(for: .milliseconds(100))
        }

        // Timed out
        print("⏰ Timed out waiting for transcript (10s)")
        if isConnected || fallbackMode {
            cleanup()
            onStateChanged?(.idle)
            // Re-connect for next session
            isPreConnected = false
            Task { await preConnect() }
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

        // Re-connect for next session
        isPreConnected = false
        Task { await preConnect() }
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

    // MARK: - Wiring

    private func wireClientCallbacks(_ dualClient: DualPathRealtimeClient) {
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
                Task { await self?.tryGroqFallback() }
            }
        }
    }

    private func cleanup() {
        client?.disconnect()
        client = nil
        groqClient?.reset()
        groqClient = nil
        isConnected = false
        fallbackMode = false
        chunkCount = 0
    }
}
