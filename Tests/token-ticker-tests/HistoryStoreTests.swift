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
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        await store.persist(provider: .ollamaLocal, cost: Decimal(string: "0.50")!)
        if cal.component(.day, from: today) > 1 {
            // Yesterday is in the same month — safe to add a second entry
            let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
            await store.backfill(date: yesterday, provider: .ollamaLocal, cost: Decimal(string: "0.30")!)
            let monthly = await store.costThisMonth(for: .ollamaLocal)
            XCTAssertEqual(monthly, Decimal(string: "0.80"))
        } else {
            // First of month: yesterday is in the prior month, only today counts
            let monthly = await store.costThisMonth(for: .ollamaLocal)
            XCTAssertEqual(monthly, Decimal(string: "0.50"))
        }
    }

    func testCostLastDaysIncludesWindow() async {
        // lastDays:7 = offsets 0..6 = today through 6 days ago (7 dates inclusive).
        // offset 6 (minus6) is the boundary — included.
        // offset 7 (minus7) is just outside — excluded.
        let cal    = Calendar.current
        let today  = cal.startOfDay(for: .now)
        let minus6 = cal.date(byAdding: .day, value: -6, to: today)!
        let minus7 = cal.date(byAdding: .day, value: -7, to: today)!
        await store.backfill(date: minus6, provider: .openRouter, cost: Decimal(string: "1.00")!)
        await store.backfill(date: minus7, provider: .openRouter, cost: Decimal(string: "9.00")!)
        let result = await store.cost(for: .openRouter, lastDays: 7)
        XCTAssertEqual(result, Decimal(string: "1.00")!)  // minus6 included; minus7 (offset 7) excluded
    }

    func testCostLastDaysIncludesToday() async {
        await store.persist(provider: .openRouter, cost: Decimal(string: "5.00")!)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        await store.backfill(date: yesterday, provider: .openRouter, cost: Decimal(string: "3.00")!)
        let todayOnly = await store.cost(for: .openRouter, lastDays: 1)
        XCTAssertEqual(todayOnly, Decimal(string: "5.00")!)  // yesterday excluded
    }

    func testCostLastDaysZeroOrNegativeReturnsZero() async {
        await store.persist(provider: .openRouter, cost: Decimal(string: "1.00")!)
        let zero     = await store.cost(for: .openRouter, lastDays: 0)
        let negative = await store.cost(for: .openRouter, lastDays: -1)
        XCTAssertEqual(zero,     0)
        XCTAssertEqual(negative, 0)
    }

    func testCostLastDaysEmptyStoreReturnsZero() async {
        let result = await store.cost(for: .openRouter, lastDays: 30)
        XCTAssertEqual(result, 0)
    }

    func testCostCurrentWeekExcludesPreviousSunday() async {
        var cal = Calendar.current
        cal.firstWeekday = 2  // Monday
        guard let interval = cal.dateInterval(of: .weekOfYear, for: .now) else {
            XCTFail("Could not compute week interval")
            return
        }
        let monday    = cal.startOfDay(for: interval.start)
        let wednesday = cal.date(byAdding: .day, value: 2, to: monday)!
        let prevSun   = cal.date(byAdding: .day, value: -1, to: monday)!

        await store.backfill(date: monday,    provider: .openRouter, cost: Decimal(string: "1.00")!)
        await store.backfill(date: wednesday, provider: .openRouter, cost: Decimal(string: "2.00")!)
        await store.backfill(date: prevSun,   provider: .openRouter, cost: Decimal(string: "9.00")!)

        let result = await store.costCurrentWeek(for: .openRouter)
        XCTAssertEqual(result, Decimal(string: "3.00")!)  // monday + wednesday; prevSun excluded
    }

    func testCostCurrentWeekEmptyReturnsZero() async {
        let result = await store.costCurrentWeek(for: .openRouter)
        XCTAssertEqual(result, 0)
    }
}
