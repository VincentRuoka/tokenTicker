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
        let json = """
        {"data":{"total_cost":1.23}}
        """.data(using: .utf8)!

        let cost = OpenRouterService.parseCost(from: json)
        XCTAssertEqual(cost, Decimal(string: "1.23"))
    }

    func testMissingKeyReturnsError() async {
        let service = OpenRouterService(apiKey: nil)
        let snapshot = await service.fetchSnapshot()
        XCTAssertNotNil(snapshot.error)
        XCTAssertEqual(snapshot.error, .missingCredentials)
    }
}
