import Foundation
import WebKit
import AppKit

/// Authenticates with ChatGPT via a web view.
///
/// Strategy: Open chatgpt.com in a WKWebView, let the user log in normally,
/// then intercept the access token from cookies/localStorage.
///
/// This is the same approach used by ChatGPT's own desktop app.
final class ChatGPTAuth: ObservableObject {
    static let shared = ChatGPTAuth()

    @Published var authState: AuthState = .signedOut
    @Published var userEmail: String?

    private let keychain = KeychainStore.shared
    private var webView: WKWebView?
    private var window: NSWindow?

    private init() {
        // Check for existing token
        if let tokens = keychain.loadTokens() {
            if let email = extractEmailFromJWT(tokens.accessToken) {
                userEmail = email
                authState = .signedIn(email: email, plan: "ChatGPT")
            }
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

        // Inject script to capture access tokens
        let script = WKUserScript(
            source: tokenCaptureScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(script)

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

    // MARK: - Token Capture

    private let tokenCaptureScript = """
    // Monitor for access tokens in localStorage and cookies
    (function() {
        function checkTokens() {
            // ChatGPT stores tokens in localStorage
            var token = localStorage.getItem('accessToken');
            if (token) {
                window.webkit.messageHandlers.tokenCapture.postMessage({
                    type: 'accessToken',
                    token: token
                });
                return;
            }

            // Also check for session token in cookies
            var cookies = document.cookie;
            if (cookies.includes('__Secure-next-auth.session-token')) {
                window.webkit.messageHandlers.tokenCapture.postMessage({
                    type: 'sessionCookie',
                    cookies: cookies
                });
            }
        }

        // Check periodically
        setInterval(checkTokens, 1000);
        checkTokens();
    })();
    """

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
        data.withUnsafeBytes { ptr in
            CC_SHA256(ptr.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - WKNavigationDelegate & Script Message Handler

extension ChatGPTAuth: WKNavigationDelegate, WKScriptMessageHandler {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url

        // If redirected to chatgpt.com (logged in), try to extract token
        if let host = url?.host, host.contains("chatgpt.com") {
            if url?.path == "/" || url?.path == "/auth/login" {
                // Inject token capture after page loads
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    webView.evaluateJavaScript("localStorage.getItem('accessToken')") { [weak self] result, _ in
                        if let token = result as? String, !token.isEmpty {
                            self?.handleToken(token)
                        }
                    }
                }
            }
        }

        decisionHandler(.allow)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        if type == "accessToken", let token = body["token"] as? String {
            handleToken(token)
        }
    }

    private func handleToken(_ token: String) {
        guard !token.isEmpty else { return }

        // Store in keychain
        let tokens = KeychainStore.AuthTokens(
            accessToken: token,
            refreshToken: nil,
            expiresIn: 3600,
            scope: nil
        )
        keychain.saveTokens(tokens)

        // Extract user info
        let email = Self.extractEmailFromJWT(token) ?? "ChatGPT User"
        DispatchQueue.main.async {
            self.userEmail = email
            self.authState = .signedIn(email: email, plan: "ChatGPT")
            self.window?.close()
            self.window = nil
        }
    }
}

// CommonCrypto import
import CommonCrypto
