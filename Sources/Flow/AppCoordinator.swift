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
    @Published var isEnhancedMode: Bool = false

    private let auth = ChatGPTAuth.shared
    private var dictationEngine: DictationEngine?
    private let floatingPill = FloatingPillWindowController()
    private let sounds = SoundManager.shared
    private let permissions = PermissionsManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var sessionStartTime: Date?
    private var previousState: FlowState = .idle
    private var onboardingWindow: NSWindow?

    init() {
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
        // Headless/builder mode: skip everything, go straight to idle
        // Detected via FLOW_HEADLESS env var OR running from a CloseLoop job worktree
        let env = ProcessInfo.processInfo.environment
        let isHeadless = env["FLOW_HEADLESS"] == "1"
            || Bundle.main.bundlePath.contains("CloseLoop")
            || Bundle.main.bundlePath.contains("closeloop")
            || Bundle.main.executablePath.contains("CloseLoop")

        if isHeadless {
            print("🤖 Headless mode — skipping onboarding & permissions")
            showOnboarding = false
            authState = .signedIn(email: "headless@flow.dev", plan: "Builder")
            activateDictation()
            return
        }

        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        let permStatus = permissions.checkAll()

        if !hasCompletedOnboarding || !permStatus.allGranted {
            showOnboarding = true
            // Open onboarding window immediately via AppKit (not SwiftUI openWindow)
            DispatchQueue.main.async {
                self.openOnboardingWindow()
            }
            return
        }
        checkAuth()
    }

    /// Open the onboarding window using NSPanel (reliable, unlike SwiftUI openWindow).
    private func openOnboardingWindow() {
        // Don't open duplicate windows
        guard onboardingWindow == nil else { return }

        let view = OnboardingFlowView(coordinator: self)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "ChatFlow Setup"
        window.contentView = NSHostingView(rootView: view)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.onboardingWindow = window
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        showOnboarding = false
        onboardingWindow?.close()
        onboardingWindow = nil
        permissionsStatus = permissions.checkAll()
        checkAuth()
    }

    /// Re-open onboarding (from menu Help button or settings).
    func reopenOnboarding() {
        showOnboarding = true
        openOnboardingWindow()
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
        if dictationEngine != nil {
            deactivateAll()
        }
        let engine = DictationEngine(auth: auth, config: config)
        engine.onStateChanged = { [weak self] newState in
            Task { @MainActor in
                self?.handleStateChange(newState)
                self?.state = newState
                if newState == .recording {
                    self?.floatingPill.reposition()
                    self?.isEnhancedMode = self?.dictationEngine?.isEnhancedMode ?? false
                }
                if newState == .idle || newState.isError {
                    self?.isEnhancedMode = false
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

    func updateHotkey(_ newHotkey: String) {
        config.hotkey = newHotkey
        config.save()
        // Use runtime combo update — no need to tear down and rebuild
        // the entire dictation engine just for a hotkey change (WisprFlow pattern)
        if let engine = dictationEngine {
            engine.updateHotkey(newHotkey)
        }
    }

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
