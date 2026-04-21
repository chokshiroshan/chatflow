import Foundation
import AppKit

/// Authenticates with ChatGPT via the system browser + a local token capture page.
///
/// Strategy:
/// 1. Start a local HTTP server on a random port
/// 2. Open system browser to a local HTML page with a "Get Token" button
/// 3. The HTML page tries to read chatgpt.com's localStorage via an iframe/proxy
/// 4. If that fails (CORS), it shows instructions to manually copy the token
/// 5. User pastes token into the page → sent to our local server
///
/// This avoids WKWebView entirely (which has sandbox issues in SPM projects).
final class ChatGPTAuth: @unchecked Sendable, ObservableObject {
    static let shared = ChatGPTAuth()

    @Published var authState: AuthState = .signedOut
    @Published var userEmail: String?

    /// Current access token (if signed in)
    private(set) var accessToken: String?

    private let keychain = KeychainStore.shared
    private var callbackServer: TokenCaptureServer?

    @unchecked Sendable init() {
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
        guard authState != .signingIn else { return }
        DispatchQueue.main.async {
            self.authState = .signingIn
        }

        Task { @MainActor in
            do {
                let server = TokenCaptureServer()
                self.callbackServer = server

                // Start server and get the HTML page URL
                let pageURL = try server.start()

                print("🌐 Opening token capture page: \(pageURL)")
                // Open the local HTML page in system browser
                NSWorkspace.shared.open(URL(string: pageURL)!)

                // Wait for the user to submit their token
                let token = try await server.waitForToken()
                server.stop()
                self.callbackServer = nil

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
                try keychain.saveTokens(tokens)

                let displayEmail = email ?? "ChatGPT User"
                DispatchQueue.main.async {
                    self.userEmail = displayEmail
                    self.authState = .signedIn(email: displayEmail, plan: "ChatGPT")
                }
                print("✅ Authenticated as \(displayEmail)")

            } catch {
                print("❌ Auth failed: \(error)")
                self.callbackServer?.stop()
                self.callbackServer = nil
                DispatchQueue.main.async {
                    self.authState = .signedOut
                }
            }
        }
    }

    func signOut() {
        keychain.deleteTokens()
        accessToken = nil
        userEmail = nil
        authState = .signedOut
        callbackServer?.stop()
        callbackServer = nil
    }

    // MARK: - Token Refresh

    @discardableResult
    func refreshAccessToken() async -> Bool {
        guard let tokens = keychain.loadTokens(), !tokens.isExpired else { return false }
        accessToken = tokens.accessToken
        return true
    }

    func ensureValidToken() async -> String? {
        if let tokens = keychain.loadTokens(), !tokens.isExpired {
            accessToken = tokens.accessToken
            return accessToken
        }
        return nil
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

// MARK: - Token Capture Server

/// A local HTTP server that serves an HTML page for token capture
/// and waits for the user to paste their access token.
final class TokenCaptureServer {
    private var serverSocket: Int32 = -1
    private var port: UInt16 = 0
    private var continuation: CheckedContinuation<String, Error>?

    /// Start the server and return the URL of the capture page.
    func start() throws -> String {
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket != -1 else { throw AuthError.serverFailed }

        var reuse: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout.size(ofValue: addr))
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = INADDR_ANY
        addr.sin_port = 0

        let bindResult = withUnsafePointer(to: addr) { ptr in
            bind(serverSocket, UnsafeRawPointer(ptr).assumingMemoryBound(to: sockaddr.self), socklen_t(MemoryLayout<sockaddr_in>.size))
        }
        guard bindResult == 0 else { close(serverSocket); throw AuthError.serverFailed }

        var assignedAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &assignedAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
                getsockname(serverSocket, rebound, &addrLen)
            }
        }
        port = UInt16(bigEndian: assignedAddr.sin_port)

        guard listen(serverSocket, 5) == 0 else { close(serverSocket); throw AuthError.serverFailed }

