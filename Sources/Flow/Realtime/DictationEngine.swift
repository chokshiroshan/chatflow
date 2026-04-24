import Foundation

/// Dictation engine using OpenAI's Realtime API for streaming transcription.
///
/// Strategy: Connect to gpt-realtime WebSocket, stream audio in real-time.
/// Uses server-side transcription via `input_audio_transcription` with
/// the gpt-4o-mini-transcribe model for accurate STT.
///
/// Auth: ChatGPT subscription token via Codex OAuth
/// STT: gpt-4o-mini-transcribe via Realtime API's input_audio_transcription
@MainActor
final class DictationEngine {
    var onStateChanged: ((FlowState) -> Void)?
    var onPartialTranscript: ((String) -> Void)?

    private let auth: ChatGPTAuth
    private let config: FlowConfig
    private let audioCapture = AudioCapture()
    private let hotkey: HotkeyManager
    private var client: RealtimeClient?
    private var isRecording = false
    private var isConnected = false
    private var chunkCount = 0
    private var transcriptReceived = false
    private var lastTranscript = ""
    private var isFinishing = false  // Guard against double-finish
    private(set) var isEnhancedMode = false  // Screen context mode
    private var screenContextInjected = false  // Whether vision context was applied

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
        Task { await preConnect() }
    }

    func deactivate() {
        hotkey.stop()
        audioCapture.stop()
        client?.disconnect()
        client = nil
        isRecording = false
        isConnected = false
        isReconnecting = false
        reconnectAttempts = 0  // Reset on clean shutdown
    }

    /// Update hotkey at runtime without restarting the engine (WisprFlow pattern).
    func updateHotkey(_ newKey: String) {
        hotkey.updateCombo(newKey)
        print("🎤 Hotkey updated to: \(newKey) — no engine restart needed")
    }

    // MARK: - Pre-connect

    private func preConnect() async {
        guard !isConnected else { return }

        do {
            guard let token = await auth.ensureValidToken() else {
                print("⚠️ No valid token for pre-connect")
                return
            }

            let client = RealtimeClient()
            wireCallbacks(client)

            try await client.connect(accessToken: token, model: config.realtimeModel, mode: .dictation(language: config.language))
            self.client = client

            isConnected = true
            print("⚡️ Pre-connected — ready for instant dictation")
        } catch {
            print("⚠️ Pre-connect failed: \(error) — will connect on first hotkey press")
        }
    }

    // MARK: - Dictation Lifecycle

    private func startDictation() async {
        // If still finishing previous session, force-complete it
        if isFinishing {
            print("⚠️ Still finishing previous — force completing")
            forceCompletePrevious()
        }

        guard !isRecording else {
            print("⚠️ Already recording — forcing stop first")
            await finishDictation()
            return
        }

        // Connect if not pre-connected
        if !isConnected {
            // If reconnecting in background, just wait briefly for it
            if isReconnecting {
                print("⏳ Waiting for reconnect to complete...")
                for _ in 1...20 {
                    if isConnected { break }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            
            // Still not connected? Do it ourselves
            if !isConnected {
                isReconnecting = false  // Cancel pending reconnect
                onStateChanged?(.connecting)
                do {
                    guard let token = await auth.ensureValidToken() else {
                        onStateChanged?(.error("Session expired. Please sign in again."))
                        return
                    }

                    let client = RealtimeClient()
                    wireCallbacks(client)
                    try await client.connect(accessToken: token, model: config.realtimeModel, mode: .dictation(language: config.language))
                    self.client = client
                    isConnected = true
                } catch {
                    print("⚠️ Connect failed: \(error)")
                    onStateChanged?(.error("Connection failed: \(error.localizedDescription)"))
                    return
                }
            }
        }

        // Refresh instructions with current active app
        client?.refreshInstructions(language: config.language)

        isRecording = true
        isFinishing = false
        chunkCount = 0
        transcriptReceived = false
        lastTranscript = ""
        screenContextInjected = false
        onPartialTranscript?("")

        // Check for enhanced mode (Shift held during hotkey press)
        // Uses curKeysDown tracking from HotkeyManager for reliable state
        isEnhancedMode = hotkey.isEnhancedTrigger
        if isEnhancedMode {
            print("📸 Enhanced mode — capturing screen context...")
            Task {
                guard let token = await auth.ensureValidToken() else { return }
                if let screenContext = await ScreenContextExtractor.shared.extractContext(token: token) {
                    // Inject screen context into the live session
                    await injectScreenContext(screenContext)
                }
            }
        }

        // Wire audio callback — stream chunks to WebSocket
        audioCapture.onAudioData = { [weak self] data in
            guard let self else { return }
            self.chunkCount += 1
            self.client?.sendAudio(data)
        }

        do {
            try audioCapture.start()
            onStateChanged?(.recording)
            print("🎙️ Recording started")
        } catch {
            print("⚠️ Audio capture failed: \(error)")
            onStateChanged?(.error("Audio capture failed: \(error.localizedDescription)"))
            isRecording = false
        }
    }

    private func finishDictation() async {
        guard isRecording else { return }
        guard !isFinishing else { return }  // Prevent double-finish
        isRecording = false
        isFinishing = true

        audioCapture.stop()
        let chunks = chunkCount
        print("🛑 Recording stopped (\(chunks) chunks)")

        // Need at least a few chunks (half a second of audio)
        guard chunks > 12 else {
            print("⚠️ Too few chunks — cancelling response")
            client?.cancelResponse()  // Don't let the model hallucinate
            onStateChanged?(.idle)
            isFinishing = false
            reconnect()
            return
        }

        // Immediately show processing state
        onStateChanged?(.processing)

        // Make sure we're connected before committing
        guard let client, isConnected else {
            print("⚠️ Not connected — reconnecting")
            onStateChanged?(.idle)
            isFinishing = false
            reconnect()
            return
        }

        // Commit immediately — audio was already streamed in real-time
        client.commitAndRespond()
        print("📤 Committed buffer, waiting for transcript...")

        // Wait for transcript (max 5s)
        transcriptReceived = false
        for _ in 1...50 {
            if transcriptReceived { return }
            try? await Task.sleep(for: .milliseconds(100))
        }

        // Timed out
        print("⏰ Timed out waiting for transcript (5s)")
        onStateChanged?(.idle)
        isFinishing = false
        reconnect()
    }

    /// Force-complete if stuck in finishing state
    private func forceCompletePrevious() {
        audioCapture.stop()
        isRecording = false
        isFinishing = false
        onStateChanged?(.idle)
    }

    /// Inject screen context into the live Realtime API session.
    /// This updates instructions mid-recording so the transcription model
    /// can use what's on screen for better accuracy.
    @MainActor
    private func injectScreenContext(_ context: String) {
        guard isRecording, !screenContextInjected else { return }
        screenContextInjected = true

        let instructions = ContextManager.shared.buildInstructions(
            screenContext: context
        )

        let event = """
        {"type":"session.update","session":{"instructions":"\(instructions.escapingJSON)","input_audio_transcription":{"model":"gpt-4o-mini-transcribe","language":"\(config.language)"}}}
        """
        try? client?.send(event)
        print("📸 Screen context injected into session")
    }

    private func handleTranscript(_ text: String) {
        transcriptReceived = true
        lastTranscript = text
        isFinishing = false

        // Skip empty transcripts
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            print("⚠️ Empty transcript")
            onStateChanged?(.idle)
            reconnect()
            return
        }

        print("📝 Transcript: \"\(cleaned)\"")
        onStateChanged?(.injecting)

        let result = TextInjector.injectWithResult(cleaned)
        switch result {
        case .success:
            print("✅ Text injected successfully")
            onStateChanged?(.idle)
        case .failed(let reason):
            print("❌ Text injection failed: \(reason)")
            onStateChanged?(.error("Text injection failed: \(reason)"))
        case .blocked:
            print("⚠️ Text injection blocked (readonly field?)")
            onStateChanged?(.error("Paste blocked — text field may be readonly"))
        }

        // Reconnect for next session
        reconnect()
    }

    private var reconnectAttempts = 0
    private var isReconnecting = false

    private func reconnect() {
        client?.disconnect()
        client = nil
        isConnected = false
        isReconnecting = true
        reconnectAttempts += 1

        // Exponential backoff: 1s, 2s, 4s, 8s, max 5s
        let delay = min(Double(reconnectAttempts), 5) * 1.0
        print("🔄 Reconnecting in \(delay)s (attempt \(reconnectAttempts))...")

        Task {
            try? await Task.sleep(for: .seconds(delay))
            isReconnecting = false
            await preConnect()
            if isConnected { reconnectAttempts = 0 }
        }
    }

    // MARK: - Callbacks

    private func wireCallbacks(_ client: RealtimeClient) {
        // Transcription events — this is the accurate STT
        client.onFinalTranscript = { [weak self] text in
            Task { @MainActor in self?.handleTranscript(text) }
        }
        client.onPartialTranscript = { [weak self] text in
            Task { @MainActor in self?.onPartialTranscript?(text) }
        }
        client.onError = { [weak self] err in
            Task { @MainActor in
                print("⚠️ Realtime error: \(err)")
                // Only show error if we were actually recording
                if self?.isRecording == true || self?.isFinishing == true {
                    self?.onStateChanged?(.error(err))
                    self?.isRecording = false
                    self?.isFinishing = false
                }
                self?.reconnect()
            }
        }
    }
}
