import Foundation

@MainActor
final class AggregatorService {
    private let appState: AppState
    private var timer: Timer?
    private var services: [ProviderService] = []

    init(appState: AppState) {
        self.appState = appState
        rebuildServices()
    }

    func start() {
        refresh()
        let interval = Double(UserDefaults.standard.integer(forKey: "pollingIntervalSeconds")
                              .nonZero ?? 300)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard !appState.isRefreshing else { return }
        appState.isRefreshing = true
        Task {
            await fetchAll()
            appState.isRefreshing = false
            appState.lastRefreshedAt = .now
        }
    }

    func rebuildServices() {
        services = [
            OpenRouterService(apiKey: Keychain.load(for: Keychain.openRouterAPIKey)),
            OllamaLocalService(),
            OllamaCloudService(),
            ClaudeService()
        ]
    }

    private func fetchAll() async {
        await withTaskGroup(of: ProviderSnapshot.self) { group in
            for service in services {
                group.addTask { await service.fetchSnapshot() }
            }
            for await snapshot in group {
                appState.snapshots[snapshot.provider] = snapshot
            }
        }
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
