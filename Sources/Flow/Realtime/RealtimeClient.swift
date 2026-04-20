import Foundation

/// WebSocket client for OpenAI's Realtime API.
///
/// Handles the full lifecycle:
/// 1. Connect to `wss://api.openai.com/v1/realtime?model=gpt-realtime-1.5`
/// 2. Configure session (text-only for dictation, text+audio for voice chat)
/// 3. Stream audio via `input_audio_buffer.append`
/// 4. Receive transcripts and/or audio responses
/// 5. Handle turn detection and session management
///
/// Two modes:
/// - **Dictation**: text output only, manual turn control (commit + response.create)
/// - **Voice Chat**: audio+text output, server VAD for natural conversation
final class RealtimeClient {
    // MARK: - Callbacks

    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?
    var onPartialTranscript: ((String) -> Void)?
    var onFinalTranscript: ((String) -> Void)?
    var onAudioResponse: ((Data) -> Void)?
    var onSpeechStarted: (() -> Void)?
    var onSpeechEnded: (() -> Void)?
    var onResponseComplete: (() -> Void)?
    var onError: ((String) -> Void)?

    // MARK: - State

    private var webSocket: URLSessionWebSocketTask?
    private(set) var isConnected = false
    private var partialText = ""
    private var receivingQueue = DispatchQueue(label: "ai.flow.realtime.recv", qos: .userInteractive)

    // MARK: - Connection

