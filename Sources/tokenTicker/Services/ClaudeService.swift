import Foundation
import AppKit

final class ClaudeService: ProviderService {
    let providerID: ProviderID = .claude
    static let shared = ClaudeService()

    private let clientID = "9d04ca1f-6ac0-484e-9e42-c0e5c3a5d347" // claude-usage-bar client ID
    private let redirectURI = "tokenticker://oauth"

    func fetchSnapshot() async -> ProviderSnapshot {
        guard let accessToken = validAccessToken() else {
            return ProviderSnapshot(provider: .claude, costToday: 0,
                                    costThisMonth: nil, balance: nil,
                                    claudeUtilization: nil, updatedAt: .now,
                                    error: .missingCredentials)
        }
        do {
            let utilization = try await fetchUtilization(token: accessToken)
            return ProviderSnapshot(provider: .claude, costToday: 0,
                                    costThisMonth: nil, balance: nil,
                                    claudeUtilization: utilization,
                                    updatedAt: .now, error: nil)
        } catch {
            return ProviderSnapshot(provider: .claude, costToday: 0,
                                    costThisMonth: nil, balance: nil,
                                    claudeUtilization: nil, updatedAt: .now,
                                    error: .networkError(error.localizedDescription))
        }
    }

    // MARK: - OAuth Flow

    func startOAuthFlow() {
        let (verifier, challenge) = PKCEHelper.generatePair()
        _ = Keychain.save(verifier, for: Keychain.claudeCodeVerifier)
        var comps = URLComponents(string: "https://claude.ai/oauth/authorize")!
        comps.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "scope", value: "org:read_usage")
        ]
        NSWorkspace.shared.open(comps.url!)
    }

    func exchangeCode(_ code: String) async {
        guard let verifier = Keychain.load(for: Keychain.claudeCodeVerifier) else { return }
        Keychain.delete(for: Keychain.claudeCodeVerifier)
        do {
            let tokens = try await requestTokens(code: code, verifier: verifier)
            _ = Keychain.save(tokens.accessToken, for: Keychain.claudeAccessToken)
            _ = Keychain.save(tokens.refreshToken ?? "", for: Keychain.claudeRefreshToken)
            _ = Keychain.save(String(tokens.expiresAt), for: Keychain.claudeExpiresAt)
        } catch {
            print("Claude token exchange failed: \(error)")
        }
    }

    // MARK: - Private

    private func validAccessToken() -> String? {
        guard let token = Keychain.load(for: Keychain.claudeAccessToken),
              let expiresAtStr = Keychain.load(for: Keychain.claudeExpiresAt),
              let expiresAt = TimeInterval(expiresAtStr) else { return nil }
        let expiresDate = Date(timeIntervalSince1970: expiresAt)
        if expiresDate.timeIntervalSinceNow < 60 {
            // Refresh token in background — will succeed on next poll
            Task { await refreshTokens() }
            return nil
        }
        return token
    }

    private func refreshTokens() async {
        guard let refreshToken = Keychain.load(for: Keychain.claudeRefreshToken),
              !refreshToken.isEmpty else { return }
        var request = URLRequest(url: URL(string: "https://platform.claude.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID
        ])
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let tokens = try? JSONDecoder().decode(TokenResponse.self, from: data)
        else { return }
        _ = Keychain.save(tokens.accessToken, for: Keychain.claudeAccessToken)
        if let newRefresh = tokens.refreshToken {
            _ = Keychain.save(newRefresh, for: Keychain.claudeRefreshToken)
        }
        _ = Keychain.save(String(tokens.expiresAt), for: Keychain.claudeExpiresAt)
    }

    private func requestTokens(code: String, verifier: String) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://platform.claude.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier
        ])
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func fetchUtilization(token: String) async throws -> ClaudeUtilization {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ProviderError.networkError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        return try parseUtilization(from: data)
    }

    private func parseUtilization(from data: Data) throws -> ClaudeUtilization {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fiveHour = json["fiveHour"] as? [String: Any],
              let sevenDay = json["sevenDay"] as? [String: Any],
              let extraUsage = json["extraUsage"] as? [String: Any]
        else { throw ProviderError.decodingError("usage response") }

        let isoFormatter = ISO8601DateFormatter()
        return ClaudeUtilization(
            fiveHourPct: fiveHour["utilization"] as? Double ?? 0,
            sevenDayPct: sevenDay["utilization"] as? Double ?? 0,
            extraUsagePct: extraUsage["utilization"] as? Double ?? 0,
            fiveHourResetsAt: isoFormatter.date(from: fiveHour["resetsAtDate"] as? String ?? "") ?? .now,
            sevenDayResetsAt: isoFormatter.date(from: sevenDay["resetsAtDate"] as? String ?? "") ?? .now
        )
    }
}

private struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: TimeInterval

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_in"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try c.decode(String.self, forKey: .accessToken)
        refreshToken = try? c.decode(String.self, forKey: .refreshToken)
        let expiresIn = try c.decode(TimeInterval.self, forKey: .expiresAt)
        expiresAt = Date.now.timeIntervalSince1970 + expiresIn
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(accessToken, forKey: .accessToken)
        try c.encodeIfPresent(refreshToken, forKey: .refreshToken)
        try c.encode(expiresAt, forKey: .expiresAt)
    }
}
