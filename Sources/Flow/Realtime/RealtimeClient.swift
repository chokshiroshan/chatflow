import Foundation

/// WebSocket client for OpenAI's Realtime API.
///
/// Matches Codex CLI v2 protocol:
/// - Transcription mode: dedicated STT with gpt-4o-mini-transcribe
/// - Voice chat mode: conversational with server VAD
/// - Audio: PCM16 24kHz mono
///
/// Auth: Bearer token from ChatGPT OAuth (subscription) or API key.
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

    // MARK: - Connection

    enum ConnectionMode {
        case dictation(language: String)
        case voiceChat(voice: String)
    }

    func connect(accessToken: String, model: String = "gpt-realtime", mode: ConnectionMode, backendMode: Bool = false) async throws {
        let urlString = "wss://api.openai.com/v1/realtime?model=\(model)"

        guard let url = URL(string: urlString) else {
            throw RealtimeError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        print("🔌 Connecting to Realtime API: \(urlString) (backend: \(backendMode))")

        let session = URLSession(configuration: .ephemeral)
        let ws = session.webSocketTask(with: request)
        self.webSocket = ws
        ws.resume()

        try await Task.sleep(for: .milliseconds(300))

        isConnected = true
        print("🔌 Connected to Realtime API (\(model))")

        // Configure session
        try await configureSession(mode: mode)

        // Start receiving
        receiveLoop()

        onConnected?()
    }

    func disconnect() {
        isConnected = false
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        partialText = ""
        onDisconnected?()
        print("🔌 Disconnected from Realtime API")
    }

    // MARK: - Session Configuration

    private func configureSession(mode: ConnectionMode) async throws {
        let sessionConfig: String

        switch mode {
        case .dictation(let lang):
            // Match Codex CLI v2 transcription session exactly:
            // - type: "transcription" (dedicated STT mode, not conversational)
            // - model: "gpt-4o-mini-transcribe" (better than whisper-1)
            // - audio format: audio/pcm @ 24000Hz
            // - noise_reduction: near_field
            // - no turn detection, no output
            sessionConfig = """
            {
                "type": "session.update",
                "session": {
                    "type": "transcription",
                    "audio": {
                        "input": {
                            "format": {
                                "type": "audio/pcm",
                                "rate": 24000
                            },
                            "noise_reduction": {
                                "type": "near_field"
                            },
                            "transcription": {
                                "model": "gpt-4o-mini-transcribe",
                                "language": "\(lang)"
                            }
                        }
                    }
                }
            }
            """

        case .voiceChat(let voice):
            sessionConfig = """
            {
                "type": "session.update",
                "session": {
                    "modalities": ["text", "audio"],
                    "instructions": "You are a helpful, conversational AI assistant. Be concise and natural.",
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

    func sendAudio(_ pcm16Data: Data) {
        guard isConnected else { return }
        let base64 = pcm16Data.base64EncodedString()
        let event = """
        {"type":"input_audio_buffer.append","audio":"\(base64)"}
        """
        do {
            try send(event)
        } catch {
            print("⚠️ Failed to send audio chunk: \(error)")
        }
    }

    func commitAndRespond() {
        guard isConnected else { return }
        try? send("""
        {"type":"input_audio_buffer.commit"}
        """)
        try? send("""
        {"type":"response.create","response":{"modalities":["text"]}}
        """)
    }

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

        // Input audio transcription (Whisper/gpt-4o-mini-transcribe server-side)
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

        // Response text (model output — fallback)
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
            break

        // Rate limits
        case "rate_limits.updated":
            print("  📊 Rate limits raw: \(json)")

        // Response lifecycle
        case "response.done":
            onResponseComplete?()
            partialText = ""

        // Speech detection
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
            if !type.hasPrefix("session.") && !type.hasPrefix("input_audio_buffer.speech") {
                print("  📨 Event: \(type)")
            }
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
