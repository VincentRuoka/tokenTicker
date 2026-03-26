import Foundation

@MainActor
final class HistoryStore {
    private let fileURL: URL
    private var store: HistoryData = HistoryData()

    static let shared = HistoryStore()

    init(fileURL: URL = HistoryStore.defaultURL) {
        self.fileURL = fileURL
        load()
    }

    nonisolated static var defaultURL: URL {
        let config = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/token-ticker", isDirectory: true)
        try? FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        return config.appendingPathComponent("history.json")
    }

    nonisolated static func dateKey(for date: Date = .now) -> String {
        Self.dateFormatter.string(from: date)
    }

    func persist(provider: ProviderID, cost: Decimal) {
        let key = Self.dateKey()
        var day = store.days[key] ?? [:]
        day[provider.rawValue] = ProviderEntry(cost: "\(cost)", updatedAt: Self.isoFormatter.string(from: .now))
        store.days[key] = day
        save()
    }

    func costToday(for provider: ProviderID) -> Decimal {
        let key = Self.dateKey()
        return decimal(store.days[key]?[provider.rawValue]?.cost)
    }

    func costThisMonth(for provider: ProviderID) -> Decimal {
        let cal = Calendar.current
        let now = Date.now
        return store.days
            .filter { key, _ in
                guard let date = Self.date(from: key) else { return false }
                return cal.isDate(date, equalTo: now, toGranularity: .month)
            }
            .compactMap { _, day in day[provider.rawValue]?.cost }
            .compactMap { Decimal(string: $0) }
            .reduce(0, +)
    }

    func backfill(date: Date, provider: ProviderID, cost: Decimal) {
        let key = Self.dateKey(for: date)
        var day = store.days[key] ?? [:]
        // Always update from the API — persist() runs after and will correctly overwrite
        // today's entry with a live updatedAt. Historical entries must be correctable.
        day[provider.rawValue] = ProviderEntry(cost: "\(cost)", updatedAt: "")
        store.days[key] = day
        save()
    }

    func allDateKeys() -> [String] { Array(store.days.keys) }

    /// Sum of all stored daily costs for a provider across all stored history.
    func totalStoredCost(for provider: ProviderID) -> Decimal {
        store.days.values
            .compactMap { $0[provider.rawValue]?.cost }
            .compactMap { Decimal(string: $0) }
            .reduce(0, +)
    }

    /// Returns daily costs for a provider over the last `days` days, oldest first.
    func dailyCosts(for provider: ProviderID, days: Int = 30) -> [(date: Date, cost: Double)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return (0..<days).reversed().compactMap { offset -> (date: Date, cost: Double)? in
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = Self.dateKey(for: date)
            guard let costStr = store.days[key]?[provider.rawValue]?.cost,
                  let cost = Double(costStr), cost > 0 else { return nil }
            return (date: date, cost: cost)
        }
    }

    func deleteAll() {
        store.days = [:]
        save()
    }

    // MARK: - Private

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(HistoryData.self, from: data)
        else { return }
        store = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func date(from key: String) -> Date? {
        dateFormatter.date(from: key)
    }

    // Cached formatters — DateFormatter and ISO8601DateFormatter are expensive to initialise
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    private nonisolated(unsafe) static let isoFormatter = ISO8601DateFormatter()

    private func decimal(_ string: String?) -> Decimal {
        guard let s = string else { return 0 }
        return Decimal(string: s) ?? 0
    }
}

// MARK: - Codable types

private struct HistoryData: Codable {
    var version: Int = 1
    var days: [String: [String: ProviderEntry]] = [:]
}

private struct ProviderEntry: Codable {
    var cost: String
    var updatedAt: String
}
