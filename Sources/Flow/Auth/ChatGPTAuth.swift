import Foundation
import CommonCrypto
import AppKit

/// Full ChatGPT OAuth authentication via PKCE flow.
///
/// This reverse-engineers the same auth flow that Codex uses:
/// 1. Start local HTTP server
/// 2. Generate PKCE code_verifier + challenge
/// 3. Open browser to ChatGPT login
/// 4. Catch callback with authorization code
/// 5. Exchange code for access/refresh tokens
/// 6. Store in macOS Keychain
///
/// The access token works with OpenAI's Realtime API.
final class ChatGPTAuth {
    // MARK: - OAuth Config (from Codex RE)

    private static let authBase = "https://auth0.openai.com"
    private static let clientID = "DRivsnm2Mu42T3KOpqdtwB3NYviHYzwD"
    private static let scopes = "openid email profile offline_access"
    private static let audience = "https://api.openai.com/v1"

    private var codeVerifier: String?
    private var state: String?
    private let callbackServer = OAuthCallbackServer()
    private let keychain = KeychainStore.shared

    // MARK: - Public API

    /// Check if we have valid cached tokens.
    var isAuthenticated: Bool {
        if let tokens = keychain.loadTokens(), !tokens.isExpired {
            return true
        }
        // Try refresh
        return false
    }

    /// Get the current email from stored tokens.
    var currentUserEmail: String? {
        keychain.loadTokens()?.email
    }

    /// Get current plan from stored tokens.
    var currentPlan: String? {
        keychain.loadTokens()?.plan
    }

    /// Get a valid access token, refreshing if necessary.
    func getAccessToken() async throws -> String {
        guard let tokens = keychain.loadTokens() else {
            throw OAuthError.noRefreshToken
        }

        if !tokens.isExpired {
            return tokens.accessToken
        }

        // Try to refresh
        return try await refreshTokens(refreshToken: tokens.refreshToken)
    }

    /// Start the full browser-based OAuth login flow.
    func signIn() async throws {
        // Generate PKCE
        let pkce = generatePKCE()
        codeVerifier = pkce.verifier
        state = generateRandomString(length: 32)

        // Build auth URL
        var components = URLComponents(string: "\(Self.authBase)/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: callbackServer.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "audience", value: Self.audience),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "prompt", value: "login"),
        ]

        guard let authURL = components.url else {
            throw OAuthError.serverStartFailed
        }

        // Open browser
        print("🌐 Opening browser for ChatGPT login...")
        NSWorkspace.shared.open(authURL)

        // Wait for callback
        let code = try await callbackServer.waitForCallback()

        // Exchange code for tokens
        let tokens = try await exchangeCodeForTokens(
            code: code,
            redirectURI: callbackServer.redirectURI
        )

        // Store tokens
        try keychain.saveTokens(tokens)
        print("✅ Signed in as \(tokens.email ?? "unknown")")
    }

    /// Sign out and delete stored tokens.
    func signOut() {
        keychain.deleteTokens()
        print("👋 Signed out")
    }

    // MARK: - Token Exchange

    private func exchangeCodeForTokens(code: String, redirectURI: String) async throws -> KeychainStore.AuthTokens {
        guard let verifier = codeVerifier else {
            throw OAuthError.noCode
        }

        let url = URL(string: "\(Self.authBase)/oauth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": verifier,
            "client_id": Self.clientID,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.tokenExchangeFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw OAuthError.tokenExchangeFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        return try parseTokenResponse(data)
    }

    private func refreshTokens(refreshToken: String) async throws -> String {
        let url = URL(string: "\(Self.authBase)/oauth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            // Refresh failed — need to re-login
            keychain.deleteTokens()
            throw OAuthError.tokenExchangeFailed("Token refresh failed")
        }

        let tokens = try parseTokenResponse(data)
        try keychain.saveTokens(tokens)
        return tokens.accessToken
    }

    private func parseTokenResponse(_ data: Data) throws -> KeychainStore.AuthTokens {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OAuthError.tokenExchangeFailed("Invalid JSON")
        }

        guard let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String else {
            throw OAuthError.tokenExchangeFailed("Missing tokens in response")
        }

        let expiresIn = json["expires_in"] as? Int ?? 3600

        // Try to extract email from id_token (JWT)
        var email: String? = nil
        if let idToken = json["id_token"] as? String {
            email = Self.extractEmailFromJWT(idToken)
        }

        return KeychainStore.AuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            idToken: json["id_token"] as? String,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            email: email,
            plan: nil // Plan info would come from a separate API call
        )
    }

    // MARK: - PKCE

    private func generatePKCE() -> (verifier: String, challenge: String) {
        let verifier = generateRandomString(length: 64)
        let challenge = Self.sha256Base64URL(verifier)
        return (verifier, challenge)
    }

    private func generateRandomString(length: Int) -> String {
        var buffer = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &buffer)
        return Data(buffer)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .prefix(length)
            .lowercased()
    }

    static func sha256Base64URL(_ input: String) -> String {
        let data = input.data(using: .utf8)!
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - JWT Parsing

    /// Extract email from id_token JWT payload (no verification — just parsing).
    static func extractEmailFromJWT(_ jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return nil }

        // Decode payload (2nd part)
        var payload = String(parts[1])
        // Add padding
        while payload.count % 4 != 0 { payload += "=" }
        payload = payload.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return json["email"] as? String
    }
}
