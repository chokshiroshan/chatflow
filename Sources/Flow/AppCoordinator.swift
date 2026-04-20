import SwiftUI
import Combine

/// The central coordinator that glues all subsystems together.
@MainActor
final class AppCoordinator: ObservableObject {
    @Published var state: FlowState = .idle
    @Published var authState: AuthState = .signedOut
    @Published var partialTranscript: String = ""
    @Published var userTranscript: String = ""
    @Published var assistantTranscript: String = ""
    @Published var config: FlowConfig = .load()

    private(set) var voiceChatActive = false

    private let auth = ChatGPTAuth()
    private var dictationEngine: DictationEngine?
    private var voiceChatEngine: VoiceChatEngine?

    init() {
        checkAuth()
    }

    // MARK: - Auth

    func signIn() async {
        authState = .signingIn
        do {
            try await auth.signIn()
            let email = auth.currentUserEmail ?? "Unknown"
            let plan = auth.currentPlan ?? "ChatGPT"
            authState = .signedIn(email: email, plan: plan)

            // Auto-activate dictation on sign-in
            activateDictation()
        } catch {
            authState = .error(error.localizedDescription)
        }
    }

    func signOut() {
        auth.signOut()
        authState = .signedOut
        deactivateAll()
    }

    private func checkAuth() {
        if let tokens = KeychainStore.shared.loadTokens() {
            let email = tokens.email ?? "Unknown"
            let plan = tokens.plan ?? "ChatGPT"
            authState = .signedIn(email: email, plan: plan)

            // Auto-refresh if expired
            if tokens.isExpired {
                Task {
                    do {
                        _ = try await auth.getAccessToken()
                    } catch {
                        authState = .error("Session expired. Please sign in again.")
                    }
                }
            }

            // Auto-activate
            activateDictation()
        }
    }

    // MARK: - Mode Switching

    func switchMode(to mode: AppMode) {
        config.preferredMode = mode
        config.save()

        deactivateAll()

        switch mode {
        case .dictation:
            activateDictation()
        case .voiceChat:
            // Voice chat requires manual start via button
            break
        }
    }

    // MARK: - Dictation

    private func activateDictation() {
        guard authState.isSignedIn else { return }

        let engine = DictationEngine(auth: auth, config: config)
        engine.onStateChanged = { [weak self] newState in
            Task { @MainActor in self?.state = newState }
        }
        engine.onPartialTranscript = { [weak self] text in
            Task { @MainActor in self?.partialTranscript = text }
        }
        engine.activate()
        self.dictationEngine = engine
    }

    // MARK: - Voice Chat

    func startVoiceChat() async {
        guard authState.isSignedIn else { return }

        let engine = VoiceChatEngine(auth: auth, config: config)
        engine.onStateChanged = { [weak self] newState in
            Task { @MainActor in self?.state = newState }
        }
        engine.onUserTranscript = { [weak self] text in
            Task { @MainActor in self?.userTranscript = text }
        }
        engine.onAssistantTranscript = { [weak self] text in
            Task { @MainActor in self?.assistantTranscript = text }
        }
        engine.onError = { [weak self] err in
            Task { @MainActor in self?.state = .error(err) }
        }
        self.voiceChatEngine = engine
        voiceChatActive = true

        await engine.start()
    }

    func stopVoiceChat() {
        voiceChatEngine?.stop()
        voiceChatEngine = nil
        voiceChatActive = false
        userTranscript = ""
        assistantTranscript = ""
        state = .idle
    }

    func interruptVoiceChat() {
        voiceChatEngine?.interrupt()
    }

    // MARK: - Cleanup

    private func deactivateAll() {
        dictationEngine?.deactivate()
        dictationEngine = nil
        voiceChatEngine?.stop()
        voiceChatEngine = nil
        voiceChatActive = false
        state = .idle
    }
}

// MARK: - AuthState Extension

extension AuthState {
    var isSignedIn: Bool {
        if case .signedIn = self { return true }
        return false
    }
}
