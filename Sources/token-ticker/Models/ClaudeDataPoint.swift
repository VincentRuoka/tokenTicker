import Foundation

// MARK: - Model

struct ClaudeDataPoint: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let fiveHourPct: Double
    let sevenDayPct: Double
}

// MARK: - History store

@MainActor
final class ClaudeUsageHistory {
    static let shared = ClaudeUsageHistory()

    private var points: [ClaudeDataPoint] = []

    private static let fileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/token-ticker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("claude-usage.json")
    }()

    init() { load() }

    // MARK: - Public API

    func append(_ utilization: ClaudeUtilization) {
        let point = ClaudeDataPoint(
            id: UUID(),
            timestamp: .now,
            fiveHourPct: utilization.fiveHourPct,
            sevenDayPct: utilization.sevenDayPct
        )
        points.append(point)
        prune()
        save()
    }

    /// Returns points within the given time window (most recent first after filtering).
    func points(since date: Date) -> [ClaudeDataPoint] {
        points.filter { $0.timestamp >= date }
    }

    func allPoints() -> [ClaudeDataPoint] { points }

    // MARK: - Private

    private func prune() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: .now)!
        points = points.filter { $0.timestamp > cutoff }
        // Also cap at 2000 points to keep file size manageable
        if points.count > 2000 {
            points = Array(points.suffix(2000))
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode([ClaudeDataPoint].self, from: data)
        else { return }
        points = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(points) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
