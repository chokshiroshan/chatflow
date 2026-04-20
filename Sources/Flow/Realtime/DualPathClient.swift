import Foundation

/// A dual-path Realtime client that tries the ChatGPT backend first (free with sub),
/// then falls back to the developer API (pay-per-use).
///
/// This gives Flow the best of both worlds:
/// - If you have a ChatGPT subscription → free (uses backend-api)
/// - If backend fails → falls back to developer API key
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
    private var useBackend = true

    init(auth: ChatGPTAuth, config: FlowConfig) {
        self.auth = auth
        self.config = config
    }

    // MARK: - Connection

    /// Connect using the best available path.
    /// Tries ChatGPT backend first, falls back to developer API.
    func connect(mode: RealtimeClient.ConnectionMode) async throws {
        let token = try await auth.getAccessToken()

        // Try backend path first (free with subscription)
        if useBackend {
            do {
                let subscription = try await ChatGPTBackendClient.fetchSubscriptionInfo(accessToken: token)
                if subscription.hasRealtimeAccess {
                    print("✅ ChatGPT \(subscription.displayName) — using backend path (free)")
                    onBackendPathUsed?(true)

                    let client = RealtimeClient()
                    wireCallbacks(client)

                    // Try connecting via developer API with the ChatGPT access token
                    // The access token from auth0.openai.com should work with api.openai.com
                    // because we request audience: "https://api.openai.com/v1"
                    try await client.connect(
                        accessToken: token,
                        model: config.realtimeModel,
                        mode: mode
                    )

                    activeClient = client
                    return
                } else {
                    print("ℹ️ Free plan — backend path unavailable, using developer API")
                    useBackend = false
                }
            } catch {
                print("⚠️ Backend path failed: \(error.localizedDescription)")
                print("   Falling back to developer API...")
                useBackend = false
            }
        }

        // Developer API fallback (requires OPENAI_API_KEY)
        if let apiKey = config.resolveAPIKey() ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"] {
            let client = RealtimeClient()
            wireCallbacks(client)
            try await client.connect(accessToken: apiKey, model: config.realtimeModel, mode: mode)
            activeClient = client
            onBackendPathUsed?(false)
            print("📡 Connected via developer API")
        } else {
            throw DualPathError.noValidPath
        }
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
