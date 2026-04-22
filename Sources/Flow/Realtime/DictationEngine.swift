import Foundation

/// Dictation engine using Realtime API with Whisper transcription.
///
/// Strategy: Connect to gpt-realtime WebSocket, stream audio in real-time,
/// but use the server-side Whisper transcription (`input_audio_transcription`)
/// instead of the model's own text generation. This gives Whisper accuracy
/// with the Realtime API's streaming capability.
///
/// Auth: ChatGPT subscription token via Codex OAuth
/// STT: Server-side whisper-1 via Realtime API's input_audio_transcription
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

        // Pre-connect in background for instant first use
        Task { await preConnect() }
    }

    func deactivate() {
        hotkey.stop()
        audioCapture.stop()
        client?.disconnect()
        client = nil
        isRecording = false
        isConnected = false
    }

    // MARK: - Pre-connection

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
        guard !isRecording else {
            print("⚠️ Already recording — forcing stop first")
            await finishDictation()
            return
        }

        // Connect if not pre-connected
        if !isConnected {
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

        // Refresh instructions with current active app (may have changed since pre-connect)
        client?.refreshInstructions(language: config.language)

        isRecording = true
        chunkCount = 0
        transcriptReceived = false
        lastTranscript = ""
        onPartialTranscript?("")

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
        isRecording = false

        audioCapture.stop()
        let chunks = chunkCount
        print("🛑 Recording stopped (\(chunks) chunks)")

        // Need at least a few chunks
        guard chunks > 2 else {
            print("⚠️ Too few chunks — skipping")
            onStateChanged?(.idle)
            // Reconnect for next session
            reconnect()
            return
        }

        // Immediately show processing state
        onStateChanged?(.processing)

        // Make sure we're connected before committing
        guard let client, isConnected else {
            print("⚠️ Not connected — reconnecting")
            reconnect()
            return
        }

        // Commit immediately — audio was already streamed in real-time
        client.commitAndRespond()
        print("📤 Committed buffer, waiting for transcript...")

        // Wait for transcript (max 5s — should be fast since audio was streamed)
        transcriptReceived = false
        for _ in 1...50 {
            if transcriptReceived { return }
            try? await Task.sleep(for: .milliseconds(100))
        }

        // Timed out
        print("⏰ Timed out waiting for transcript (10s)")
        onStateChanged?(.idle)
        reconnect()
    }

    private func handleTranscript(_ text: String) {
        guard isConnected else { return }
        transcriptReceived = true
        lastTranscript = text

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

        let success = TextInjector.inject(cleaned)
        print(success ? "✅ Text injected" : "❌ Text injection failed")
        onStateChanged?(success ? .idle : .error("Text injection failed"))

        // Reconnect for next session
        reconnect()
    }

    private var reconnectAttempts = 0

    private func reconnect() {
        client?.disconnect()
        client = nil
        isConnected = false
        reconnectAttempts += 1

        // Exponential backoff: 1s, 2s, 4s, 8s, max 30s
        let delay = min(Double(reconnectAttempts), 5) * 1.0
        print("🔄 Reconnecting in \(delay)s (attempt \(reconnectAttempts))...")

        Task {
            try? await Task.sleep(for: .seconds(delay))
            await preConnect()
            if isConnected { reconnectAttempts = 0 }
        }
    }

    // MARK: - Callbacks

    private func wireCallbacks(_ client: RealtimeClient) {
        // Whisper transcription events — this is the accurate STT
        client.onFinalTranscript = { [weak self] text in
            Task { @MainActor in self?.handleTranscript(text) }
        }
        client.onPartialTranscript = { [weak self] text in
            Task { @MainActor in self?.onPartialTranscript?(text) }
        }
        client.onError = { [weak self] err in
            Task { @MainActor in
                print("⚠️ Realtime error: \(err)")
                // Only reconnect if we were actually recording (not during pre-connect)
                if self?.isRecording == true {
                    self?.onStateChanged?(.error(err))
                }
                self?.reconnect()
            }
        }
    }
}
