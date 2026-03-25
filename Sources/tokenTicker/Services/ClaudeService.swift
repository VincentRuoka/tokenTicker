// Temporary stub — full implementation in Task 8
final class ClaudeService: ProviderService {
    let providerID: ProviderID = .claude
    static let shared = ClaudeService()
    func fetchSnapshot() async -> ProviderSnapshot { .empty(.claude) }
    func startOAuthFlow() {}
    func exchangeCode(_ code: String) async {}
}
