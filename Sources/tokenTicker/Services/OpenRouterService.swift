import Foundation

final class OpenRouterService: ProviderService {
    let providerID: ProviderID = .openRouter
    private let apiKey: String?
    private let session: URLSession

    init(apiKey: String?, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func fetchSnapshot() async -> ProviderSnapshot {
        guard let key = apiKey, !key.isEmpty else {
            return .empty(.openRouter)
        }
        do {
            async let balance = fetchBalance(key: key)
            async let costToday = fetchCost(key: key, since: .startOfToday)
            async let costMonth = fetchCost(key: key, since: .startOfMonth)
            return ProviderSnapshot(
                provider: .openRouter,
                costToday: try await costToday,
                costThisMonth: try await costMonth,
                balance: try await balance,
                claudeUtilization: nil,
                updatedAt: .now,
                error: nil
            )
        } catch {
            return ProviderSnapshot(provider: .openRouter, costToday: 0,
                                    costThisMonth: nil, balance: nil,
                                    claudeUtilization: nil, updatedAt: .now,
                                    error: .networkError(error.localizedDescription))
        }
    }

    private func fetchBalance(key: String) async throws -> Decimal {
        let url = URL(string: "https://openrouter.ai/api/v1/credits")!
        let data = try await get(url: url, key: key)
        guard let balance = try Self.parseBalance(from: data) else {
            throw ProviderError.decodingError("balance")
        }
        return balance
    }

    private func fetchCost(key: String, since date: Date) async throws -> Decimal {
        var comps = URLComponents(string: "https://openrouter.ai/api/v1/activity")!
        comps.queryItems = [
            .init(name: "start_time", value: String(Int(date.timeIntervalSince1970))),
            .init(name: "end_time", value: String(Int(Date.now.timeIntervalSince1970)))
        ]
        let data = try await get(url: comps.url!, key: key)
        return try Self.parseCost(from: data) ?? 0
    }

    private func get(url: URL, key: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ProviderError.networkError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        return data
    }

    // MARK: - Parsing (internal for testability)

    static func parseBalance(from data: Data) throws -> Decimal? {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let dataObj = json?["data"] as? [String: Any],
              let total = dataObj["total_credits"] as? Double,
              let usage = dataObj["usage"] as? Double
        else { return nil }
        return Decimal(total - usage)
    }

    static func parseCost(from data: Data) throws -> Decimal? {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let dataObj = json?["data"] as? [String: Any],
              let cost = dataObj["total_cost"] as? Double
        else { return nil }
        return Decimal(cost)
    }
}

private extension Date {
    static var startOfToday: Date {
        Calendar.current.startOfDay(for: .now)
    }
    static var startOfMonth: Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: .now)
        return cal.date(from: comps)!
    }
}
