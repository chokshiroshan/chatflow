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
    @Published var showOnboarding: Bool = false

    private(set) var voiceChatActive = false

    private let auth = ChatGPTAuth()
    private var dictationEngine: DictationEngine?
    private var voiceChatEngine: VoiceChatEngine?
    private let floatingPill = FloatingPillWindowController()
    private let sounds = SoundManager.shared
    private let permissions = PermissionsManager.shared
    private let autoStart = AutoStartManager.shared

    init() {
        checkPermissionsAndAuth()
    }

    // MARK: - Startup

    private func checkPermissionsAndAuth() {
        let permStatus = permissions.checkAll()

        if !permStatus.allGranted {
            showOnboarding = true
            return
        }

        checkAuth()
    }

    func completeOnboarding() {
        showOnboarding = false
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

            if tokens.isExpired {
                Task {
                    do {
                        _ = try await auth.getAccessToken()
                    } catch {
                        authState = .error("Session expired. Sign in again.")
                    }
                }
            }

            activateDictation()
        }
    }

    // MARK: - Mode Switching

    func switchMode(to mode: AppMode) {
        config.preferredMode = mode
        config.save()
        deactivateAll()

        switch mode {
        case .dictation: activateDictation()
        case .voiceChat: break // Manual start
        }
    }

    // MARK: - Dictation

    private func activateDictation() {
        guard authState.isSignedIn else { return }

        let engine = DictationEngine(auth: auth, config: config)
        engine.onStateChanged = { [weak self] newState in
            Task { @MainActor in
                self?.state = newState
                self?.handleStateChange(newState)
            }
        }
        engine.onPartialTranscript = { [weak self] text in
            Task { @MainActor in self?.partialTranscript = text }
        }
        engine.activate()
        self.dictationEngine = engine

        // Show floating pill
        floatingPill.show(coordinator: self)
    }

    // MARK: - Voice Chat

    func startVoiceChat() async {
        guard authState.isSignedIn else { return }

        let engine = VoiceChatEngine(auth: auth, config: config)
        engine.onStateChanged = { [weak self] newState in
            Task { @MainActor in
                self?.state = newState
                self?.handleStateChange(newState)
            }
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

    // MARK: - State Changes + Sound Effects

    private func handleStateChange(_ newState: FlowState) {
        switch newState {
        case .recording:
            sounds.play(.startRecording)
        case .processing, .injecting:
            sounds.play(.stopRecording)
        case .idle:
            if state == .injecting {
                sounds.play(.success)
            }
        case .error:
            sounds.play(.error)
        default:
            break
        }
    }

    // MARK: - Cleanup

    private func deactivateAll() {
        dictationEngine?.deactivate()
        dictationEngine = nil
        voiceChatEngine?.stop()
        voiceChatEngine = nil
        voiceChatActive = false
        floatingPill.hide()
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
