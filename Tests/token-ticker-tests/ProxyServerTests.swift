import XCTest
@testable import token_ticker

final class ProxyServerTests: XCTestCase {

    // MARK: - testLogEntryFormat

    func testLogEntryFormat() throws {
        let entry = ProxyServer.ProxyLogEntry(
            model: "llama3",
            promptTokens: 128,
            completionTokens: 256,
            timestamp: "2026-03-24T10:01:01Z"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(entry)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["model"] as? String, "llama3")
        XCTAssertEqual(json["promptTokens"] as? Int, 128)
        XCTAssertEqual(json["completionTokens"] as? Int, 256)
        XCTAssertEqual(json["timestamp"] as? String, "2026-03-24T10:01:01Z")
    }

    // MARK: - testLogRotationRemovesOldEntries

    func testLogRotationRemovesOldEntries() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let logURL = tempDir.appendingPathComponent("test-proxy-\(UUID().uuidString).log")

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let now = Date()
        let fiveDaysAgo = Calendar.current.date(byAdding: .day, value: -5, to: now)!
        let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: now)!

        // Build 3 log entries
        let entries: [(model: String, promptTokens: Int, completionTokens: Int, date: Date)] = [
            ("llama3", 10, 20, tenDaysAgo),   // should be removed (> 7 days)
            ("llama3", 30, 40, fiveDaysAgo),  // should be kept (< 7 days)
            ("llama3", 50, 60, now),           // should be kept (today)
        ]

        var lines: [String] = []
        let encoder = JSONEncoder()
        for e in entries {
            let entry = ProxyServer.ProxyLogEntry(
                model: e.model,
                promptTokens: e.promptTokens,
                completionTokens: e.completionTokens,
                timestamp: formatter.string(from: e.date)
            )
            let data = try encoder.encode(entry)
            lines.append(String(data: data, encoding: .utf8)!)
        }

        let content = lines.joined(separator: "\n") + "\n"
        try content.write(to: logURL, atomically: true, encoding: .utf8)

        // Rotate using cutoff = 7 days ago
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        ProxyServer.rotateLog(url: logURL, cutoffDate: cutoff)

        // Read result
        let result = try String(contentsOf: logURL, encoding: .utf8)
        let remaining = result.components(separatedBy: .newlines).filter { !$0.isEmpty }

        XCTAssertEqual(remaining.count, 2, "Expected 2 entries after rotation (10-day-old entry removed)")

        // Verify the kept entries have the right token counts
        struct RawEntry: Decodable { let promptTokens: Int }
        let decoder = JSONDecoder()
        let promptCounts = try remaining.map {
            try decoder.decode(RawEntry.self, from: $0.data(using: .utf8)!).promptTokens
        }
        XCTAssertTrue(promptCounts.contains(30), "5-days-ago entry should be kept")
        XCTAssertTrue(promptCounts.contains(50), "Today's entry should be kept")
        XCTAssertFalse(promptCounts.contains(10), "10-days-ago entry should be removed")
    }

    // MARK: - testParseOllamaResponse

    func testParseOllamaResponse() throws {
        let json = """
        {"model":"llama3","prompt_eval_count":128,"eval_count":256,"done":true}
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(ProxyServer.OllamaResponse.self, from: data)

        XCTAssertEqual(response.model, "llama3")
        XCTAssertEqual(response.promptEvalCount, 128)
        XCTAssertEqual(response.evalCount, 256)
    }
}
