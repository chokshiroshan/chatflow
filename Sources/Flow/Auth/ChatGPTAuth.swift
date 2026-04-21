import Foundation
import AppKit
import CryptoKit
import CommonCrypto

/// Authenticates with ChatGPT via OAuth PKCE using the ChatGPT web app client ID.
///
/// Uses the same client ID as chatgpt.com web app (app_X8zY6vW2pQ9tR3dE7nK1jL5gH)
/// which works with regular ChatGPT subscriptions (no API org needed).
///
/// Flow:
/// 1. Generate PKCE code_verifier + code_challenge
/// 2. Open system browser to auth.openai.com/authorize
/// 3. User logs in → browser redirects to localhost with auth code
/// 4. Exchange code for tokens (access + refresh via offline_access scope)
/// 5. Store refresh token → auto-refresh access tokens before expiry
final class ChatGPTAuth: @unchecked Sendable, ObservableObject {
    static let shared = ChatGPTAuth()

    @Published var authState: AuthState = .signedOut
    @Published var userEmail: String?

    /// Current access token (if signed in)
    private(set) var accessToken: String?

    private let keychain = KeychainStore.shared
    private var callbackServer: OAuthCallbackServer?

    // MARK: - OAuth Config (ChatGPT web app client)

    private let clientID = "app_X8zY6vW2pQ9tR3dE7nK1jL5gH"
    private let issuer = "https://auth.openai.com"
    private let scopes = "openid email profile offline_access model.request model.read organization.read"
    private let redirectPath = "/auth/callback"

