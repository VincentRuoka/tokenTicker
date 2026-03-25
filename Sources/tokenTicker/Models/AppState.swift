import Foundation
import Observation

@Observable
final class AppState {
    var snapshots: [ProviderID: ProviderSnapshot] = [:]
    var lastRefreshedAt: Date?
    var isRefreshing: Bool = false

    var totalCostToday: Decimal {
        snapshots.values.reduce(0) { $0 + $1.costToday }
    }

    var totalCostThisMonth: Decimal {
        snapshots.values.compactMap(\.costThisMonth).reduce(0, +)
    }

    var openRouterBalance: Decimal? {
        snapshots[.openRouter]?.balance
    }
}
