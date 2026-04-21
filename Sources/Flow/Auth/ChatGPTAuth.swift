import Foundation
import AppKit
import CommonCrypto

/// Authenticates with ChatGPT via the Codex OAuth PKCE flow.
///
/// Uses the same auth flow as Codex CLI:
/// 1. Generate PKCE code_verifier + code_challenge (S256)
/// 2. Start local HTTP server on port 1455
/// 3. Open system browser to auth.openai.com/oauth/authorize
/// 4. User logs in → browser redirects to localhost with auth code
/// 5. Exchange code + verifier for access/refresh tokens
/// 6. Store tokens in Keychain
///
/// Client ID: app_EMoamEEZ73f0CkXaXp7hrann (same as Codex CLI)
final class ChatGPTAuth: NSObject, ObservableObject {
    static let shared = ChatGPTAuth()

    // Codex CLI public client ID
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    // Codex CLI overrides OIDC discovery endpoints with these specific paths
    // (discovered from Codex CLI source code: auth.tsx)
    private static let authorizeURL = "https://auth.openai.com/oauth/authorize"
    private static let tokenURL = "https://auth.openai.com/oauth/token"
    private static let callbackPath = "/auth/callback"
    private static let callbackPort: UInt16 = 1455

    @Published var authState: AuthState = .signedOut
    @Published var userEmail: String?

    /// Current access token (if signed in)
    private(set) var accessToken: String?
    private(set) var refreshToken: String?

    private let keychain = KeychainStore.shared
    private var callbackServer: OAuthCallbackServer?
    private var pendingVerifier: String?
    private var pendingState: String?

    override init() {
        super.init()
        // Restore existing session
        if let tokens = keychain.loadTokens(), !tokens.isExpired {
            let email = Self.extractEmailFromJWT(tokens.accessToken)
            self.accessToken = tokens.accessToken
            self.refreshToken = tokens.refreshToken
            self.userEmail = email
            self.authState = .signedIn(email: email ?? "ChatGPT User", plan: tokens.plan ?? "ChatGPT")
        }
    }

    // MARK: - Sign In (PKCE via system browser)