    init() {
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
                // Generate PKCE
                let verifier = Self.generateCodeVerifier()
                let challenge = Self.generateCodeChallenge(from: verifier)
                let state = Self.randomString(length: 32)

                // Start callback server
                let server = OAuthCallbackServer()
                server.path = redirectPath
                self.callbackServer = server
                let port = try server.start(fixedPort: 1455)
                let redirectURI = "http://localhost:\(port)\(redirectPath)"

                // Build authorize URL
                var components = URLComponents(string: "\(issuer)/oauth/authorize")!
                components.queryItems = [
                    URLQueryItem(name: "client_id", value: clientID),
                    URLQueryItem(name: "redirect_uri", value: redirectURI),
                    URLQueryItem(name: "response_type", value: "code"),
                    URLQueryItem(name: "scope", value: scopes),
                    URLQueryItem(name: "code_challenge", value: challenge),
                    URLQueryItem(name: "code_challenge_method", value: "S256"),
                    URLQueryItem(name: "state", value: state),
                    URLQueryItem(name: "audience", value: "https://api.openai.com/v1"),
                ]

                guard let authURL = components.url else {
                    throw AuthError.serverFailed
                }

                print("🌐 Opening OAuth: \(authURL)")
                NSWorkspace.shared.open(authURL)

                // Wait for callback with auth code
                let result = try await server.waitForCallback()
                server.stop()
                self.callbackServer = nil

                guard result.state == state else {
                    throw AuthError.authFailed("State mismatch")
                }

                // Exchange code for tokens
                let tokens = try await exchangeCode(result.code, verifier: verifier, redirectURI: redirectURI)

                self.accessToken = tokens.accessToken
                let email = Self.extractEmailFromJWT(tokens.accessToken)

                try keychain.saveTokens(tokens)

                let displayEmail = email ?? "ChatGPT User"
                DispatchQueue.main.async {
                    self.userEmail = displayEmail
                    self.authState = .signedIn(email: displayEmail, plan: "ChatGPT")
                }
                print("✅ Authenticated as \(displayEmail) (refresh token: \(tokens.refreshToken.isEmpty ? "NO" : "YES"))")

            } catch {
                print("❌ Auth failed: \(error)")
                self.callbackServer?.stop()
                self.callbackServer = nil
                DispatchQueue.main.async {
                    self.authState = .error(error.localizedDescription)
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
        guard let tokens = keychain.loadTokens(),
              !tokens.refreshToken.isEmpty else {
            return false
        }

        // If not expired, just return current token
        if !tokens.isExpired {
            accessToken = tokens.accessToken
            return true
        }

        print("🔄 Refreshing access token...")
        do {
            let newTokens = try await refreshToken(tokens.refreshToken)
            try keychain.saveTokens(newTokens)
            accessToken = newTokens.accessToken

            let email = Self.extractEmailFromJWT(newTokens.accessToken) ?? userEmail
            DispatchQueue.main.async {
                self.userEmail = email
                self.authState = .signedIn(email: email ?? "ChatGPT User", plan: "ChatGPT")
            }
            print("✅ Token refreshed successfully")
            return true
        } catch {
            print("❌ Token refresh failed: \(error)")
            return false
        }
    }

    func ensureValidToken() async -> String? {
        // If token is still valid, return it
        if let tokens = keychain.loadTokens(), !tokens.isExpired {
            accessToken = tokens.accessToken
            return accessToken
        }

        // Try to refresh
        if await refreshAccessToken() {
            return accessToken
        }

        // Refresh failed, need re-auth
        DispatchQueue.main.async {
            self.authState = .signedOut
        }
        return nil
    }

    /// Check if the current token is still valid
    var isTokenValid: Bool {
        guard let tokens = keychain.loadTokens() else { return false }
        return !tokens.isExpired
    }

    // MARK: - OAuth Token Exchange

    private func exchangeCode(_ code: String, verifier: String, redirectURI: String) async throws -> KeychainStore.AuthTokens {
        var request = URLRequest(url: URL(string: "\(issuer)/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": verifier,
            "client_id": clientID,
            "redirect_uri": redirectURI,
        ]

        request.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResp = response as? HTTPURLResponse else {
            throw AuthError.authFailed("Invalid response")
        }

        guard httpResp.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            print("❌ Token exchange failed (\(httpResp.statusCode)): \(body)")
            throw AuthError.authFailed("Token exchange failed: \(httpResp.statusCode)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let accessToken = json["access_token"] as? String else {
            throw AuthError.authFailed("No access_token in response")
        }

        let refreshToken = json["refresh_token"] as? String ?? ""
        let expiresIn = json["expires_in"] as? TimeInterval ?? 3600
        let idToken = json["id_token"] as? String

        let email = Self.extractEmailFromJWT(accessToken)

        print("📋 Token response scopes: \(json["scope"] ?? "none")")
        print("📋 Refresh token present: \(!refreshToken.isEmpty)")

        return KeychainStore.AuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            idToken: idToken,
            expiresAt: Date().addingTimeInterval(expiresIn - 60),
            email: email,
            plan: "ChatGPT"
        )
    }

    private func refreshToken(_ refreshToken: String) async throws -> KeychainStore.AuthTokens {
        var request = URLRequest(url: URL(string: "\(issuer)/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw AuthError.authFailed("Refresh failed: \(body)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let accessToken = json["access_token"] as? String else {
            throw AuthError.authFailed("No access_token in refresh response")
        }

        let newRefreshToken = json["refresh_token"] as? String ?? refreshToken
        let expiresIn = json["expires_in"] as? TimeInterval ?? 3600
        let idToken = json["id_token"] as? String
        let email = Self.extractEmailFromJWT(accessToken)

        return KeychainStore.AuthTokens(
            accessToken: accessToken,
            refreshToken: newRefreshToken,
            idToken: idToken,
            expiresAt: Date().addingTimeInterval(expiresIn - 60),
            email: email,
            plan: "ChatGPT"
        )
    }

    // MARK: - PKCE Helpers

    private static func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, 64, &buffer)
        return Data(buffer).map { String(format: "%02x", $0) }.joined()
    }

    private static func generateCodeChallenge(from verifier: String) -> String {
        let data = verifier.data(using: .utf8)!
        let hashed = SHA256.hash(data: data)
        return Data(hashed).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func randomString(length: Int) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map { _ in chars.randomElement()! })
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

    static func extractExpiryFromJWT(_ jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        while payload.count % 4 != 0 { payload += "=" }

        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval else {
            return nil
        }

        return Date(timeIntervalSince1970: exp)
    }
}

enum AuthError: LocalizedError {
    case serverFailed
    case authFailed(String)

    var errorDescription: String? {
        switch self {
        case .serverFailed: return "Could not start local auth server"
        case .authFailed(let msg): return "Auth failed: \(msg)"
        }
    }
}
