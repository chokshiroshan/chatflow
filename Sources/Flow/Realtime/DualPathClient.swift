import Foundation

/// A dual-path Realtime client that uses the ChatGPT backend (free with sub).
///
/// Connection priority:
/// 1. chatgpt.com/backend-api/realtime — free with ChatGPT Plus/Pro subscription
/// 2. api.openai.com Realtime API — requires OPENAI_API_KEY env var (pay-per-use)
/// 3. Groq Whisper — free fallback for dictation only
@MainActor
final class DualPathRealtimeClient {
    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?
    var onPartialTranscript: ((String) -> Void)?
    var onFinalTranscript: ((String) -> Void)?
    var onAudioResponse: ((Data) -> Void)?
    var onSpeechStarted: (() -> Void)?
    var onSpeechEnded: (() -> Void)?
    var onResponseComplete: (() -> Void)?
    var onError: ((String) -> Void)?
    var onBackendPathUsed: ((Bool) -> Void)?

    private var activeClient: RealtimeClient?
    private let auth: ChatGPTAuth
    private var config: FlowConfig

    init(auth: ChatGPTAuth, config: FlowConfig) {
        self.auth = auth
        self.config = config
    }

    // MARK: - Connection

    func connect(mode: RealtimeClient.ConnectionMode) async throws {
        // Path 1: ChatGPT backend (free with subscription)
        if let token = auth.accessToken {
            do {
                let client = RealtimeClient()
                wireCallbacks(client)

                // Connect via ChatGPT backend WebSocket
                // The access token from chatgpt.com localStorage works here
                try await client.connect(
                    accessToken: token,
                    model: config.realtimeModel,
                    mode: mode,
                    backendMode: true
                )

                activeClient = client
                onBackendPathUsed?(true)
                print("✅ Connected via ChatGPT subscription (free)")
                return
            } catch {
                print("⚠️ Backend path failed: \(error.localizedDescription)")
            }
        }

        // Path 2: Developer API (requires OPENAI_API_KEY env var)
        if let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] {
            let client = RealtimeClient()
            wireCallbacks(client)
            try await client.connect(accessToken: apiKey, model: config.realtimeModel, mode: mode)
            activeClient = client
            onBackendPathUsed?(false)
            print("📡 Connected via developer API (pay-per-use)")
            return
        }

        throw DualPathError.noValidPath
    }

    func disconnect() {
        activeClient?.disconnect()
        activeClient = nil
    }

    // MARK: - Passthrough

    func sendAudio(_ data: Data) { activeClient?.sendAudio(data) }
    func commitAndRespond() { activeClient?.commitAndRespond() }
    func cancelResponse() { activeClient?.cancelResponse() }

    // MARK: - Wiring

    private func wireCallbacks(_ client: RealtimeClient) {
        client.onConnected = { [weak self] in self?.onConnected?() }
        client.onDisconnected = { [weak self] in self?.onDisconnected?() }
        client.onPartialTranscript = { [weak self] t in self?.onPartialTranscript?(t) }
        client.onFinalTranscript = { [weak self] t in self?.onFinalTranscript?(t) }
        client.onAudioResponse = { [weak self] d in self?.onAudioResponse?(d) }
        client.onSpeechStarted = { [weak self] in self?.onSpeechStarted?() }
        client.onSpeechEnded = { [weak self] in self?.onSpeechEnded?() }
        client.onResponseComplete = { [weak self] in self?.onResponseComplete?() }
        client.onError = { [weak self] e in self?.onError?(e) }
    }
}

enum DualPathError: LocalizedError {
    case noValidPath

    var errorDescription: String? {
        switch self {
        case .noValidPath:
            return "No valid connection path. Sign in with ChatGPT or set OPENAI_API_KEY."
        }
    }
}
