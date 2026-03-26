import XCTest
@testable import token_ticker

@MainActor
final class HistoryStoreTests: XCTestCase {
    var store: HistoryStore!
    var tempURL: URL!

    override func setUp() {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        store = HistoryStore(fileURL: tempURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
    }

    func testPersistAndLoadToday() async {
        await store.persist(provider: .openRouter, cost: Decimal(string: "1.23")!)
        let loaded = HistoryStore(fileURL: tempURL)
        let cost = await loaded.costToday(for: .openRouter)
        XCTAssertEqual(cost, Decimal(string: "1.23"))
    }

    func testMonthlyTotalSumsAllDaysThisMonth() async {
        await store.persist(provider: .ollamaLocal, cost: Decimal(string: "0.50")!)
        // Simulate a previous day entry
        await store.backfill(date: previousDayInMonth(), provider: .ollamaLocal, cost: Decimal(string: "0.30")!)
        let monthly = await store.costThisMonth(for: .ollamaLocal)
        XCTAssertEqual(monthly, Decimal(string: "0.80"))
    }

    func testRetentionDropsOldEntries() async {
        let oldDate = Calendar.current.date(byAdding: .day, value: -31, to: .now)!
        await store.backfill(date: oldDate, provider: .openRouter, cost: 1)
        await store.persist(provider: .openRouter, cost: 0)  // triggers cleanup
        let keys = await store.allDateKeys()
        XCTAssertFalse(keys.contains(HistoryStore.dateKey(for: oldDate)))
    }

    private func previousDayInMonth() -> Date {
        Calendar.current.date(byAdding: .day, value: -1, to: .now)!
    }
}
