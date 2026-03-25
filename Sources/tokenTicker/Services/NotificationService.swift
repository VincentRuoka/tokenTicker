import UserNotifications
import Foundation

final class NotificationService {
    static let shared = NotificationService()

    private let defaults: UserDefaults
    private static let firedAlertsKey = "firedAlerts"

    // Designated initializer — injectable defaults for testability
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Public API

    /// Called after each aggregation cycle from AggregatorService.
    @MainActor
    func check(appState: AppState, threshold: AlertThreshold) async {
        pruneFiredKeys()

        // 1. Daily spend
        if let dailyLimit = threshold.dailySpendAboveUSD,
           appState.totalCostToday > Decimal(dailyLimit) {
            let key = dedupKey("dailySpend")
            if shouldFire(key: key) {
                let spent = appState.totalCostToday
                markFired(key: key)
                await fire(
                    key,
                    title: "Daily Spend Alert",
                    body: "Daily spend \(formatUSD(spent)) exceeded \(formatUSD(Decimal(dailyLimit))) threshold"
                )
            }
        }

        // 2. Monthly spend
        if let monthlyLimit = threshold.monthlySpendAboveUSD,
           appState.totalCostThisMonth > Decimal(monthlyLimit) {
            let key = dedupKey("monthlySpend")
            if shouldFire(key: key) {
                let spent = appState.totalCostThisMonth
                markFired(key: key)
                await fire(
                    key,
                    title: "Monthly Spend Alert",
                    body: "Monthly spend \(formatUSD(spent)) exceeded \(formatUSD(Decimal(monthlyLimit)))"
                )
            }
        }

        // 3. OpenRouter balance low
        if let balanceLimit = threshold.openRouterBalanceBelowUSD,
           let balance = appState.openRouterBalance,
           balance < Decimal(balanceLimit) {
            let key = dedupKey("openRouterBalance")
            if shouldFire(key: key) {
                markFired(key: key)
                await fire(
                    key,
                    title: "OpenRouter Balance Low",
                    body: "OpenRouter balance \(formatUSD(balance)) below \(formatUSD(Decimal(balanceLimit)))"
                )
            }
        }

        // 4. Claude utilization
        if let utilizationLimit = threshold.claudeUtilizationAbovePct,
           let claudeSnapshot = appState.snapshots[.claude],
           let utilization = claudeSnapshot.claudeUtilization,
           utilization.fiveHourPct > utilizationLimit {
            let key = dedupKey("claudeUtilization")
            if shouldFire(key: key) {
                let pct = Int(utilization.fiveHourPct * 100)
                markFired(key: key)
                await fire(
                    key,
                    title: "Claude Utilization Alert",
                    body: "Claude 5h usage at \(pct)%"
                )
            }
        }
    }

    /// Request notification authorization — call on first launch.
    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do {
            try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            // Authorization errors are non-fatal; silently ignore
        }
    }

    // MARK: - Internal helpers (exposed for testability)

    /// Returns true if the given dedup key has not been fired today.
    @MainActor
    func shouldFire(key: String) -> Bool {
        let fired = defaults.stringArray(forKey: Self.firedAlertsKey) ?? []
        return !fired.contains(key)
    }

    /// Records that a notification with the given key has been fired.
    @MainActor
    func markFired(key: String) {
        var fired = defaults.stringArray(forKey: Self.firedAlertsKey) ?? []
        if !fired.contains(key) {
            fired.append(key)
            defaults.set(fired, forKey: Self.firedAlertsKey)
        }
    }

    /// Removes dedup keys older than 2 days from UserDefaults.
    @MainActor
    func pruneFiredKeys() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -2, to: .now)!
        let cutoffString = HistoryStore.dateKey(for: cutoff)

        var fired = defaults.stringArray(forKey: Self.firedAlertsKey) ?? []
        fired = fired.filter { entry in
            // Key format: "<alertType>_<yyyy-MM-dd>"
            guard let dateString = entry.split(separator: "_", maxSplits: 1).last.map(String.init) else {
                return false
            }
            // Keep entries whose date is >= cutoff (i.e., not older than 2 days)
            return dateString >= cutoffString
        }
        defaults.set(fired, forKey: Self.firedAlertsKey)
    }

    // MARK: - Private helpers

    private func dedupKey(_ alertType: String) -> String {
        "\(alertType)_\(HistoryStore.dateKey())"
    }

    @MainActor
    private func fire(_ key: String, title: String, body: String) async {
        // Check authorization status; request if not yet determined
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            await requestAuthorization()
        }
        // Re-fetch after possible authorization request
        let freshSettings = await center.notificationSettings()
        guard freshSettings.authorizationStatus == .authorized ||
              freshSettings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: key, content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            // Notification scheduling failure is non-fatal
        }
    }

    private func formatUSD(_ amount: Decimal) -> String {
        let nsDecimal = amount as NSDecimalNumber
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: nsDecimal) ?? "$\(amount)"
    }
}
