import Foundation
import WebKit
import AppKit
import CommonCrypto

/// Authenticates with ChatGPT via WKWebView with browser user-agent.
///
/// Strategy: Open chatgpt.com in a WKWebView that impersonates a real browser
/// (to prevent the native ChatGPT app redirect), let the user log in normally,
/// then intercept the access token from localStorage.
///
/// The access token works with chatgpt.com/backend-api endpoints —
/// free with a ChatGPT Plus/Pro subscription.
final class ChatGPTAuth: NSObject, ObservableObject {
    static let shared = ChatGPTAuth()

    @Published var authState: AuthState = .signedOut
    @Published var userEmail: String?

    /// Current access token (if signed in)
    private(set) var accessToken: String?

    private let keychain = KeychainStore.shared
    private var webView: WKWebView?
    private var window: NSWindow?
    private var tokenCheckTimer: Timer?

    override init() {
        super.init()
        // Restore existing session
        if let tokens = keychain.loadTokens(), !tokens.isExpired {
            let email = Self.extractEmailFromJWT(tokens.accessToken)
            self.accessToken = tokens.accessToken
            self.userEmail = email
            self.authState = .signedIn(email: email ?? "ChatGPT User", plan: tokens.plan ?? "ChatGPT")
        }
    }

    // MARK: - Sign In

    func signIn() {
        DispatchQueue.main.async {
            self.authState = .signingIn
            self.showLoginWindow()
        }
    }

    func signOut() {
        keychain.deleteTokens()
        accessToken = nil
        userEmail = nil
        authState = .signedOut
        tokenCheckTimer?.invalidate()
        tokenCheckTimer = nil
        webView?.stopLoading()
        window?.close()
        window = nil
        webView = nil
    }

    // MARK: - Token Refresh

    @discardableResult
    func refreshAccessToken() async -> Bool {
        // For WKWebView-based auth, we don't have a refresh token mechanism.
        // The user will need to re-login when the token expires (~1 hour).
        // ChatGPT tokens typically last 1 hour.
        guard let tokens = keychain.loadTokens() else { return false }
        if !tokens.isExpired {
            accessToken = tokens.accessToken
            return true
        }
        return false
    }

    func ensureValidToken() async -> String? {
        if let tokens = keychain.loadTokens(), !tokens.isExpired {
            accessToken = tokens.accessToken
            return accessToken
        }
        return nil
    }

    // MARK: - Login Window

    private func showLoginWindow() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 480, height: 700), configuration: config)
        webView.navigationDelegate = self
        // Spoof Chrome user-agent to prevent native ChatGPT app redirect
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        self.webView = webView

        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 480, height: 700),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in to ChatGPT"
        window.contentView = webView
        window.center()
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
        window.delegate = self
        self.window = window

        // Load ChatGPT login
        if let url = URL(string: "https://chatgpt.com/auth/login") {
            webView.load(URLRequest(url: url))
        }

        // Start polling for the access token
        startTokenPolling()
    }

    // MARK: - Token Polling

    private func startTokenPolling() {
        tokenCheckTimer?.invalidate()
        tokenCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkForToken()
        }
    }

    private func checkForToken() {
        guard let webView = webView else { return }

        webView.evaluateJavaScript("localStorage.getItem('accessToken')") { [weak self] result, _ in
            guard let self, let token = result as? String, !token.isEmpty else { return }
            self.handleToken(token)
        }
    }

    private func handleToken(_ token: String) {
        guard !token.isEmpty, accessToken != token else { return }

        tokenCheckTimer?.invalidate()
        tokenCheckTimer = nil
        self.accessToken = token

        let email = Self.extractEmailFromJWT(token)
        let tokens = KeychainStore.AuthTokens(
            accessToken: token,
            refreshToken: "",
            idToken: nil,
            expiresAt: Date().addingTimeInterval(3600), // ~1 hour
            email: email,
            plan: "ChatGPT"
        )
        try? keychain.saveTokens(tokens)

        let displayEmail = email ?? "ChatGPT User"
        DispatchQueue.main.async {
            self.userEmail = displayEmail
            self.authState = .signedIn(email: displayEmail, plan: "ChatGPT")
            self.window?.close()
            self.window = nil
            self.webView = nil
        }
        print("✅ Authenticated as \(displayEmail)")
    }

    // MARK: - JWT Parsing

    static func extractEmailFromJWT(_ jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        while payload.count % 4 != 0 { payload += "=" }

        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return json["email"] as? String ?? json["name"] as? String
    }
}

// MARK: - WKNavigationDelegate

extension ChatGPTAuth: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("⚠️ WebView navigation error: \(error.localizedDescription)")
    }
}

// MARK: - NSWindowDelegate

extension ChatGPTAuth: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // If still signing in when window closes, reset state
        if case .signingIn = authState {
            tokenCheckTimer?.invalidate()
            tokenCheckTimer = nil
            authState = .signedOut
            webView = nil
            window = nil
        }
    }
}
