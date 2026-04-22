import SwiftUI
import Combine

/// The central coordinator that glues all subsystems together.
@MainActor
final class AppCoordinator: ObservableObject {
    @Published var state: FlowState = .idle
    @Published var authState: AuthState = .signedOut
    @Published var partialTranscript: String = ""
    @Published var config: FlowConfig = .load()
    @Published var showOnboarding: Bool = false
    @Published var permissionsStatus: PermissionsManager.PermissionStatus = PermissionsManager.shared.checkAll()
    @Published var usageDisplay: String = UsageTracker.shared.stats.monthMinutesDisplay

    private let auth = ChatGPTAuth.shared
    private var dictationEngine: DictationEngine?
    private let floatingPill = FloatingPillWindowController()
    private let sounds = SoundManager.shared
    private let permissions = PermissionsManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var sessionStartTime: Date?
    private var previousState: FlowState = .idle

    init() {
        // Single consolidated auth subscription
        auth.$authState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] authState in
                self?.authState = authState
                if case .signedIn = authState {
                    self?.activateDictation()
                }
            }
            .store(in: &cancellables)

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

    func signIn() {
        auth.signIn()
    }

    func signOut() {
        auth.signOut()
        authState = .signedOut
        deactivateAll()
    }

    private func checkAuth() {
        if let tokens = KeychainStore.shared.loadTokens() {
            let email = ChatGPTAuth.extractEmailFromJWT(tokens.accessToken) ?? "ChatGPT User"
            authState = .signedIn(email: email, plan: "ChatGPT")
            activateDictation()
        }
    }

    // MARK: - Dictation

    private func activateDictation() {
        guard case .signedIn = authState else { return }
        // Deactivate any existing engine before creating a new one
        if dictationEngine != nil {
            deactivateAll()
        }
        let engine = DictationEngine(auth: auth, config: config)
        engine.onStateChanged = { [weak self] newState in
            Task { @MainActor in
                self?.handleStateChange(newState)
                self?.state = newState
                // Reposition pill to active screen when recording starts
                if newState == .recording {
                    self?.floatingPill.reposition()
                }
            }
        }
        engine.onPartialTranscript = { [weak self] text in
            Task { @MainActor in self?.partialTranscript = text }
        }
        engine.activate()
        self.dictationEngine = engine
        floatingPill.show(coordinator: self)
    }

    // MARK: - State Changes + Sound Effects

    private func handleStateChange(_ newState: FlowState) {
        switch newState {
        case .recording:
            sessionStartTime = Date()
            if config.soundEffectsEnabled { sounds.play(.startRecording) }
        case .processing, .injecting:
            if let start = sessionStartTime {
                UsageTracker.shared.recordSession(durationSeconds: Date().timeIntervalSince(start))
                usageDisplay = UsageTracker.shared.stats.monthMinutesDisplay
                sessionStartTime = nil
            }
            if config.soundEffectsEnabled { sounds.play(.stopRecording) }
        case .idle:
            // Play success sound when transitioning from injecting → idle
            if previousState == .injecting {
                if config.soundEffectsEnabled { sounds.play(.success) }
            }
        case .error:
            sessionStartTime = nil
            if config.soundEffectsEnabled { sounds.play(.error) }
        default: break
        }
        previousState = newState
    }

    // MARK: - Config Updates

    /// Update hotkey and restart the hotkey manager.
    func updateHotkey(_ newHotkey: String) {
        config.hotkey = newHotkey
        config.save()
        if dictationEngine != nil {
            deactivateAll()
            activateDictation()
        }
    }

    /// Refresh permissions status.
    func refreshPermissions() {
        permissionsStatus = permissions.checkAll()
    }

    // MARK: - Cleanup

    private func deactivateAll() {
        dictationEngine?.deactivate()
        dictationEngine = nil
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
