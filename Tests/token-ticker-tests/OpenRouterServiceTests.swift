import XCTest
@testable import token_ticker

final class OpenRouterServiceTests: XCTestCase {

    func testParseCreditsResponse() throws {
        let json = """
        {"data":{"total_credits":10.0,"usage":5.5}}
        """.data(using: .utf8)!

        let balance = try OpenRouterService.parseBalance(from: json)
        XCTAssertEqual(balance, Decimal(string: "4.5"))
    }

    func testParseActivityResponse() throws {
        // parseCost expects {"data": [{usage, date}]} and sums entries in the current month
        let today = ISO8601DateFormatter().string(from: .now).prefix(10) // "yyyy-MM-dd"
        let json = """
        {"data":[{"usage":1.23,"date":"\(today) 00:00:00"}]}
        """.data(using: .utf8)!

        let cost = OpenRouterService.parseCost(from: json, granularity: .month)
        XCTAssertEqual(cost, Decimal(string: "1.23"))
    }

    func testMissingKeyReturnsError() async {
        let service = OpenRouterService(apiKey: nil)
        let snapshot = await service.fetchSnapshot()
        XCTAssertNotNil(snapshot.error)
        XCTAssertEqual(snapshot.error, .missingCredentials)
    }
}
