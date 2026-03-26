import Foundation

@MainActor
final class AggregatorService {
    private let appState: AppState
    private var timer: Timer?
    private var services: [ProviderService] = []
    private var notificationObservers: [NSObjectProtocol] = []

    init(appState: AppState) {
        self.appState = appState
        rebuildServices()
    }

    deinit {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func start() {
        let rebuildObserver = NotificationCenter.default.addObserver(
            forName: .tokenTickerRebuildServices,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.rebuildServices() }
        }
        let timerObserver = NotificationCenter.default.addObserver(
            forName: .tokenTickerRestartTimer,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stop()
                self?.startTimer()
            }
        }
        let refreshObserver = NotificationCenter.default.addObserver(
            forName: .tokenTickerManualRefresh,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        notificationObservers = [rebuildObserver, timerObserver, refreshObserver]
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
        let ud = UserDefaults.standard
        // Reset disabled providers' snapshots so they disappear from the popover immediately,
        // and build the active services list in one pass.
        services = ProviderID.allCases.compactMap { id -> ProviderService? in
            let explicitlyDisabled = ud.object(forKey: id.enabledDefaultsKey) != nil
                                     && !ud.bool(forKey: id.enabledDefaultsKey)
            if explicitlyDisabled {
                appState.snapshots[id] = .empty(id)
                return nil
            }
            switch id {
            case .openRouter:  return OpenRouterService(apiKey: Keychain.load(for: Keychain.openRouterAPIKey))
            case .ollamaLocal: return OllamaLocalService()
            case .ollamaCloud: return OllamaCloudService()
            case .claude:      return ClaudeService.shared
            }
        }
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
        for (providerID, snapshot) in appState.snapshots where snapshot.error == nil {
            HistoryStore.shared.persist(provider: providerID, cost: snapshot.costToday)
        }
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}

extension Notification.Name {
    static let tokenTickerRebuildServices = Notification.Name("token-tickerRebuildServices")
    static let tokenTickerRestartTimer    = Notification.Name("token-tickerRestartTimer")
    static let tokenTickerManualRefresh   = Notification.Name("token-tickerManualRefresh")
}
