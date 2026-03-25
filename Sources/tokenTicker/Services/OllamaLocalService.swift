// Temporary stub — full implementation in Task 9
final class OllamaLocalService: ProviderService {
    let providerID: ProviderID = .ollamaLocal
    func fetchSnapshot() async -> ProviderSnapshot { .empty(.ollamaLocal) }
}
