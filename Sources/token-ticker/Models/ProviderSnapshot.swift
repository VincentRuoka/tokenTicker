import Foundation

struct ClaudeUtilization {
    let fiveHourPct: Double
    let sevenDayPct: Double
    /// Non-zero only on Pro/Teams plans when extended (Sonnet) usage is available.
    let extraUsagePct: Double
    let fiveHourResetsAt: Date
    let sevenDayResetsAt: Date
    let extraUsageResetsAt: Date

    var hasExtraUsage: Bool { extraUsagePct > 0 }
}

enum ProviderError: Error, LocalizedError, Equatable {
    case missingCredentials
    case logNotFound
    case networkError(String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials: return "No API key configured"
        case .logNotFound: return "Ollama not running"
        case .networkError(let msg): return msg
        case .decodingError(let msg): return "Decode error: \(msg)"
        }
    }
}

struct ProviderSnapshot {
    let provider: ProviderID
    let costToday: Decimal
    let cost7d: Decimal            // last 7 days (direct from activity API)
    let cost30d: Decimal           // last 30 days (direct from activity API)
    let costThisMonth: Decimal?    // nil = not available
    let balance: Decimal?          // nil = not applicable
    let allTimeUsage: Decimal?     // nil = not available (OpenRouter only)
    let claudeUtilization: ClaudeUtilization?
    let updatedAt: Date
    let error: ProviderError?

    static func empty(_ provider: ProviderID) -> ProviderSnapshot {
        ProviderSnapshot(provider: provider, costToday: 0, cost7d: 0, cost30d: 0,
                         costThisMonth: nil, balance: nil, allTimeUsage: nil,
                         claudeUtilization: nil, updatedAt: .distantPast, error: .missingCredentials)
    }
}
