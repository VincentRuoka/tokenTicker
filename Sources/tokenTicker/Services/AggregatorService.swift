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
        // Listen for settings changes that require rebuilding services or restarting the timer.
        // Using NotificationCenter keeps SettingsView fully decoupled from AggregatorService.
        NotificationCenter.default.addObserver(
            forName: .tokenTickerRebuildServices,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rebuildServices()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .tokenTickerRestartTimer,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stop()
                self?.startTimer()
            }
        }
        refresh()
        startTimer()
    }

    private func startTimer() {
        let interval = Double(UserDefaults.standard.integer(forKey: "pollingIntervalSeconds")
                              .nonZero ?? 300)
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
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
            ClaudeService.shared
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
        // Persist successful fetches to history
        for (providerID, snapshot) in appState.snapshots {
            if snapshot.error == nil {
                HistoryStore.shared.persist(provider: providerID, cost: snapshot.costToday)
            }
        }
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}

extension Notification.Name {
    static let tokenTickerRebuildServices = Notification.Name("tokenTickerRebuildServices")
    static let tokenTickerRestartTimer    = Notification.Name("tokenTickerRestartTimer")
}
