import XCTest
@testable import token_ticker

@MainActor
final class NotificationServiceTests: XCTestCase {

    var suiteName: String!
    var defaults: UserDefaults!
    var service: NotificationService!

    override func setUp() {
        suiteName = "test_\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        service = NotificationService(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        service = nil
        suiteName = nil
    }

    // MARK: - Test 1: Dedup prevents double fire

    func testDedupPreventsDoubleFire() async {
        let key = "dailySpend_\(HistoryStore.dateKey())"

        // First call: key not present, shouldFire returns true
        XCTAssertTrue(service.shouldFire(key: key))
        service.markFired(key: key)

        // Second call: key already present, shouldFire returns false
        XCTAssertFalse(service.shouldFire(key: key))

        // Only one entry should exist for this key
        let fired = defaults.stringArray(forKey: "firedAlerts") ?? []
        XCTAssertEqual(fired.filter { $0 == key }.count, 1)
    }

    // MARK: - Test 2: No alert when below threshold

    func testNoAlertWhenBelowThreshold() async {
        let appState = AppState()
        // totalCostToday defaults to 0; threshold is $10
        let threshold = AlertThreshold(
            openRouterBalanceBelowUSD: nil,
            dailySpendAboveUSD: 10.0,
            monthlySpendAboveUSD: nil,
            claudeUtilizationAbovePct: nil
        )

        await service.check(appState: appState, threshold: threshold)

        let fired = defaults.stringArray(forKey: "firedAlerts") ?? []
        XCTAssertTrue(fired.isEmpty, "Expected no alerts fired, but found: \(fired)")
    }

    // MARK: - Test 3: Pruning removes old dedup keys

    func testPrunesOldDedupKeys() async {
        // Inject 3 keys with a 3-day-old date (should be pruned)
        let oldDate = Calendar.current.date(byAdding: .day, value: -3, to: .now)!
        let oldDateKey = HistoryStore.dateKey(for: oldDate)
        let oldKey1 = "dailySpend_\(oldDateKey)"
        let oldKey2 = "monthlySpend_\(oldDateKey)"
        let oldKey3 = "openRouterBalance_\(oldDateKey)"

        // Also inject a recent key (yesterday) that should be kept
        let recentDate = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let recentKey = "dailySpend_\(HistoryStore.dateKey(for: recentDate))"

        defaults.set([oldKey1, oldKey2, oldKey3, recentKey], forKey: "firedAlerts")

        // Call prune
        service.pruneFiredKeys()

        let remaining = defaults.stringArray(forKey: "firedAlerts") ?? []
        XCTAssertFalse(remaining.contains(oldKey1), "3-day-old key should be pruned")
        XCTAssertFalse(remaining.contains(oldKey2), "3-day-old key should be pruned")
        XCTAssertFalse(remaining.contains(oldKey3), "3-day-old key should be pruned")
        XCTAssertTrue(remaining.contains(recentKey), "Yesterday's key should be kept")
    }
}
