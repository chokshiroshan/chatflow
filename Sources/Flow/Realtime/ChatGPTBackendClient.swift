import Foundation

/// Backend API client for the ChatGPT web app.
///
/// The access token from chatgpt.com localStorage works as a Bearer token
/// for backend-api endpoints — free with a ChatGPT subscription.
///
/// Key endpoints:
/// - Subscription check: GET /backend-api/accounts/check
/// - Realtime WebSocket: wss://chatgpt.com/backend-api/realtime
final class ChatGPTBackendClient {

    // MARK: - Check Subscription

    /// Fetch the user's ChatGPT subscription info.
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

        var plan = "free"
        var isPaid = false

        if let accounts = json["accounts"] as? [String: Any] {
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
            hasRealtimeAccess: isPaid
        )
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
