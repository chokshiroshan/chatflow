import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// A minimal HTTP server that runs on localhost to catch OAuth callbacks.
///
/// Flow:
/// 1. Start server on a random port
/// 2. Open browser → ChatGPT login
/// 3. Browser redirects to http://localhost:PORT/callback?code=xxx
/// 4. Server captures the auth code
/// 5. Exchanges code for tokens
/// 6. Shuts down
final class OAuthCallbackServer {
    private var serverSocket: Int32 = -1
    private var port: UInt16 = 0
    private var continuation: CheckedContinuation<String, Error>?

    /// The redirect URI to use in the OAuth URL.
    var redirectURI: String {
        "http://localhost:\(port)/callback"
    }

    /// Start the server and return the auth code received.
    func waitForCallback() async throws -> String {
        try startServer()
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            self.acceptConnection()
        }
    }

    /// Shut down the server.
    func stop() {
        if serverSocket != -1 {
            shutdown(serverSocket, SHUT_RDWR)
            close(serverSocket)
            serverSocket = -1
        }
    }

    deinit { stop() }

    // MARK: - Private

    private func startServer() throws {
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket != -1 else {
            throw OAuthError.serverStartFailed
        }

        // Allow port reuse
        var reuse: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))

        // Bind to localhost on random port
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout.size(ofValue: addr))
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = INADDR_ANY // 0.0.0.0 — only accessible locally
        addr.sin_port = 0 // OS picks a port

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            bind(serverSocket, UnsafeRawPointer(ptr).assumingMemoryBound(to: sockaddr.self), socklen_t(MemoryLayout.size(ofValue: addr)))
        }

        guard bindResult == 0 else {
            close(serverSocket)
            throw OAuthError.serverStartFailed
        }

        // Get the assigned port
        var addrLen = socklen_t(MemoryLayout.size(ofValue: addr))
        var assignedAddr = sockaddr_in()
        getsockname(serverSocket, UnsafeMutablePointer(&assignedAddr).withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 }, &addrLen)
        port = ntohs(assignedAddr.sin_port)

        // Start listening
        guard listen(serverSocket, 1) == 0 else {
            close(serverSocket)
            throw OAuthError.serverStartFailed
        }
    }

    private func acceptConnection() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, self.serverSocket != -1 else { return }

            var clientAddr = sockaddr()
            var clientLen = socklen_t(MemoryLayout.size(ofValue: clientAddr))
            let clientSocket = accept(self.serverSocket, &clientAddr, &clientLen)

            guard clientSocket != -1 else {
                self.continuation?.resume(throwing: OAuthError.acceptFailed)
                return
            }
            defer { close(clientSocket) }

            // Read the HTTP request
            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = recv(clientSocket, &buffer, buffer.count, 0)
            guard bytesRead > 0 else {
                self.continuation?.resume(throwing: OAuthError.noData)
                return
            }

            let request = String(bytes: buffer.prefix(bytesRead), encoding: .utf8) ?? ""

            // Parse the authorization code from the URL
            // GET /callback?code=xxx&state=yyy HTTP/1.1
            guard let code = self.extractCode(from: request) else {
                // Send error response
                self.sendResponse(clientSocket, html: """
                <html><body>
                <h2>❌ Authentication Failed</h2>
                <p>No authorization code received. Please try again.</p>
                <script>setTimeout(() => window.close(), 2000)</script>
                </body></html>
                """)
                self.continuation?.resume(throwing: OAuthError.noCode)
                return
            }

            // Send success response
            self.sendResponse(clientSocket, html: """
            <html><body style="font-family:system-ui;text-align:center;padding-top:15%">
            <h2>✅ Authenticated!</h2>
            <p>You can close this tab and go back to Flow.</p>
            <script>setTimeout(() => window.close(), 1500)</script>
            </body></html>
            """)

            self.continuation?.resume(returning: code)
        }
    }

    private func extractCode(from request: String) -> String? {
        // Parse "GET /callback?code=XXX HTTP/1.1"
        guard let range = request.range(of: "GET /callback?") else { return nil }
        let path = String(request[range.upperBound...])
        guard let space = path.firstIndex(of: " ") else { return nil }
        let queryString = String(path[..<space])

        for param in queryString.split(separator: "&") {
            let parts = param.split(separator: "=", maxSplits: 1)
            if parts.count == 2 && parts[0] == "code" {
                return String(parts[1]).removingPercentEncoding
            }
        }
        return nil
    }

    private func sendResponse(_ socket: Int32, html: String) {
        let httpResponse = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Connection: close\r
        Content-Length: \(html.utf8.count)\r
        \r
        \(html)
        """
        let data = Data(httpResponse.utf8)
        data.withUnsafeBytes { ptr in
            send(socket, ptr.baseAddress, data.count, 0)
        }
    }
}

enum OAuthError: LocalizedError {
    case serverStartFailed
    case acceptFailed
    case noData
    case noCode
    case invalidState
    case tokenExchangeFailed(String)
    case noRefreshToken

    var errorDescription: String? {
        switch self {
        case .serverStartFailed: return "Could not start local OAuth server"
        case .acceptFailed: return "Could not accept OAuth callback connection"
        case .noData: return "Empty callback data received"
        case .noCode: return "No authorization code in callback"
        case .invalidState: return "OAuth state mismatch — possible CSRF"
        case .tokenExchangeFailed(let msg): return "Token exchange failed: \(msg)"
        case .noRefreshToken: return "No refresh token available"
        }
    }
}
