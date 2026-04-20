import Foundation
import WebKit
import AppKit
import CommonCrypto

/// Authenticates with ChatGPT via a web view.
///
/// Strategy: Open chatgpt.com in a WKWebView, let the user log in normally,
/// then intercept the access token from cookies/localStorage.
///
/// This is the same approach used by ChatGPT's own desktop app.
final class ChatGPTAuth: NSObject, ObservableObject {
    static let shared = ChatGPTAuth()

    @Published var authState: AuthState = .signedOut
    @Published var userEmail: String?

    /// Current access token (if signed in)
    private(set) var accessToken: String?

    private let keychain = KeychainStore.shared
    private var webView: WKWebView?
    private var window: NSWindow?

    override init() {
        super.init()
        // Check for existing token
        if let tokens = keychain.loadTokens() {
            let email = Self.extractEmailFromJWT(tokens.accessToken)
            self.accessToken = tokens.accessToken
            self.userEmail = email
            self.authState = .signedIn(email: email ?? "ChatGPT User", plan: "ChatGPT")
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
        webView = nil
        window?.close()
        window = nil
    }

    // MARK: - Login Window

    private func showLoginWindow() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 480, height: 700), configuration: config)
        webView.navigationDelegate = self
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
        window.makeKeyAndOrderFront(nil)
        self.window = window

        // Load ChatGPT login
        if let url = URL(string: "https://chatgpt.com/auth/login") {
            webView.load(URLRequest(url: url))
        }
    }

    // MARK: - JWT Parsing

    static func extractEmailFromJWT(_ jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Pad base64
        while payload.count % 4 != 0 { payload += "=" }

        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return json["email"] as? String ?? json["name"] as? String
    }

    static func sha256Base64URL(_ input: String) -> String {
        let data = input.data(using: .utf8)!
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = data.withUnsafeBytes { ptr in
            CC_SHA256(ptr.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - WKNavigationDelegate

extension ChatGPTAuth: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url

        // If redirected to chatgpt.com (logged in), try to extract token
        if let host = url?.host, host.contains("chatgpt.com") {
            if url?.path == "/" || url?.path == "/auth/login" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    webView.evaluateJavaScript("localStorage.getItem('accessToken')") { result, _ in
                        if let token = result as? String, !token.isEmpty {
                            self?.handleToken(token)
                        }
                    }
                }
            }
        }

        decisionHandler(.allow)
    }

    private func handleToken(_ token: String) {
        guard !token.isEmpty else { return }

        self.accessToken = token

        let email = Self.extractEmailFromJWT(token)
        let tokens = KeychainStore.AuthTokens(
            accessToken: token,
            refreshToken: "",
            idToken: nil,
            expiresAt: Date().addingTimeInterval(3600),
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
        }
    }
}
