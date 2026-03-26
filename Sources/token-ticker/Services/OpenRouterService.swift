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
        guard let key = apiKey, !key.isEmpty else { return .empty(.openRouter) }
        do {
            async let balanceData  = fetchRaw(url: URL(string: "https://openrouter.ai/api/v1/credits")!, key: key)
            async let activityData = fetchActivityRaw(key: key)

            let (bData, aData) = try await (balanceData, activityData)

            let balance    = try Self.parseBalance(from: bData)
            let costToday  = Self.parseCost(from: aData, granularity: .day)  ?? 0
            let costMonth  = Self.parseCost(from: aData, granularity: .month) ?? 0

            // Backfill historical data for the chart
            await backfillHistory(from: aData)

            return ProviderSnapshot(
                provider: .openRouter,
                costToday: costToday,
                costThisMonth: costMonth,
                balance: balance,
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

    // MARK: - Fetch helpers

    private func fetchActivityRaw(key: String) async throws -> Data {
        var comps = URLComponents(string: "https://openrouter.ai/api/v1/activity")!
        // start_time=0 requests maximum history; the API currently returns its own
        // fixed window regardless, but this future-proofs the request.
        comps.queryItems = [
            .init(name: "start_time", value: "0"),
            .init(name: "end_time",   value: String(Int(Date.now.timeIntervalSince1970)))
        ]
        return try await fetchRaw(url: comps.url!, key: key)
    }

    private func fetchRaw(url: URL, key: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)",                    forHTTPHeaderField: "Authorization")
        request.setValue("https://github.com/token-ticker", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Token Ticker",                     forHTTPHeaderField: "X-Title")
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(data: data, encoding: .utf8) ?? "<binary>"
        print("[OpenRouter] \(statusCode) GET \(url)\n\(body)\n")
        guard statusCode == 200 else {
            throw ProviderError.networkError("HTTP \(statusCode)")
        }
        return data
    }

    // MARK: - Cached formatters

    /// Parses "yyyy-MM-dd" date strings from the OpenRouter activity API (UTC timezone).
    private static let utcDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Extracts the local calendar day from an activity entry's "date" field.
    /// Adds 12 h to UTC midnight so the result is stable across ±11 h timezones.
    private static func localDate(from entry: [String: Any]) -> Date? {
        guard let raw = entry["date"] as? String,
              let prefix = raw.split(separator: " ").first.map(String.init),
              let utcDay = utcDateFormatter.date(from: prefix) else { return nil }
        return utcDay.addingTimeInterval(12 * 3600)
    }

    // MARK: - History backfill

    private func backfillHistory(from data: Data) async {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["data"] as? [[String: Any]] else { return }

        // Group by local calendar day → sum usage, and log every raw row
        var byDay: [Date: Double] = [:]
        print("[OpenRouter] ── Raw activity rows (\(entries.count) entries) ──")
        for entry in entries {
            let date    = entry["date"]          as? String ?? "?"
            let model   = entry["model"]         as? String ?? "?"
            let usage   = entry["usage"]         as? Double ?? 0
            let reqs    = entry["requests"]      as? Int    ?? 0
            let provider = entry["provider_name"] as? String ?? "?"
            print("[OpenRouter]   \(date)  \(String(format: "%.6f", usage))$  \(reqs)req  \(model) @ \(provider)")

            guard let localDay = Self.localDate(from: entry) else { continue }
            let dayStart = Calendar.current.startOfDay(for: localDay)
            byDay[dayStart, default: 0] += usage
        }

        // Log the per-day totals we'll store
        let cal = Calendar.current
        let sortedDays = byDay.keys.sorted()
        print("[OpenRouter] ── Per-day totals ──")
        var grandTotal = 0.0
        for day in sortedDays {
            let cost = byDay[day]!
            grandTotal += cost
            let label = cal.isDateInToday(day) ? "TODAY" : cal.isDateInYesterday(day) ? "YESTERDAY" : ""
            print("[OpenRouter]   \(Self.utcDateFormatter.string(from: day))  $\(String(format: "%.5f", cost))  \(label)")
        }
        print("[OpenRouter] ── Grand total: $\(String(format: "%.5f", grandTotal)) ──")

        let snapshot = byDay
        await MainActor.run {
            for (date, cost) in snapshot {
                HistoryStore.shared.backfill(date: date, provider: .openRouter, cost: Decimal(cost))
            }
        }
    }

    // MARK: - Parsing (internal for testability)

    static func parseBalance(from data: Data) throws -> Decimal? {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any] else { return nil }

        // Format A: total_credits - (usage or total_usage)
        if let total = dataObj["total_credits"] as? Double {
            let usage = (dataObj["usage"] as? Double)
                     ?? (dataObj["total_usage"] as? Double)
                     ?? 0.0
            return Decimal(total) - Decimal(usage)
        }
        // Format B: direct balance field
        if let balance = dataObj["balance"] as? Double {
            return Decimal(balance)
        }
        return nil
    }

    static func parseCost(from data: Data, granularity: Calendar.Component = .month) -> Decimal? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["data"] as? [[String: Any]] else { return nil }

        let cal = Calendar.current
        let now = Date.now

        let total = entries
            .filter { entry in
                guard let localDay = localDate(from: entry) else { return false }
                return cal.isDate(localDay, equalTo: now, toGranularity: granularity)
            }
            .compactMap { $0["usage"] as? Double }
            .reduce(0.0, +)
        return Decimal(total)
    }
}