    func signIn() {
        guard authState != .signingIn else { return }
        DispatchQueue.main.async {
            self.authState = .signingIn
        }

        Task {
            do {
                // 1. Generate PKCE pair
                let verifier = Self.generateCodeVerifier()
                let challenge = Self.generateCodeChallenge(from: verifier)
                let state = Self.generateState()
                self.pendingVerifier = verifier
                self.pendingState = state

                // 2. Start callback server
                let server = OAuthCallbackServer()
                server.path = Self.callbackPath
                server.fixedPort = Self.callbackPort
                self.callbackServer = server

                // Use 'localhost' (not '127.0.0.1') to match Codex CLI's registered redirect URI
                let redirectURI = "http://localhost:\(Self.callbackPort)\(Self.callbackPath)"

                // 3. Build authorize URL
                var components = URLComponents(string: Self.authorizeURL)!
                components.queryItems = [
                    URLQueryItem(name: "client_id", value: Self.clientID),
                    URLQueryItem(name: "redirect_uri", value: redirectURI),
                    URLQueryItem(name: "response_type", value: "code"),
                    URLQueryItem(name: "code_challenge", value: challenge),
                    URLQueryItem(name: "code_challenge_method", value: "S256"),
                    URLQueryItem(name: "state", value: state),
                    URLQueryItem(name: "scope", value: "openid profile email offline_access"),
                    URLQueryItem(name: "id_token_add_organizations", value: "true"),
                ]

                guard let authURL = components.url else {
                    throw OAuthError.serverStartFailed
                }

                // 4. Open system browser (not WKWebView!)
                NSWorkspace.shared.open(authURL)
                print("🌐 Opened browser for ChatGPT login...")

                // 5. Wait for callback
                let callbackResult = try await server.waitForCallback()
                server.stop()
                self.callbackServer = nil

                // 6. Validate state
                guard callbackResult.state == state else {
                    throw OAuthError.invalidState
                }

                // 7. Exchange code for tokens
                let tokens = try await exchangeCode(
                    code: callbackResult.code,
                    verifier: verifier,
                    redirectURI: redirectURI
                )

                // 8. Store and update state
                self.accessToken = tokens.accessToken
                self.refreshToken = tokens.refreshToken

                let email = Self.extractEmailFromJWT(tokens.accessToken)
                let keychainTokens = KeychainStore.AuthTokens(
                    accessToken: tokens.accessToken,
                    refreshToken: tokens.refreshToken,
                    idToken: nil,
                    expiresAt: tokens.expiresAt,
                    email: email,
                    plan: "ChatGPT"
                )
                try keychain.saveTokens(keychainTokens)

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
        refreshToken = nil
        userEmail = nil
        authState = .signedOut
        callbackServer?.stop()
        callbackServer = nil
    }

    // MARK: - Token Refresh

    /// Refresh the access token using the refresh token.
    /// Returns true if refresh succeeded.
    @discardableResult
    func refreshAccessToken() async -> Bool {
        guard let rt = refreshToken, !rt.isEmpty else { return false }

        do {
            let response = try await tokenRequest(grantType: "refresh_token", code: nil, verifier: nil, redirectURI: nil, refreshToken: rt)

            self.accessToken = response.accessToken
            if !response.refreshToken.isEmpty {
                self.refreshToken = response.refreshToken
            }

            let email = Self.extractEmailFromJWT(response.accessToken)
            let tokens = KeychainStore.AuthTokens(
                accessToken: response.accessToken,
                refreshToken: self.refreshToken ?? "",
                idToken: nil,
                expiresAt: response.expiresAt,
                email: email,
                plan: "ChatGPT"
            )
            try keychain.saveTokens(tokens)
            print("🔄 Token refreshed")
            return true
        } catch {
            print("⚠️ Token refresh failed: \(error)")
            return false
        }
    }

    /// Ensure we have a valid access token, refreshing if needed.
    func ensureValidToken() async -> String? {
        // Check if current token is still good
        if let tokens = keychain.loadTokens(), !tokens.isExpired {
            accessToken = tokens.accessToken
            return accessToken
        }

        // Try refresh
        if await refreshAccessToken() {
            return accessToken
        }

        return nil
    }

    // MARK: - Token Exchange

    private func exchangeCode(code: String, verifier: String, redirectURI: String) async throws -> TokenResponse {
        try await tokenRequest(
            grantType: "authorization_code",
            code: code,
            verifier: verifier,
            redirectURI: redirectURI,
            refreshToken: nil
        )
    }

    private func tokenRequest(
        grantType: String,
        code: String?,
        verifier: String?,
        redirectURI: String?,
        refreshToken: String?
    ) async throws -> TokenResponse {
        let url = URL(string: Self.tokenURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Codex uses JSON for refresh, form-urlencoded for code exchange
        if grantType == "refresh_token" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var body: [String: String] = [
                "client_id": Self.clientID,
                "grant_type": grantType,
            ]
            if let refreshToken { body["refresh_token"] = refreshToken }
            body["scope"] = "openid profile email"
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        } else {
            // authorization_code exchange — form-urlencoded
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var body: [String: String] = [
                "grant_type": grantType,
                "client_id": Self.clientID,
            ]
            if let code { body["code"] = code }
            if let verifier { body["code_verifier"] = verifier }
            if let redirectURI { body["redirect_uri"] = redirectURI }
            request.httpBody = body
                .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
                .joined(separator: "&")
                .data(using: .utf8)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OAuthError.tokenExchangeFailed("Invalid response")
        }

        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw OAuthError.tokenExchangeFailed("HTTP \(http.statusCode): \(body)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw OAuthError.tokenExchangeFailed("No access_token in response")
        }

        let refreshToken = json["refresh_token"] as? String ?? ""
        let expiresIn = json["expires_in"] as? Double ?? 3600

        return TokenResponse(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
    }

    // MARK: - PKCE Helpers

    /// Generate a cryptographically random code verifier (128 hex chars, matching Codex CLI)
    private static func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return buffer.map { String(format: "%02x", $0) }.joined()
    }

    /// Generate S256 code challenge from verifier
    private static func generateCodeChallenge(from verifier: String) -> String {
        let data = verifier.data(using: .utf8)!
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

    /// Random state parameter for CSRF protection
    private static func generateState() -> String {
        var buffer = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).map { String(format: "%02x", $0) }.joined()
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

// MARK: - Types

struct TokenResponse {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}