    /// Connect to the Realtime API.
    /// - Parameters:
    ///   - accessToken: Bearer token (from ChatGPT OAuth or API key)
    ///   - model: Realtime model name
    ///   - mode: Dictation (text-only) or VoiceChat (audio+text)
    func connect(accessToken: String, model: String = "gpt-realtime-1.5", mode: ConnectionMode) async throws {
        guard let url = URL(string: "wss://api.openai.com/v1/realtime?model=\(model)") else {
            throw RealtimeError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let session = URLSession(configuration: .ephemeral)
        let ws = session.webSocketTask(with: request)
        self.webSocket = ws
        ws.resume()

        // Wait briefly for the handshake
        try await Task.sleep(for: .milliseconds(200))

        isConnected = true
        print("🔌 Connected to Realtime API (\(model))")

        // Configure session based on mode
        try await configureSession(mode: mode)

        // Start receiving
        receiveLoop()

        onConnected?()
    }

    /// Disconnect from the API.
    func disconnect() {
        isConnected = false
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        partialText = ""
        onDisconnected?()
        print("🔌 Disconnected from Realtime API")
    }

    // MARK: - Session Configuration

    enum ConnectionMode {
        case dictation(language: String)
        case voiceChat(voice: String)
    }

    private func configureSession(mode: ConnectionMode) async throws {
        let sessionConfig: String

        switch mode {
        case .dictation(let lang):
            sessionConfig = """
            {
                "type": "session.update",
                "session": {
                    "modalities": ["text"],
                    "instructions": "You are a transcription engine. Output ONLY the exact transcription of the user's speech. No commentary, no formatting, no corrections beyond obvious speech-to-text fixes. Preserve the speaker's intent.",
                    "voice": "alloy",
                    "input_audio_format": "pcm16",
                    "output_audio_format": "pcm16",
                    "input_audio_transcription": {
                        "model": "whisper-1",
                        "language": "\(lang)"
                    },
                    "turn_detection": null,
                    "max_response_output_tokens": 1024
                }
            }
            """

        case .voiceChat(let voice):
            sessionConfig = """
            {
                "type": "session.update",
                "session": {
                    "modalities": ["text", "audio"],
                    "instructions": "You are a helpful, conversational AI assistant. Be concise and natural. You're having a voice conversation — keep responses short and spoken-style, like talking to a friend. Don't use markdown or bullet points.",
                    "voice": "\(voice)",
                    "input_audio_format": "pcm16",
                    "output_audio_format": "pcm16",
                    "input_audio_transcription": {
                        "model": "whisper-1"
                    },
                    "turn_detection": {
                        "type": "server_vad",
                        "threshold": 0.5,
                        "prefix_padding_ms": 300,
                        "silence_duration_ms": 500
                    },
                    "max_response_output_tokens": 4096
                }
            }
            """
        }

        try send(sessionConfig)
    }

    // MARK: - Audio Input

    /// Send a chunk of PCM16 audio data.
    func sendAudio(_ pcm16Data: Data) {
        guard isConnected else { return }
        let base64 = pcm16Data.base64EncodedString()
        let event = """
        {"type":"input_audio_buffer.append","audio":"\(base64)"}
        """
        try? send(event)
    }

    /// Signal end of speech — commit buffer and request response.
    func commitAndRespond() {
        guard isConnected else { return }
        try? send("""
        {"type":"input_audio_buffer.commit"}
        """)
        try? send("""
        {"type":"response.create","response":{"modalities":["text"]}}
        """)
    }

    /// Cancel any in-progress response (for interruptions in voice chat).
    func cancelResponse() {
        guard isConnected else { return }
        try? send("""
        {"type":"response.cancel"}
        """)
    }

    // MARK: - Sending

    private func send(_ message: String) throws {
        guard let ws = webSocket else { throw RealtimeError.notConnected }
        ws.send(.string(message)) { error in
            if let error { print("⚠️ WebSocket send: \(error.localizedDescription)") }
        }
    }

    // MARK: - Receiving

    private func receiveLoop() {
        guard let ws = webSocket, isConnected else { return }

        ws.receive { [weak self] result in
            guard let self, self.isConnected else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let json): self.handleEvent(json)
                case .data(let d):
                    if let s = String(data: d, encoding: .utf8) { self.handleEvent(s) }
                @unknown default: break
                }
                self.receiveLoop()

            case .failure(let err):
                if self.isConnected {
                    print("⚠️ WebSocket error: \(err)")
                    self.onError?(err.localizedDescription)
                    self.isConnected = false
                }
            }
        }
    }

    private func handleEvent(_ json: String) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }

        switch type {
        // Session lifecycle
        case "session.created":
            print("  ✅ Session created")

        case "session.updated":
            print("  ✅ Session configured")

        // Input audio transcription (from Whisper server-side)
        case "conversation.item.input_audio_transcription.delta":
            if let delta = obj["delta"] as? String {
                partialText += delta
                onPartialTranscript?(partialText)
            }

        case "conversation.item.input_audio_transcription.completed":
            if let t = obj["transcript"] as? String {
                partialText = t
                onFinalTranscript?(t)
            }

        // Response text (model output)
        case "response.text.delta":
            if let delta = obj["delta"] as? String {
                partialText += delta
                onPartialTranscript?(partialText)
            }

        case "response.text.done":
            if let t = obj["text"] as? String {
                partialText = t
                onFinalTranscript?(t)
            }

        // Response audio (voice chat mode)
        case "response.audio.delta":
            if let b64 = obj["delta"] as? String,
               let audioData = Data(base64Encoded: b64) {
                onAudioResponse?(audioData)
            }

        case "response.audio.done":
            break // Audio stream complete

        // Response lifecycle
        case "response.done":
            onResponseComplete?()
            partialText = ""

        // Speech detection (voice chat mode)
        case "input_audio_buffer.speech_started":
            onSpeechStarted?()

        case "input_audio_buffer.speech_stopped":
            onSpeechEnded?()

        // Audio buffer
        case "input_audio_buffer.committed":
            break

        // Conversation item
        case "conversation.item.created":
            break

        // Errors
        case "error":
            let msg = (obj["error"] as? [String: Any])?["message"] as? String ?? json
            print("  ❌ Error: \(msg)")
            onError?(msg)

        default:
            break
        }
    }
}

enum RealtimeError: LocalizedError {
    case invalidURL
    case notConnected
    case authFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid Realtime API URL"
        case .notConnected: return "Not connected to Realtime API"
        case .authFailed: return "Authentication failed"
        }
    }
}
