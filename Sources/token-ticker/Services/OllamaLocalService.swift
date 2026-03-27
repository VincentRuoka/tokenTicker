import Foundation

final class OllamaLocalService: ProviderService {
    let providerID: ProviderID = .ollamaLocal

    // Injected price (for testing). When nil, reads from UserDefaults at call time.
    private let injectedPricePerK: Decimal?

    init(tokenPricePerK: Decimal? = nil) {
        self.injectedPricePerK = tokenPricePerK
    }

    // MARK: - ProviderService

    func fetchSnapshot() async -> ProviderSnapshot {
        let since = Calendar.current.startOfDay(for: Date())
        let proxyEnabled = UserDefaults.standard.bool(forKey: "ollamaProxyEnabled")

        let logURL: URL
        let home = FileManager.default.homeDirectoryForCurrentUser

        if proxyEnabled {
            logURL = home
                .appendingPathComponent(".config/token-ticker/ollama-proxy.log")
        } else {
            logURL = home
                .appendingPathComponent(".ollama/logs/server.log")
        }

        let content: String
        do {
            content = try await Task.detached(priority: .utility) {
                try String(contentsOf: logURL, encoding: .utf8)
            }.value
        } catch {
            let monthCost = await MainActor.run { HistoryStore.shared.costThisMonth(for: .ollamaLocal) }
            return ProviderSnapshot(
                provider: .ollamaLocal,
                costToday: 0, cost7d: 0, cost30d: 0,
                costThisMonth: monthCost,
                balance: nil, allTimeUsage: nil,
                claudeUtilization: nil,
                updatedAt: .now,
                error: .logNotFound
            )
        }

        let tokens: (promptTokens: Int, completionTokens: Int)
        if proxyEnabled {
            tokens = Self.parseTokensFromProxyLog(content: content, since: since)
        } else {
            tokens = Self.parseTokensFromLog(content: content, since: since)
        }

        let totalTokens = tokens.promptTokens + tokens.completionTokens
        let costToday = calculateCost(totalTokens: totalTokens)
        let monthCost = await MainActor.run { HistoryStore.shared.costThisMonth(for: .ollamaLocal) }

        return ProviderSnapshot(
            provider: .ollamaLocal,
            costToday: costToday, cost7d: 0, cost30d: 0,
            costThisMonth: monthCost,
            balance: nil, allTimeUsage: nil,
            claudeUtilization: nil,
            updatedAt: .now,
            error: nil
        )
    }

    // MARK: - Cost Calculation

    /// Calculates cost for a given total token count using the configured price per 1k tokens.
    func calculateCost(totalTokens: Int) -> Decimal {
        let pricePerK: Decimal
        if let injected = injectedPricePerK {
            pricePerK = injected
        } else {
            let raw = UserDefaults.standard.double(forKey: "ollamaTokenPricePerK")
            pricePerK = Decimal(string: String(raw)) ?? 0
        }
        return Decimal(totalTokens) * pricePerK / 1000
    }

    // MARK: - Cached formatters

    private static let isoFormatterFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Server Log Parsing

    /// Parses token counts from Ollama server log content.
    /// Only counts log lines whose timestamp is >= `since`.
    static func parseTokensFromLog(content: String, since: Date) -> (promptTokens: Int, completionTokens: Int) {
        let formatter = isoFormatterFrac
        let formatterNoFrac = isoFormatter

        var promptTokens = 0
        var completionTokens = 0

        for line in content.components(separatedBy: .newlines) {
            guard !line.isEmpty else { continue }

            // Extract timestamp: time=<value>
            guard let timeRange = line.range(of: "time=") else { continue }
            let afterTime = line[timeRange.upperBound...]
            // Timestamp ends at the next space
            let timestampStr: String
            if let spaceIdx = afterTime.firstIndex(of: " ") {
                timestampStr = String(afterTime[afterTime.startIndex..<spaceIdx])
            } else {
                timestampStr = String(afterTime)
            }

            let lineDate = formatter.date(from: timestampStr)
                ?? formatterNoFrac.date(from: timestampStr)
            guard let date = lineDate, date >= since else { continue }

            // Check for "prompt eval count:" before "eval count:" — the latter is a substring
            // of the former, so order matters. Using else-if guarantees mutual exclusion.
            if line.contains("prompt eval count:") {
                // Extract token count from "prompt eval count: N tokens"
                if let n = extractNumber(after: "prompt eval count:", in: line) {
                    promptTokens += n
                }
            } else if line.contains("eval count:") {
                // Completion line (not a prompt eval line)
                if let n = extractNumber(after: "eval count:", in: line) {
                    completionTokens += n
                }
            }
        }

        return (promptTokens, completionTokens)
    }

    // MARK: - Proxy Log Parsing

    /// Parses token counts from proxy log (one JSON object per line).
    static func parseTokensFromProxyLog(content: String, since: Date) -> (promptTokens: Int, completionTokens: Int) {
        let formatter = isoFormatter

        var promptTokens = 0
        var completionTokens = 0

        struct ProxyEntry: Decodable {
            let promptTokens: Int
            let completionTokens: Int
            let timestamp: String
        }

        for line in content.components(separatedBy: .newlines) {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let entry = try? JSONDecoder().decode(ProxyEntry.self, from: data),
                  let date = formatter.date(from: entry.timestamp),
                  date >= since
            else { continue }

            promptTokens += entry.promptTokens
            completionTokens += entry.completionTokens
        }

        return (promptTokens, completionTokens)
    }

    // MARK: - Helpers

    private static func extractNumber(after prefix: String, in line: String) -> Int? {
        guard let prefixRange = line.range(of: prefix) else { return nil }
        let rest = line[prefixRange.upperBound...].trimmingCharacters(in: .whitespaces)
        // rest looks like "128 tokens" or "128 tokens\""
        let parts = rest.components(separatedBy: .whitespaces)
        guard let first = parts.first, let n = Int(first) else { return nil }
        return n
    }
}
