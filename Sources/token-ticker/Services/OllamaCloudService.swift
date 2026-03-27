import Foundation

/// Placeholder — Ollama Cloud API endpoints are not yet publicly documented.
/// Returns a zero snapshot until the API is confirmed.
final class OllamaCloudService: ProviderService {
    let providerID: ProviderID = .ollamaCloud

    func fetchSnapshot() async -> ProviderSnapshot {
        ProviderSnapshot(provider: .ollamaCloud, costToday: 0, cost7d: 0, cost30d: 0,
                         costThisMonth: nil, balance: nil, allTimeUsage: nil,
                         claudeUtilization: nil, updatedAt: .now,
                         error: .missingCredentials)
    }
}
