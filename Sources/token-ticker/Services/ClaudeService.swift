import Foundation

final class ClaudeService: ProviderService {
    let providerID: ProviderID = .claude
    static let shared = ClaudeService()

    // MARK: - ProviderService

    func fetchSnapshot() async -> ProviderSnapshot {
        guard let cookie = Keychain.load(for: Keychain.claudeSessionCookie), !cookie.isEmpty else {
            return .init(provider: .claude, costToday: 0, costThisMonth: nil,
                         balance: nil, claudeUtilization: nil, updatedAt: .now,
                         error: .missingCredentials)
        }
        do {
            let utilization = try await fetchUtilization(cookie: cookie)
            await ClaudeUsageHistory.shared.append(utilization)
            return .init(provider: .claude, costToday: 0, costThisMonth: nil,
                         balance: nil, claudeUtilization: utilization,
                         updatedAt: .now, error: nil)
        } catch {
            return .init(provider: .claude, costToday: 0, costThisMonth: nil,
                         balance: nil, claudeUtilization: nil, updatedAt: .now,
                         error: .networkError(error.localizedDescription))
        }
    }

    // MARK: - Private

    /// Builds a URLRequest pre-populated with the headers Claude's API expects.
    private func claudeRequest(url: URL, cookie: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue(cookie,               forHTTPHeaderField: "Cookie")
        req.setValue("*/*",                forHTTPHeaderField: "Accept")
        req.setValue("application/json",   forHTTPHeaderField: "Content-Type")
        req.setValue("https://claude.ai",  forHTTPHeaderField: "Origin")
        req.setValue("https://claude.ai",  forHTTPHeaderField: "Referer")
        req.setValue("claude.ai",          forHTTPHeaderField: "authority")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                                           forHTTPHeaderField: "User-Agent")
        return req
    }

    private func fetchUtilization(cookie: String) async throws -> ClaudeUtilization {
        // Extract org ID directly from the cookie — no extra API call needed
        let orgID = try await extractOrgID(from: cookie)
        print("[Claude] org from cookie: \(orgID)")

        let req = claudeRequest(url: URL(string: "https://claude.ai/api/organizations/\(orgID)/usage")!, cookie: cookie)

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(data: data, encoding: .utf8) ?? "<binary>"
        print("[Claude] usage \(status): \(body)")

        guard status == 200 else {
            throw ProviderError.networkError("HTTP \(status)")
        }
        return try parseUtilization(from: data)
    }

    /// Parses `lastActiveOrg=<uuid>` out of the session cookie string.
    /// Falls back to the bootstrap API if not found.
    private func extractOrgID(from cookie: String) async throws -> String {
        // Cookie format: "key1=val1; key2=val2; lastActiveOrg=<uuid>; ..."
        for part in cookie.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("lastActiveOrg=") {
                let value = String(trimmed.dropFirst("lastActiveOrg=".count))
                if !value.isEmpty { return value }
            }
        }

        // Fallback: bootstrap endpoint
        return try await fetchOrgIDFromBootstrap(cookie: cookie)
    }

    private func fetchOrgIDFromBootstrap(cookie: String) async throws -> String {
        let req = claudeRequest(url: URL(string: "https://claude.ai/api/bootstrap")!, cookie: cookie)

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(data: data, encoding: .utf8) ?? ""
        print("[Claude] bootstrap \(status): \(body.prefix(500))")

        guard status == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ProviderError.decodingError("bootstrap failed (\(status))") }

        // Shape: { account: { memberships: [ { organization: { uuid } } ] } }
        if let account  = json["account"]       as? [String: Any],
           let members  = account["memberships"] as? [[String: Any]],
           let org      = members.first?["organization"] as? [String: Any],
           let uuid     = org["uuid"] as? String { return uuid }

        // Shape: { organizations: [ { uuid } ] }
        if let orgs = json["organizations"] as? [[String: Any]],
           let uuid = orgs.first?["uuid"]   as? String { return uuid }

        throw ProviderError.decodingError("org UUID not found in bootstrap response")
    }

    // Response: { "five_hour": { "utilization": 0.42, "resets_at": "..." }, "seven_day": {...}, ... }
    private func parseUtilization(from data: Data) throws -> ClaudeUtilization {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ProviderError.decodingError("usage response not JSON") }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        func pct(_ key: String) -> Double {
            // API returns 0–100 (e.g. 9.0 = 9%). Divide to store as 0–1 fraction.
            let raw = (json[key] as? [String: Any])?["utilization"] as? Double ?? 0
            return raw / 100.0
        }
        func resetDate(_ key: String) -> Date {
            let s = (json[key] as? [String: Any])?["resets_at"] as? String ?? ""
            return iso.date(from: s) ?? .now
        }

        return ClaudeUtilization(
            fiveHourPct:       pct("five_hour"),
            sevenDayPct:       pct("seven_day"),
            extraUsagePct:     pct("seven_day_sonnet"),
            fiveHourResetsAt:  resetDate("five_hour"),
            sevenDayResetsAt:  resetDate("seven_day"),
            extraUsageResetsAt: resetDate("seven_day_sonnet")
        )
    }
}
