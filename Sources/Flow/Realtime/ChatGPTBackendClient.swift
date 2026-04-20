import Foundation

/// Backend API client for the ChatGPT web app backend.
///
/// From the Codex RE, we know:
/// - Codex authenticates via ChatGPT OAuth → gets access token
/// - Uses that token to hit `backend-api/realtime/calls` (WebRTC SDP exchange)
/// - Also has a WebSocket path for streaming
///
/// This module provides two paths to use the Realtime API:
///
/// **Path A: Developer API** (simpler, costs money)
///   wss://api.openai.com/v1/realtime with Bearer token
///
/// **Path B: ChatGPT Backend** (free with subscription, experimental)
///   POST https://chatgpt.com/backend-api/realtime/calls with session cookie
///   OR wss://chatgpt.com/backend-api/realtime with access token
///
/// Path B is what Codex uses. The access token from auth0.openai.com OAuth
/// works as a Bearer token for backend-api endpoints.
final class ChatGPTBackendClient {
    private let baseURL = "https://chatgpt.com/backend-api"

    struct BackendSessionInfo {
        let accessToken: String
        let orgId: String?
    }

    // MARK: - Check Subscription

    /// Fetch the user's ChatGPT subscription info.
    /// Returns plan type, usage, and whether realtime is available.
    static func fetchSubscriptionInfo(accessToken: String) async throws -> SubscriptionInfo {
        let url = URL(string: "https://chatgpt.com/backend-api/accounts/check/v4-2023-04-27")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw BackendError.authFailed("HTTP \(httpResponse.statusCode)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BackendError.invalidResponse
        }

        // Parse the subscription info
        var plan = "free"
        var isPaid = false

        if let accounts = json["accounts"] as? [String: Any] {
            // Look for the user's account
            for (_, account) in accounts {
                if let acct = account as? [String: Any],
                   let accountInfo = acct["account"] as? [String: Any] {
                    plan = accountInfo["plan_type"] as? String ?? "free"
                    isPaid = accountInfo["is_deactivated"] as? Bool != true && plan != "free"
                }
            }
        }

        return SubscriptionInfo(
            planType: plan,
            isPaid: isPaid,
            hasRealtimeAccess: isPaid // Plus/Pro/Team/Business all have realtime
        )
    }

    // MARK: - Realtime via Backend API (WebRTC path)

    /// Create a Realtime session via the ChatGPT backend.
    /// This is the same path Codex uses: POST /realtime/calls with SDP offer.
    ///
    /// Returns an SDP answer that configures the WebRTC peer connection.
    static func createRealtimeCall(
        accessToken: String,
        sdpOffer: String,
        sessionConfig: String? = nil
    ) async throws -> RealtimeCallResponse {
        let url = URL(string: "https://chatgpt.com/backend-api/realtime/calls")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/sdp", forHTTPHeaderField: "Content-Type")

        if let config = sessionConfig {
            // If session config is provided, use multipart
            let boundary = "flow-boundary-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            var body = Data()
            // SDP part
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"sdp\"\r\n\r\n".data(using: .utf8)!)
            body.append(sdpOffer.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
            // Session config part
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"session\"; filename=\"session.json\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
            body.append(config.data(using: .utf8)!)
            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
            request.httpBody = body
        } else {
            request.httpBody = sdpOffer.data(using: .utf8)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw BackendError.authFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        // Parse SDP answer from response body
        let sdpAnswer = String(data: data, encoding: .utf8) ?? ""

        // Parse call_id from Location header
        let callId = httpResponse.value(forHTTPHeaderField: "Location")?
            .components(separatedBy: "/").last ?? UUID().uuidString

        return RealtimeCallResponse(sdp: sdpAnswer, callId: callId)
    }

    // MARK: - Realtime via WebSocket (simpler path)

    /// Build the WebSocket URL for the ChatGPT backend Realtime API.
    /// This may work as an alternative to the WebRTC path.
    static func backendRealtimeURL(model: String = "gpt-realtime-1.5") -> URL {
        URL(string: "wss://chatgpt.com/backend-api/realtime?model=\(model)")!
    }
}

// MARK: - Types

struct SubscriptionInfo {
    let planType: String
    let isPaid: Bool
    let hasRealtimeAccess: Bool

    var displayName: String {
        switch planType.lowercased() {
        case "chatgptplus", "plus": return "ChatGPT Plus"
        case "chatgptpro", "pro": return "ChatGPT Pro"
        case "chatgptteam", "team": return "ChatGPT Team"
        case "chatgptbusiness", "business": return "ChatGPT Business"
        case "chatgptenterprise", "enterprise": return "ChatGPT Enterprise"
        default: return planType.capitalized
        }
    }
}

struct RealtimeCallResponse {
    let sdp: String
    let callId: String
}

enum BackendError: LocalizedError {
    case invalidResponse
    case authFailed(String)
    case noSession

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from ChatGPT backend"
        case .authFailed(let msg): return "Backend auth failed: \(msg)"
        case .noSession: return "No active session"
        }
    }
}
