import XCTest
@testable import tokenTicker

final class OllamaLocalServiceTests: XCTestCase {

    // MARK: - testParseTokensFromLogLine

    func testParseTokensFromLogLine() {
        // Build log content with two completions:
        //   completion 1: promptTokens=128, completionTokens=256
        //   completion 2: promptTokens=64,  completionTokens=128
        // All timestamps are today so they should all be counted.
        let todayISO = isoStringForToday()
        let content = """
        time=\(todayISO) level=INFO msg="prompt eval count: 128 tokens"
        time=\(todayISO) level=INFO msg="eval count: 256 tokens"
        time=\(todayISO) level=INFO msg="prompt eval count: 64 tokens"
        time=\(todayISO) level=INFO msg="eval count: 128 tokens"
        """

        let since = Calendar.current.startOfDay(for: Date())
        let result = OllamaLocalService.parseTokensFromLog(content: content, since: since)

        XCTAssertEqual(result.promptTokens, 192, "Expected 128+64=192 prompt tokens")
        XCTAssertEqual(result.completionTokens, 384, "Expected 256+128=384 completion tokens")
    }

    // MARK: - testCostCalculation

    func testCostCalculation() {
        // 1000 tokens at $1.00 per 1k should produce cost = $1.00
        let service = OllamaLocalService(tokenPricePerK: 1.0)
        let cost = service.calculateCost(totalTokens: 1000)
        XCTAssertEqual(cost, Decimal(1), "Expected cost of $1.00 for 1000 tokens at $1.00/1k")
    }

    // MARK: - testZeroCostWithDefaultPrice

    func testZeroCostWithDefaultPrice() {
        // Default price = 0.0 → any token count should produce $0.00
        let service = OllamaLocalService(tokenPricePerK: 0.0)
        let cost = service.calculateCost(totalTokens: 999_999)
        XCTAssertEqual(cost, Decimal(0), "Expected $0.00 cost when price per 1k is 0.0")
    }

    // MARK: - Helpers

    /// Returns an ISO8601 string for "now" that the server log parser will accept as today.
    private func isoStringForToday() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