        // Accept connections in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.acceptLoop()
        }

        return "http://localhost:\(port)/"
    }

    func stop() {
        if serverSocket != -1 {
            shutdown(serverSocket, SHUT_RDWR)
            close(serverSocket)
            serverSocket = -1
        }
    }

    func waitForToken() async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
        }
    }

    deinit { stop() }

    // MARK: - Accept Loop

    private func acceptLoop() {
        while serverSocket != -1 {
            var clientAddr = sockaddr()
            var clientLen = socklen_t(MemoryLayout.size(ofValue: clientAddr))
            let clientSocket = accept(serverSocket, &clientAddr, &clientLen)
            guard clientSocket != -1 else { return }
            defer { close(clientSocket) }

            var buffer = [UInt8](repeating: 0, count: 16384)
            let bytesRead = recv(clientSocket, &buffer, buffer.count, 0)
            guard bytesRead > 0 else { continue }

            let request = String(bytes: buffer.prefix(bytesRead), encoding: .utf8) ?? ""

            if request.hasPrefix("GET / ") || request.hasPrefix("GET /capture") {
                // Serve the HTML capture page
                sendResponse(clientSocket, html: capturePageHTML())
            } else if request.hasPrefix("POST /token") {
                // User submitted their token
                let body = extractBody(from: request)
                if let token = parseToken(from: body), !token.isEmpty {
                    sendResponse(clientSocket, html: successHTML())
                    continuation?.resume(returning: token)
                    return // Done
                } else {
                    sendResponse(clientSocket, html: errorHTML())
                }
            } else if request.hasPrefix("GET /success") {
                sendResponse(clientSocket, html: successHTML())
            } else {
                sendResponse(clientSocket, html: capturePageHTML())
            }
        }
    }

    // MARK: - HTML Pages

    private func capturePageHTML() -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>Flow — Sign in to ChatGPT</title>
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif; background: #1a1a2e; color: #e0e0e0; min-height: 100vh; display: flex; align-items: center; justify-content: center; }
          .container { max-width: 520px; width: 100%; padding: 40px; }
          h1 { font-size: 24px; font-weight: 600; margin-bottom: 8px; color: #fff; }
          .subtitle { color: #888; font-size: 14px; margin-bottom: 24px; }
          .step { background: #16213e; border-radius: 12px; padding: 16px 20px; margin-bottom: 12px; }
          .step-num { display: inline-block; background: #0f3460; color: #e94560; font-weight: 700; width: 24px; height: 24px; border-radius: 50%; text-align: center; line-height: 24px; font-size: 13px; margin-right: 10px; }
          .step p { font-size: 14px; line-height: 1.5; display: inline; }
          .step code { background: #0f3460; padding: 2px 8px; border-radius: 4px; font-size: 12px; color: #e94560; user-select: all; cursor: pointer; }
          textarea { width: 100%; height: 100px; background: #0f3460; border: 1px solid #1a3a6e; border-radius: 8px; color: #e0e0e0; padding: 12px; font-family: monospace; font-size: 11px; resize: vertical; margin-top: 16px; }
          textarea:focus { outline: none; border-color: #e94560; }
          textarea::placeholder { color: #555; }
          .btn { display: block; width: 100%; padding: 14px; background: #e94560; color: #fff; border: none; border-radius: 8px; font-size: 16px; font-weight: 600; cursor: pointer; margin-top: 16px; transition: background 0.2s; }
          .btn:hover { background: #c81e45; }
          .btn:disabled { background: #555; cursor: not-allowed; }
          .or { text-align: center; color: #555; margin: 16px 0; font-size: 13px; }
          .open-btn { display: inline-block; padding: 8px 16px; background: #0f3460; color: #e94560; border: 1px solid #1a3a6e; border-radius: 6px; font-size: 13px; text-decoration: none; margin-top: 8px; }
          .open-btn:hover { background: #1a3a6e; }
          .try-auto { padding: 10px 20px; background: #16213e; color: #e0e0e0; border: 1px solid #1a3a6e; border-radius: 8px; font-size: 14px; cursor: pointer; width: 100%; margin-top: 8px; }
          .try-auto:hover { background: #1a3a6e; }
        </style>
        </head>
        <body>
        <div class="container">
          <h1>🛰️ Flow — Connect ChatGPT</h1>
          <p class="subtitle">Get your access token to enable dictation & voice chat (free with subscription)</p>

          <div class="step">
            <span class="step-num">1</span>
            <p>Open <a href="https://chatgpt.com" target="_blank" style="color:#e94560">chatgpt.com</a> and make sure you're logged in</p>
          </div>

          <div class="step">
            <span class="step-num">2</span>
            <p>Open DevTools (press <code>F12</code> or <code>⌘⌥I</code>) → <strong>Console</strong> tab</p>
          </div>

          <div class="step">
            <span class="step-num">3</span>
            <p>Paste this and press Enter — your token will auto-fill below:</p>
            <br><br>
            <code id="snippet">fetch('/api/auth/session').then(r=>r.json()).then(d=>console.log(d.accessToken))</code>
            <br><span style="color:#888;font-size:12px">Copy the long string that prints out (starts with eyJ...)</span>
          </div>

          <div class="step">
            <span class="step-num">4</span>
            <p>Copy the token from the console and paste it below:</p>
          </div>

          <textarea id="token" placeholder="Paste your access token here (starts with eyJ...)"></textarea>
          <button class="btn" id="submitBtn" onclick="submitToken()">Connect</button>
        </div>
        <script>
        function submitToken() {
          const token = document.getElementById('token').value.trim();
          if (!token || token.length < 20) {
            alert('Please paste a valid access token');
            return;
          }
          document.getElementById('submitBtn').disabled = true;
          document.getElementById('submitBtn').textContent = 'Connecting...';
          fetch('/token', {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: 'token=' + encodeURIComponent(token)
          }).then(r => {
            if (r.ok) {
              document.querySelector('.container').innerHTML = '<h1>✅ Connected!</h1><p class=\"subtitle\">You can close this tab and go back to Flow.</p><script>setTimeout(() => window.close(), 2000)<\\/script>';
            }
          });
        }
        </script>
        </body>
        </html>
        """
    }

    private func successHTML() -> String {
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8"><title>Flow — Connected</title>
        <style>body{font-family:system-ui;text-align:center;padding-top:20%;background:#1a1a2e;color:#e0e0e0}
        h1{font-size:28px;margin-bottom:8px}</style></head>
        <body><h1>✅ Connected!</h1><p>You can close this tab and go back to Flow.</p>
        <script>setTimeout(()=>window.close(),2000)</script></body></html>
        """
    }

    private func errorHTML() -> String {
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8"><title>Flow — Error</title>
        <style>body{font-family:system-ui;text-align:center;padding-top:20%;background:#1a1a2e;color:#e0e0e0}</style></head>
        <body><h1>❌ Invalid token</h1><p>Please go back and try again.</p></body></html>
        """
    }

    // MARK: - Helpers

    private func sendResponse(_ socket: Int32, html: String) {
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\nContent-Length: \(html.utf8.count)\r\n\r\n\(html)"
        let data = Data(response.utf8)
        _ = data.withUnsafeBytes { ptr in
            send(socket, ptr.baseAddress, data.count, 0)
        }
    }

    private func extractBody(from request: String) -> String {
        guard let range = request.range(of: "\r\n\r\n") else { return "" }
        return String(request[range.upperBound...])
    }

    private func parseToken(from body: String) -> String? {
        // Parse "token=xxx"
        let parts = body.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 && parts[0] == "token" else { return nil }
        return String(parts[1]).removingPercentEncoding ?? String(parts[1])
    }
}

enum AuthError: LocalizedError {
    case serverFailed

    var errorDescription: String? {
        switch self {
        case .serverFailed: return "Could not start local auth server"
        }
    }
}
