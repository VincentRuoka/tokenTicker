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
            .appendingPathComponent(".config/tokenTicker", isDirectory: true)
        try? FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        return config.appendingPathComponent("history.json")
    }

    nonisolated static func dateKey(for date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    func persist(provider: ProviderID, cost: Decimal) {
        let key = Self.dateKey()
        var day = store.days[key] ?? [:]
        day[provider.rawValue] = ProviderEntry(cost: "\(cost)", updatedAt: ISO8601DateFormatter().string(from: .now))
        store.days[key] = day
        pruneOldEntries()
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

    // For testing only
    func injectEntry(date: Date, provider: ProviderID, cost: Decimal) {
        let key = Self.dateKey(for: date)
        var day = store.days[key] ?? [:]
        day[provider.rawValue] = ProviderEntry(cost: "\(cost)", updatedAt: "")
        store.days[key] = day
        save()
    }

    func allDateKeys() -> [String] { Array(store.days.keys) }

    // MARK: - Private

    private func pruneOldEntries() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now)!
        store.days = store.days.filter { key, _ in
            guard let date = Self.date(from: key) else { return false }
            return date >= cutoff
        }
    }

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
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }

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
