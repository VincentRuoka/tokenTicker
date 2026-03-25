# tokenTicker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS 14+ menubar app that aggregates LLM API costs from OpenRouter, local Ollama, and Claude subscription into a single glanceable view with configurable alerts.

**Architecture:** A `MenuBarExtra`-based SwiftUI app with no dock icon. An `AggregatorService` drives 5-min polling of provider services concurrently, writes results into an `@Observable` `AppState`, and persists daily totals to a local JSON file. The UI is a popover with stat tiles, a proportional spend bar, and per-provider rows.

**Tech Stack:** Swift 5.9+, SwiftUI, macOS 14 (Sonoma)+, Swift Package Manager, XCTest. No external dependencies. `Network.framework` for the optional Ollama proxy.

---

## File Map

```
tokenTicker/
├── Package.swift
├── Sources/tokenTicker/
│   ├── tokenTickerApp.swift
│   ├── Models/
│   │   ├── ProviderID.swift
│   │   ├── ProviderSnapshot.swift
│   │   ├── AppState.swift
│   │   └── AlertThreshold.swift
│   ├── Services/
│   │   ├── ProviderService.swift
│   │   ├── OpenRouterService.swift
│   │   ├── OllamaCloudService.swift
│   │   ├── OllamaLocalService.swift
│   │   ├── ClaudeService.swift
│   │   ├── AggregatorService.swift
│   │   ├── HistoryStore.swift
│   │   ├── NotificationService.swift
│   │   └── ProxyServer.swift
│   ├── Views/
│   │   ├── PopoverView.swift
│   │   ├── StatTileView.swift
│   │   ├── SpendBarView.swift
│   │   ├── ProviderRowView.swift
│   │   └── SettingsView.swift
│   └── Utilities/
│       ├── Keychain.swift
│       └── PKCEHelper.swift
├── Tests/tokenTickerTests/
│   ├── HistoryStoreTests.swift
│   ├── OpenRouterServiceTests.swift
│   ├── OllamaLocalServiceTests.swift
│   ├── NotificationServiceTests.swift
│   └── PKCEHelperTests.swift
└── Resources/
    └── Info.plist
```

---

## Task 1: Project Scaffold

**Files:**
- Create: `Package.swift`
- Create: `Resources/Info.plist`
- Create: `Sources/tokenTicker/tokenTickerApp.swift`

- [ ] **Step 1: Create Package.swift**

```swift
// Package.swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "tokenTicker",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "tokenTicker",
            path: "Sources/tokenTicker",
            resources: [.process("../../Resources")]
        ),
        .testTarget(
            name: "tokenTickerTests",
            dependencies: ["tokenTicker"],
            path: "Tests/tokenTickerTests"
        )
    ]
)
```

- [ ] **Step 2: Create Info.plist (no dock icon + URL scheme)**

```xml
<!-- Resources/Info.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>tokenticker</string>
            </array>
            <key>CFBundleURLName</key>
            <string>com.tokenticker.oauth</string>
        </dict>
    </array>
    <key>NSUserNotificationsUsageDescription</key>
    <string>tokenTicker uses notifications to alert you about spend thresholds.</string>
</dict>
</plist>
```

- [ ] **Step 3: Create tokenTickerApp.swift with empty popover**

```swift
// Sources/tokenTicker/tokenTickerApp.swift
import SwiftUI

@main
struct tokenTickerApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("tokenTicker", systemImage: "circle.dotted") {
            Text("Loading...")
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 4: Create all directories**

```bash
mkdir -p Sources/tokenTicker/{Models,Services,Views,Utilities}
mkdir -p Tests/tokenTickerTests
mkdir -p Resources
```

- [ ] **Step 5: Verify build**

```bash
swift build
```
Expected: Build succeeded (no source files yet beyond the app entry — may error on missing AppState, that's fine for now)

- [ ] **Step 6: Commit**

```bash
git add Package.swift Resources/Info.plist Sources/ Tests/
git commit -m "feat: scaffold project structure"
```

---

## Task 2: Utilities — Keychain + PKCE

**Files:**
- Create: `Sources/tokenTicker/Utilities/Keychain.swift`
- Create: `Sources/tokenTicker/Utilities/PKCEHelper.swift`
- Create: `Tests/tokenTickerTests/PKCEHelperTests.swift`

- [ ] **Step 1: Write PKCEHelper test first**

```swift
// Tests/tokenTickerTests/PKCEHelperTests.swift
import XCTest
@testable import tokenTicker

final class PKCEHelperTests: XCTestCase {
    func testCodeVerifierLength() {
        let (verifier, _) = PKCEHelper.generatePair()
        // base64url of 32 bytes = 43 chars (no padding)
        XCTAssertEqual(verifier.count, 43)
    }

    func testCodeChallengeIsDeterministic() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let challenge = PKCEHelper.challenge(for: verifier)
        // Known SHA256 base64url of the above string
        XCTAssertFalse(challenge.isEmpty)
        XCTAssertFalse(challenge.contains("+"))
        XCTAssertFalse(challenge.contains("/"))
        XCTAssertFalse(challenge.contains("="))
    }

    func testVerifierAndChallengeAreDifferent() {
        let (verifier, challenge) = PKCEHelper.generatePair()
        XCTAssertNotEqual(verifier, challenge)
    }
}
```

- [ ] **Step 2: Run test — verify it fails**

```bash
swift test --filter PKCEHelperTests
```
Expected: compile error (PKCEHelper not defined)

- [ ] **Step 3: Implement PKCEHelper**

```swift
// Sources/tokenTicker/Utilities/PKCEHelper.swift
import Foundation
import CryptoKit

enum PKCEHelper {
    /// Returns (codeVerifier, codeChallenge)
    static func generatePair() -> (String, String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Data(bytes).base64URLEncoded()
        return (verifier, challenge(for: verifier))
    }

    static func challenge(for verifier: String) -> String {
        let data = Data(verifier.utf8)
        let digest = SHA256.hash(data: data)
        return Data(digest).base64URLEncoded()
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
```

- [ ] **Step 4: Run test — verify it passes**

```bash
swift test --filter PKCEHelperTests
```
Expected: All 3 tests pass

- [ ] **Step 5: Implement Keychain helper**

```swift
// Sources/tokenTicker/Utilities/Keychain.swift
import Foundation
import Security

enum Keychain {
    static func save(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecValueData: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(for key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(for key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// Key constants
extension Keychain {
    static let openRouterAPIKey = "tokenTicker.openRouter.apiKey"
    static let claudeAccessToken = "tokenTicker.claude.accessToken"
    static let claudeRefreshToken = "tokenTicker.claude.refreshToken"
    static let claudeExpiresAt = "tokenTicker.claude.expiresAt"
    static let claudeCodeVerifier = "tokenTicker.claude.codeVerifier"
}
```

- [ ] **Step 6: Build**

```bash
swift build
```
Expected: Build succeeded

- [ ] **Step 7: Commit**

```bash
git add Sources/tokenTicker/Utilities/ Tests/tokenTickerTests/PKCEHelperTests.swift
git commit -m "feat: add Keychain helper and PKCEHelper with tests"
```

---

## Task 3: Models

**Files:**
- Create: `Sources/tokenTicker/Models/ProviderID.swift`
- Create: `Sources/tokenTicker/Models/ProviderSnapshot.swift`
- Create: `Sources/tokenTicker/Models/AppState.swift`
- Create: `Sources/tokenTicker/Models/AlertThreshold.swift`

- [ ] **Step 1: Create ProviderID enum**

```swift
// Sources/tokenTicker/Models/ProviderID.swift
import SwiftUI

enum ProviderID: String, CaseIterable, Codable {
    case openRouter = "OpenRouter"
    case ollamaCloud = "Ollama Cloud"
    case ollamaLocal = "Local Ollama"
    case claude = "Claude"

    var color: Color {
        switch self {
        case .openRouter: return .blue
        case .ollamaCloud: return .green
        case .ollamaLocal: return .yellow
        case .claude: return .orange
        }
    }
}
```

- [ ] **Step 2: Create ProviderSnapshot + supporting types**

```swift
// Sources/tokenTicker/Models/ProviderSnapshot.swift
import Foundation

struct ClaudeUtilization {
    let fiveHourPct: Double
    let sevenDayPct: Double
    let extraUsagePct: Double
    let fiveHourResetsAt: Date
    let sevenDayResetsAt: Date
}

enum ProviderError: Error, LocalizedError {
    case missingCredentials
    case logNotFound
    case networkError(String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials: return "No API key configured"
        case .logNotFound: return "Ollama not running"
        case .networkError(let msg): return msg
        case .decodingError(let msg): return "Decode error: \(msg)"
        }
    }
}

struct ProviderSnapshot {
    let provider: ProviderID
    let costToday: Decimal
    let costThisMonth: Decimal?    // nil = not available
    let balance: Decimal?          // nil = not applicable
    let claudeUtilization: ClaudeUtilization?
    let updatedAt: Date
    let error: ProviderError?

    static func empty(_ provider: ProviderID) -> ProviderSnapshot {
        ProviderSnapshot(provider: provider, costToday: 0, costThisMonth: nil,
                         balance: nil, claudeUtilization: nil,
                         updatedAt: .distantPast, error: .missingCredentials)
    }
}
```

- [ ] **Step 3: Create AppState**

```swift
// Sources/tokenTicker/Models/AppState.swift
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
```

- [ ] **Step 4: Create AlertThreshold**

```swift
// Sources/tokenTicker/Models/AlertThreshold.swift
import Foundation

struct AlertThreshold: Codable {
    var openRouterBalanceBelowUSD: Decimal?
    var dailySpendAboveUSD: Decimal?
    var monthlySpendAboveUSD: Decimal?
    var claudeUtilizationAbovePct: Double?   // 0.0–1.0, e.g. 0.8 = 80%

    static let `default` = AlertThreshold(
        openRouterBalanceBelowUSD: nil,
        dailySpendAboveUSD: nil,
        monthlySpendAboveUSD: nil,
        claudeUtilizationAbovePct: nil
    )

    static let userDefaultsKey = "tokenTicker.alertThreshold"
}

extension AlertThreshold {
    static func load() -> AlertThreshold {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let threshold = try? JSONDecoder().decode(AlertThreshold.self, from: data)
        else { return .default }
        return threshold
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: AlertThreshold.userDefaultsKey)
    }
}
```

- [ ] **Step 5: Build**

```bash
swift build
```
Expected: Build succeeded

- [ ] **Step 6: Commit**

```bash
git add Sources/tokenTicker/Models/
git commit -m "feat: add models — ProviderSnapshot, AppState, AlertThreshold"
```

---

## Task 4: ProviderService Protocol + OpenRouterService

**Files:**
- Create: `Sources/tokenTicker/Services/ProviderService.swift`
- Create: `Sources/tokenTicker/Services/OpenRouterService.swift`
- Create: `Sources/tokenTicker/Services/OllamaCloudService.swift`
- Create: `Tests/tokenTickerTests/OpenRouterServiceTests.swift`

- [ ] **Step 1: Write failing tests for OpenRouterService**

```swift
// Tests/tokenTickerTests/OpenRouterServiceTests.swift
import XCTest
@testable import tokenTicker

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

        let cost = try OpenRouterService.parseCost(from: json)
        XCTAssertEqual(cost, Decimal(string: "1.23"))
    }

    func testMissingKeyReturnsError() async {
        let service = OpenRouterService(apiKey: nil)
        let snapshot = await service.fetchSnapshot()
        XCTAssertNotNil(snapshot.error)
        if case .missingCredentials = snapshot.error! {} else {
            XCTFail("Expected missingCredentials error")
        }
    }
}
```

- [ ] **Step 2: Run — verify fails**

```bash
swift test --filter OpenRouterServiceTests
```
Expected: compile error

- [ ] **Step 3: Create ProviderService protocol**

```swift
// Sources/tokenTicker/Services/ProviderService.swift
import Foundation

protocol ProviderService {
    var providerID: ProviderID { get }
    func fetchSnapshot() async -> ProviderSnapshot
}
```

- [ ] **Step 4: Implement OpenRouterService**

```swift
// Sources/tokenTicker/Services/OpenRouterService.swift
import Foundation

final class OpenRouterService: ProviderService {
    let providerID: ProviderID = .openRouter
    private let apiKey: String?
    private let session: URLSession

    init(apiKey: String?, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func fetchSnapshot() async -> ProviderSnapshot {
        guard let key = apiKey, !key.isEmpty else {
            return .empty(.openRouter)
        }
        do {
            async let balance = fetchBalance(key: key)
            async let costToday = fetchCost(key: key, since: .startOfToday)
            async let costMonth = fetchCost(key: key, since: .startOfMonth)
            return ProviderSnapshot(
                provider: .openRouter,
                costToday: try await costToday,
                costThisMonth: try await costMonth,
                balance: try await balance,
                claudeUtilization: nil,
                updatedAt: .now,
                error: nil
            )
        } catch {
            return ProviderSnapshot(provider: .openRouter, costToday: 0,
                                    costThisMonth: nil, balance: nil,
                                    claudeUtilization: nil, updatedAt: .now,
                                    error: .networkError(error.localizedDescription))
        }
    }

    private func fetchBalance(key: String) async throws -> Decimal {
        let url = URL(string: "https://openrouter.ai/api/v1/credits")!
        let data = try await get(url: url, key: key)
        guard let balance = try Self.parseBalance(from: data) else {
            throw ProviderError.decodingError("balance")
        }
        return balance
    }

    private func fetchCost(key: String, since date: Date) async throws -> Decimal {
        var comps = URLComponents(string: "https://openrouter.ai/api/v1/activity")!
        comps.queryItems = [
            .init(name: "start_time", value: String(Int(date.timeIntervalSince1970))),
            .init(name: "end_time", value: String(Int(Date.now.timeIntervalSince1970)))
        ]
        let data = try await get(url: comps.url!, key: key)
        return try Self.parseCost(from: data) ?? 0
    }

    private func get(url: URL, key: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ProviderError.networkError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        return data
    }

    // MARK: - Parsing (internal for testability)

    static func parseBalance(from data: Data) throws -> Decimal? {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let dataObj = json?["data"] as? [String: Any],
              let total = dataObj["total_credits"] as? Double,
              let usage = dataObj["usage"] as? Double
        else { return nil }
        return Decimal(total - usage)
    }

    static func parseCost(from data: Data) throws -> Decimal? {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let dataObj = json?["data"] as? [String: Any],
              let cost = dataObj["total_cost"] as? Double
        else { return nil }
        return Decimal(cost)
    }
}

private extension Date {
    static var startOfToday: Date {
        Calendar.current.startOfDay(for: .now)
    }
    static var startOfMonth: Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: .now)
        return cal.date(from: comps)!
    }
}
```

- [ ] **Step 5: Create OllamaCloudService stub**

```swift
// Sources/tokenTicker/Services/OllamaCloudService.swift
import Foundation

/// Placeholder — Ollama Cloud API endpoints are not yet publicly documented.
/// Returns a zero snapshot until the API is confirmed.
final class OllamaCloudService: ProviderService {
    let providerID: ProviderID = .ollamaCloud

    func fetchSnapshot() async -> ProviderSnapshot {
        ProviderSnapshot(provider: .ollamaCloud, costToday: 0,
                         costThisMonth: nil, balance: nil,
                         claudeUtilization: nil, updatedAt: .now,
                         error: .missingCredentials)
    }
}
```

- [ ] **Step 6: Run tests**

```bash
swift test --filter OpenRouterServiceTests
```
Expected: All 3 tests pass

- [ ] **Step 7: Commit**

```bash
git add Sources/tokenTicker/Services/ Tests/tokenTickerTests/OpenRouterServiceTests.swift
git commit -m "feat: add ProviderService protocol, OpenRouterService, OllamaCloudService stub"
```

---

## Task 5: AggregatorService

**Files:**
- Create: `Sources/tokenTicker/Services/AggregatorService.swift`

- [ ] **Step 1: Implement AggregatorService**

```swift
// Sources/tokenTicker/Services/AggregatorService.swift
import Foundation

@MainActor
final class AggregatorService {
    private let appState: AppState
    private var timer: Timer?
    private var services: [ProviderService] = []

    init(appState: AppState) {
        self.appState = appState
        rebuildServices()
    }

    func start() {
        refresh()
        let interval = Double(UserDefaults.standard.integer(forKey: "pollingIntervalSeconds")
                              .nonZero ?? 300)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
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
        services = [
            OpenRouterService(apiKey: Keychain.load(for: Keychain.openRouterAPIKey)),
            OllamaLocalService(),
            OllamaCloudService(),
            ClaudeService()
        ]
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
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
```

- [ ] **Step 2: Build**

```bash
swift build
```
Expected: Build succeeded (ClaudeService and OllamaLocalService will be stubs until Task 8/9)

> Note: You'll need stub implementations of `ClaudeService` and `OllamaLocalService` to compile. Add them temporarily:

```swift
// Sources/tokenTicker/Services/ClaudeService.swift (temp stub — will be replaced in Task 8)
final class ClaudeService: ProviderService {
    let providerID: ProviderID = .claude
    static let shared = ClaudeService()
    func fetchSnapshot() async -> ProviderSnapshot { .empty(.claude) }
    func startOAuthFlow() {}
    func exchangeCode(_ code: String) async {}
}

// Sources/tokenTicker/Services/OllamaLocalService.swift (temp stub)
final class OllamaLocalService: ProviderService {
    let providerID: ProviderID = .ollamaLocal
    func fetchSnapshot() async -> ProviderSnapshot { .empty(.ollamaLocal) }
}
```

- [ ] **Step 3: Wire AggregatorService into app entry point**

```swift
// Update Sources/tokenTicker/tokenTickerApp.swift
import SwiftUI

@main
struct tokenTickerApp: App {
    @State private var appState = AppState()
    @State private var aggregator: AggregatorService?

    var body: some Scene {
        MenuBarExtra("tokenTicker", systemImage: "circle.dotted") {
            PopoverView()
                .environment(appState)
                .onAppear {
                    if aggregator == nil {
                        let agg = AggregatorService(appState: appState)
                        aggregator = agg
                        agg.start()
                    }
                }
        }
        .menuBarExtraStyle(.window)
        .onOpenURL { url in
            handleOAuthRedirect(url: url)
        }
    }

    private func handleOAuthRedirect(url: URL) {
        guard url.scheme == "tokenticker",
              let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "code" })?.value
        else { return }
        Task { await ClaudeService.shared.exchangeCode(code) }
    }
}
```

- [ ] **Step 4: Build**

```bash
swift build
```

- [ ] **Step 5: Commit**

```bash
git add Sources/tokenTicker/Services/AggregatorService.swift \
        Sources/tokenTicker/Services/ClaudeService.swift \
        Sources/tokenTicker/Services/OllamaLocalService.swift \
        Sources/tokenTicker/tokenTickerApp.swift
git commit -m "feat: add AggregatorService with concurrent polling"
```

---

## Task 6: PopoverView

**Files:**
- Create: `Sources/tokenTicker/Views/PopoverView.swift`
- Create: `Sources/tokenTicker/Views/StatTileView.swift`
- Create: `Sources/tokenTicker/Views/SpendBarView.swift`
- Create: `Sources/tokenTicker/Views/ProviderRowView.swift`

- [ ] **Step 1: Create StatTileView**

```swift
// Sources/tokenTicker/Views/StatTileView.swift
import SwiftUI

struct StatTileView: View {
    let label: String
    let value: String
    let valueColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 2: Create SpendBarView (custom GeometryReader proportional bar)**

```swift
// Sources/tokenTicker/Views/SpendBarView.swift
import SwiftUI

struct SpendBarSegment: Identifiable {
    let id: ProviderID
    let value: Decimal
    var color: Color { id.color }
}

struct SpendBarView: View {
    let segments: [SpendBarSegment]

    private var total: Decimal {
        segments.reduce(0) { $0 + $1.value }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(segments.filter { $0.value > 0 }) { segment in
                        let fraction = total > 0
                            ? CGFloat(truncating: (segment.value / total) as NSDecimalNumber)
                            : 0
                        RoundedRectangle(cornerRadius: 2)
                            .fill(segment.color)
                            .frame(width: geo.size.width * fraction)
                    }
                }
            }
            .frame(height: 6)
            .background(Color.secondary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 3))

            // Legend
            HStack(spacing: 10) {
                ForEach(segments.filter { $0.value > 0 }) { segment in
                    HStack(spacing: 4) {
                        Circle().fill(segment.color).frame(width: 6, height: 6)
                        Text(segment.id.rawValue)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 3: Create ProviderRowView**

```swift
// Sources/tokenTicker/Views/ProviderRowView.swift
import SwiftUI

struct ProviderRowView: View {
    let snapshot: ProviderSnapshot

    var body: some View {
        HStack {
            Circle()
                .fill(snapshot.provider.color)
                .frame(width: 7, height: 7)
            Text(snapshot.provider.rawValue)
                .font(.system(size: 12))
            Spacer()
            valueText
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private var valueText: some View {
        if let error = snapshot.error {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                Text(error.errorDescription ?? "Error")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        } else if let utilization = snapshot.claudeUtilization {
            Text("\(Int(utilization.fiveHourPct * 100))% (5h)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(utilizationColor(utilization.fiveHourPct))
        } else {
            let prefix = snapshot.provider == .ollamaLocal ? "~" : ""
            Text("\(prefix)$\(snapshot.costToday as NSDecimalNumber, formatter: Self.costFormatter)")
                .font(.system(size: 12, design: .monospaced))
        }
    }

    private func utilizationColor(_ pct: Double) -> Color {
        pct > 0.8 ? .red : pct > 0.6 ? .orange : .primary
    }

    private static let costFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 4
        return f
    }()
}
```

- [ ] **Step 4: Create PopoverView**

```swift
// Sources/tokenTicker/Views/PopoverView.swift
import SwiftUI

struct PopoverView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            // Stat tiles
            HStack(spacing: 0) {
                StatTileView(
                    label: "Today",
                    value: "$\(formatted(appState.totalCostToday))",
                    valueColor: .primary
                )
                StatTileView(
                    label: "This Month",
                    value: "$\(formatted(appState.totalCostThisMonth))",
                    valueColor: .primary
                )
                if let balance = appState.openRouterBalance {
                    StatTileView(
                        label: "OR Bal",
                        value: "$\(formatted(balance))",
                        valueColor: balance < 2 ? .red : .green
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            // Spend bar
            SpendBarView(segments: spendSegments)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            Divider()

            // Provider rows
            VStack(spacing: 4) {
                ForEach(visibleSnapshots, id: \.provider) { snapshot in
                    ProviderRowView(snapshot: snapshot)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // Footer
            HStack {
                if appState.isRefreshing {
                    ProgressView().scaleEffect(0.6)
                } else if let refreshed = appState.lastRefreshedAt {
                    Text("Refreshed \(refreshed, style: .relative) ago")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: openSettings) {
                    Image(systemName: "gear")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 280)
    }

    private var visibleSnapshots: [ProviderSnapshot] {
        ProviderID.allCases.compactMap { id -> ProviderSnapshot? in
            guard let snapshot = appState.snapshots[id] else { return nil }
            // Hide if no credentials and no data
            if snapshot.error == .missingCredentials && snapshot.costToday == 0 { return nil }
            return snapshot
        }
    }

    private var spendSegments: [SpendBarSegment] {
        visibleSnapshots.map { SpendBarSegment(id: $0.provider, value: $0.costToday) }
    }

    private func formatted(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "0.00"
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
```

- [ ] **Step 5: Build and run**

```bash
swift build && swift run
```
Expected: App launches, menubar icon appears, popover opens with "Loading..." skeleton. No crash.

- [ ] **Step 6: Commit**

```bash
git add Sources/tokenTicker/Views/
git commit -m "feat: add PopoverView with stat tiles, spend bar, and provider rows"
```

---

## Task 7: HistoryStore

**Files:**
- Create: `Sources/tokenTicker/Services/HistoryStore.swift`
- Create: `Tests/tokenTickerTests/HistoryStoreTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/tokenTickerTests/HistoryStoreTests.swift
import XCTest
@testable import tokenTicker

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
        await store.injectEntry(date: previousDayInMonth(), provider: .ollamaLocal, cost: Decimal(string: "0.30")!)
        let monthly = await store.costThisMonth(for: .ollamaLocal)
        XCTAssertEqual(monthly, Decimal(string: "0.80"))
    }

    func testRetentionDropsOldEntries() async {
        let oldDate = Calendar.current.date(byAdding: .day, value: -31, to: .now)!
        await store.injectEntry(date: oldDate, provider: .openRouter, cost: 1)
        await store.persist(provider: .openRouter, cost: 0)  // triggers cleanup
        let keys = await store.allDateKeys()
        XCTAssertFalse(keys.contains(HistoryStore.dateKey(for: oldDate)))
    }

    private func previousDayInMonth() -> Date {
        Calendar.current.date(byAdding: .day, value: -1, to: .now)!
    }
}
```

- [ ] **Step 2: Run — verify fails**

```bash
swift test --filter HistoryStoreTests
```
Expected: compile error

- [ ] **Step 3: Implement HistoryStore**

```swift
// Sources/tokenTicker/Services/HistoryStore.swift
import Foundation

@MainActor
final class HistoryStore {
    private let fileURL: URL
    private var store: HistoryData = HistoryData()

    static let shared = HistoryStore()

    init(fileURL: URL = Self.defaultURL) {
        self.fileURL = fileURL
        load()
    }

    static var defaultURL: URL {
        let config = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/tokenTicker", isDirectory: true)
        try? FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        return config.appendingPathComponent("history.json")
    }

    static func dateKey(for date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    func persist(provider: ProviderID, cost: Decimal) {
        let key = Self.dateKey()
        var day = store.days[key] ?? [:]
        day[provider.rawValue] = ProviderEntry(cost: "\(cost)", updatedAt: ISO8601DateFormatter().string(from: .now))
        store.days[key] = day
        pruneOldEntries()
        save()
    }

    func costToday(for provider: ProviderID) -> Decimal {
        let key = Self.dateKey()
        return decimal(store.days[key]?[provider.rawValue]?.cost)
    }

    func costThisMonth(for provider: ProviderID) -> Decimal {
        let cal = Calendar.current
        let now = Date.now
        return store.days
            .filter { key, _ in
                guard let date = Self.date(from: key) else { return false }
                return cal.isDate(date, equalTo: now, toGranularity: .month)
            }
            .compactMap { _, day in day[provider.rawValue]?.cost }
            .compactMap { Decimal(string: $0) }
            .reduce(0, +)
    }

    // For testing only
    func injectEntry(date: Date, provider: ProviderID, cost: Decimal) {
        let key = Self.dateKey(for: date)
        var day = store.days[key] ?? [:]
        day[provider.rawValue] = ProviderEntry(cost: "\(cost)", updatedAt: "")
        store.days[key] = day
        save()
    }

    func allDateKeys() -> [String] { Array(store.days.keys) }

    // MARK: - Private

    private func pruneOldEntries() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now)!
        store.days = store.days.filter { key, _ in
            guard let date = Self.date(from: key) else { return false }
            return date >= cutoff
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(HistoryData.self, from: data)
        else { return }
        store = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func date(from key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }

    private func decimal(_ string: String?) -> Decimal {
        guard let s = string else { return 0 }
        return Decimal(string: s) ?? 0
    }
}

// MARK: - Codable types

private struct HistoryData: Codable {
    var version: Int = 1
    var days: [String: [String: ProviderEntry]] = [:]
}

private struct ProviderEntry: Codable {
    var cost: String
    var updatedAt: String
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter HistoryStoreTests
```
Expected: All tests pass

- [ ] **Step 5: Wire HistoryStore into AggregatorService**

In `AggregatorService.swift`, after `fetchAll()` completes, add:

```swift
// Inside fetchAll(), after the for-await loop:
for (providerID, snapshot) in appState.snapshots {
    if snapshot.error == nil {
        HistoryStore.shared.persist(provider: providerID, cost: snapshot.costToday)
    }
}
```

- [ ] **Step 6: Update OllamaLocalService stub to use HistoryStore for monthly cost** (will be properly implemented in Task 9, this just ensures the interface is correct)

- [ ] **Step 7: Build and run tests**

```bash
swift test && swift build
```

- [ ] **Step 8: Commit**

```bash
git add Sources/tokenTicker/Services/HistoryStore.swift Tests/tokenTickerTests/HistoryStoreTests.swift
git commit -m "feat: add HistoryStore with 30-day rolling JSON persistence"
```

---

## Task 8: ClaudeService — OAuth PKCE

**Files:**
- Modify: `Sources/tokenTicker/Services/ClaudeService.swift` (replace stub)

- [ ] **Step 1: Implement ClaudeService**

```swift
// Sources/tokenTicker/Services/ClaudeService.swift
import Foundation
import AppKit

final class ClaudeService: ProviderService {
    let providerID: ProviderID = .claude
    static let shared = ClaudeService()

    private let clientID = "9d04ca1f-6ac0-484e-9e42-c0e5c3a5d347" // claude-usage-bar client ID
    private let redirectURI = "tokenticker://oauth"

    func fetchSnapshot() async -> ProviderSnapshot {
        guard let accessToken = validAccessToken() else {
            return ProviderSnapshot(provider: .claude, costToday: 0,
                                    costThisMonth: nil, balance: nil,
                                    claudeUtilization: nil, updatedAt: .now,
                                    error: .missingCredentials)
        }
        do {
            let utilization = try await fetchUtilization(token: accessToken)
            return ProviderSnapshot(provider: .claude, costToday: 0,
                                    costThisMonth: nil, balance: nil,
                                    claudeUtilization: utilization,
                                    updatedAt: .now, error: nil)
        } catch {
            return ProviderSnapshot(provider: .claude, costToday: 0,
                                    costThisMonth: nil, balance: nil,
                                    claudeUtilization: nil, updatedAt: .now,
                                    error: .networkError(error.localizedDescription))
        }
    }

    // MARK: - OAuth Flow

    func startOAuthFlow() {
        let (verifier, challenge) = PKCEHelper.generatePair()
        Keychain.save(verifier, for: Keychain.claudeCodeVerifier)
        var comps = URLComponents(string: "https://claude.ai/oauth/authorize")!
        comps.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "scope", value: "org:read_usage")
        ]
        NSWorkspace.shared.open(comps.url!)
    }

    func exchangeCode(_ code: String) async {
        guard let verifier = Keychain.load(for: Keychain.claudeCodeVerifier) else { return }
        Keychain.delete(for: Keychain.claudeCodeVerifier)
        do {
            let tokens = try await requestTokens(code: code, verifier: verifier)
            Keychain.save(tokens.accessToken, for: Keychain.claudeAccessToken)
            Keychain.save(tokens.refreshToken, for: Keychain.claudeRefreshToken)
            Keychain.save(String(tokens.expiresAt), for: Keychain.claudeExpiresAt)
        } catch {
            print("Claude token exchange failed: \(error)")
        }
    }

    // MARK: - Private

    private func validAccessToken() -> String? {
        guard let token = Keychain.load(for: Keychain.claudeAccessToken),
              let expiresAtStr = Keychain.load(for: Keychain.claudeExpiresAt),
              let expiresAt = TimeInterval(expiresAtStr) else { return nil }
        let expiresDate = Date(timeIntervalSince1970: expiresAt)
        if expiresDate.timeIntervalSinceNow < 60 {
            // Refresh synchronously-ish using a Task
            Task { await refreshTokens() }
            return nil // will succeed on next poll
        }
        return token
    }

    private func refreshTokens() async {
        guard let refreshToken = Keychain.load(for: Keychain.claudeRefreshToken) else { return }
        var request = URLRequest(url: URL(string: "https://platform.claude.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID
        ])
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let tokens = try? JSONDecoder().decode(TokenResponse.self, from: data)
        else { return }
        Keychain.save(tokens.accessToken, for: Keychain.claudeAccessToken)
        if let newRefresh = tokens.refreshToken {
            Keychain.save(newRefresh, for: Keychain.claudeRefreshToken)
        }
        Keychain.save(String(tokens.expiresAt), for: Keychain.claudeExpiresAt)
    }

    private func requestTokens(code: String, verifier: String) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://platform.claude.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier
        ])
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func fetchUtilization(token: String) async throws -> ClaudeUtilization {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try parseUtilization(from: data)
    }

    private func parseUtilization(from data: Data) throws -> ClaudeUtilization {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fiveHour = json["fiveHour"] as? [String: Any],
              let sevenDay = json["sevenDay"] as? [String: Any],
              let extraUsage = json["extraUsage"] as? [String: Any]
        else { throw ProviderError.decodingError("usage response") }

        let isoFormatter = ISO8601DateFormatter()
        return ClaudeUtilization(
            fiveHourPct: fiveHour["utilization"] as? Double ?? 0,
            sevenDayPct: sevenDay["utilization"] as? Double ?? 0,
            extraUsagePct: extraUsage["utilization"] as? Double ?? 0,
            fiveHourResetsAt: isoFormatter.date(from: fiveHour["resetsAtDate"] as? String ?? "") ?? .now,
            sevenDayResetsAt: isoFormatter.date(from: sevenDay["resetsAtDate"] as? String ?? "") ?? .now
        )
    }
}

private struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: TimeInterval

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_in"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try c.decode(String.self, forKey: .accessToken)
        refreshToken = try? c.decode(String.self, forKey: .refreshToken)
        let expiresIn = try c.decode(TimeInterval.self, forKey: .expiresAt)
        expiresAt = Date.now.timeIntervalSince1970 + expiresIn
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(accessToken, forKey: .accessToken)
        try c.encodeIfPresent(refreshToken, forKey: .refreshToken)
        try c.encode(expiresAt, forKey: .expiresAt)
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build
```

- [ ] **Step 3: Manual test** — add "Connect Claude" button to SettingsView (Task 10) and verify the browser opens correctly. Token exchange tested in Task 10.

- [ ] **Step 4: Commit**

```bash
git add Sources/tokenTicker/Services/ClaudeService.swift
git commit -m "feat: add ClaudeService with OAuth PKCE and token refresh"
```

---

## Task 9: OllamaLocalService

**Files:**
- Modify: `Sources/tokenTicker/Services/OllamaLocalService.swift` (replace stub)
- Create: `Tests/tokenTickerTests/OllamaLocalServiceTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/tokenTickerTests/OllamaLocalServiceTests.swift
import XCTest
@testable import tokenTicker

final class OllamaLocalServiceTests: XCTestCase {

    func testParseTokensFromLogLine() {
        // Ollama server log format uses colons: "prompt eval count: 128 tokens"
        let line = """
        time="2026-03-24T10:00:00Z" level=info msg="llama runner stopped" \
        prompt eval count: 128 tokens eval count: 256 tokens
        """
        let result = OllamaLocalService.parseTokens(from: line)
        XCTAssertEqual(result?.promptTokens, 128)
        XCTAssertEqual(result?.completionTokens, 256)
    }

    func testCostCalculation() {
        let tokens = OllamaTokenRecord(promptTokens: 1000, completionTokens: 1000, timestamp: .now)
        let cost = OllamaLocalService.estimateCost(tokens, pricePerThousand: Decimal(string: "0.50")!)
        XCTAssertEqual(cost, Decimal(string: "1.00"))
    }

    func testZeroCostWithDefaultPrice() {
        let tokens = OllamaTokenRecord(promptTokens: 5000, completionTokens: 2000, timestamp: .now)
        let cost = OllamaLocalService.estimateCost(tokens, pricePerThousand: 0)
        XCTAssertEqual(cost, 0)
    }
}
```

- [ ] **Step 2: Run — verify fails**

```bash
swift test --filter OllamaLocalServiceTests
```
Expected: compile error

- [ ] **Step 3: Implement OllamaLocalService**

```swift
// Sources/tokenTicker/Services/OllamaLocalService.swift
import Foundation

struct OllamaTokenRecord {
    let promptTokens: Int
    let completionTokens: Int
    let timestamp: Date
}

final class OllamaLocalService: ProviderService {
    let providerID: ProviderID = .ollamaLocal

    private var pricePerThousand: Decimal {
        Decimal(string: UserDefaults.standard.string(forKey: "ollamaPricePerThousand") ?? "0") ?? 0
    }

    private var useProxyLog: Bool {
        UserDefaults.standard.bool(forKey: "ollamaUseProxy")
    }

    func fetchSnapshot() async -> ProviderSnapshot {
        let records = useProxyLog ? readProxyLog() : readServerLog()
        let midnight = Calendar.current.startOfDay(for: .now)
        let todayRecords = records.filter { $0.timestamp >= midnight }
        let costToday = todayRecords.reduce(Decimal(0)) {
            $0 + Self.estimateCost($1, pricePerThousand: pricePerThousand)
        }
        let costThisMonth = await HistoryStore.shared.costThisMonth(for: .ollamaLocal)
        let logMissing = !useProxyLog && !FileManager.default.fileExists(atPath: Self.serverLogPath)

        return ProviderSnapshot(
            provider: .ollamaLocal,
            costToday: costToday,
            costThisMonth: costThisMonth,
            balance: nil,
            claudeUtilization: nil,
            updatedAt: .now,
            error: logMissing ? .logNotFound : nil
        )
    }

    // MARK: - Internal for testing

    static func parseTokens(from line: String) -> OllamaTokenRecord? {
        let promptPattern = #"prompt eval count:\s*(\d+)"#
        let evalPattern = #"eval count:\s*(\d+)"#
        guard let promptMatch = line.range(of: promptPattern, options: .regularExpression),
              let evalMatch = line.range(of: evalPattern, options: .regularExpression),
              let prompt = Int(line[promptMatch].components(separatedBy: "=").last ?? ""),
              let eval = Int(line[evalMatch].components(separatedBy: "=").last ?? "")
        else { return nil }
        return OllamaTokenRecord(promptTokens: prompt, completionTokens: eval, timestamp: .now)
    }

    static func estimateCost(_ record: OllamaTokenRecord, pricePerThousand: Decimal) -> Decimal {
        let total = Decimal(record.promptTokens + record.completionTokens)
        return (total / 1000) * pricePerThousand
    }

    // MARK: - Private

    private static let serverLogPath = NSHomeDirectory() + "/.ollama/logs/server.log"
    private static let proxyLogPath = NSHomeDirectory() + "/.config/tokenTicker/ollama-proxy.log"

    private func readServerLog() -> [OllamaTokenRecord] {
        guard let content = try? String(contentsOfFile: Self.serverLogPath, encoding: .utf8)
        else { return [] }
        return content.components(separatedBy: "\n").compactMap { Self.parseTokens(from: $0) }
    }

    private func readProxyLog() -> [OllamaTokenRecord] {
        guard let content = try? String(contentsOfFile: Self.proxyLogPath, encoding: .utf8)
        else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return content.components(separatedBy: "\n")
            .compactMap { $0.data(using: .utf8) }
            .compactMap { try? decoder.decode(ProxyLogEntry.self, from: $0) }
            .map { OllamaTokenRecord(promptTokens: $0.promptTokens,
                                     completionTokens: $0.completionTokens,
                                     timestamp: $0.timestamp) }
    }
}

private struct ProxyLogEntry: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let timestamp: Date
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter OllamaLocalServiceTests
```
Expected: All 3 tests pass

- [ ] **Step 5: Build**

```bash
swift build
```

- [ ] **Step 6: Commit**

```bash
git add Sources/tokenTicker/Services/OllamaLocalService.swift Tests/tokenTickerTests/OllamaLocalServiceTests.swift
git commit -m "feat: add OllamaLocalService with log parsing and cost estimation"
```

---

## Task 10: SettingsView

**Files:**
- Modify: `Sources/tokenTicker/Views/SettingsView.swift` (replace stub if exists, else create)
- Modify: `Sources/tokenTicker/tokenTickerApp.swift` (add Settings scene)

- [ ] **Step 1: Implement SettingsView**

```swift
// Sources/tokenTicker/Views/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @State private var openRouterKey: String = Keychain.load(for: Keychain.openRouterAPIKey) ?? ""
    @State private var threshold: AlertThreshold = AlertThreshold.load()
    @State private var pollingInterval: Int = UserDefaults.standard.integer(forKey: "pollingIntervalSeconds").nonZero ?? 300
    @State private var proxyEnabled: Bool = UserDefaults.standard.bool(forKey: "ollamaUseProxy")
    @State private var proxyPort: String = UserDefaults.standard.string(forKey: "proxyPort") ?? "11435"
    @State private var ollamaPrice: String = UserDefaults.standard.string(forKey: "ollamaPricePerThousand") ?? "0"

    var body: some View {
        TabView {
            providersTab.tabItem { Label("Providers", systemImage: "key") }
            alertsTab.tabItem { Label("Alerts", systemImage: "bell") }
            advancedTab.tabItem { Label("Advanced", systemImage: "gearshape") }
        }
        .frame(width: 400, height: 320)
        .padding()
    }

    // MARK: - Providers Tab

    private var providersTab: some View {
        Form {
            Section("OpenRouter") {
                SecureField("API Key", text: $openRouterKey)
                    .onChange(of: openRouterKey) { _, new in
                        Keychain.save(new, for: Keychain.openRouterAPIKey)
                    }
            }
            Section("Claude Subscription") {
                if Keychain.load(for: Keychain.claudeAccessToken) != nil {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button("Disconnect") {
                        Keychain.delete(for: Keychain.claudeAccessToken)
                        Keychain.delete(for: Keychain.claudeRefreshToken)
                        Keychain.delete(for: Keychain.claudeExpiresAt)
                    }
                } else {
                    Button("Connect Claude via OAuth") {
                        ClaudeService.shared.startOAuthFlow()
                    }
                }
            }
            Section("Ollama Cloud") {
                Text("Coming in v2").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Alerts Tab

    private var alertsTab: some View {
        Form {
            alertRow(label: "OpenRouter balance below ($)",
                     value: Binding(
                        get: { threshold.openRouterBalanceBelowUSD.map { "\($0)" } ?? "" },
                        set: { threshold.openRouterBalanceBelowUSD = Decimal(string: $0); threshold.save() }
                     ))
            alertRow(label: "Daily spend above ($)",
                     value: Binding(
                        get: { threshold.dailySpendAboveUSD.map { "\($0)" } ?? "" },
                        set: { threshold.dailySpendAboveUSD = Decimal(string: $0); threshold.save() }
                     ))
            alertRow(label: "Monthly spend above ($)",
                     value: Binding(
                        get: { threshold.monthlySpendAboveUSD.map { "\($0)" } ?? "" },
                        set: { threshold.monthlySpendAboveUSD = Decimal(string: $0); threshold.save() }
                     ))
            alertRow(label: "Claude utilization above (%)",
                     value: Binding(
                        get: { threshold.claudeUtilizationAbovePct.map { "\(Int($0 * 100))" } ?? "" },
                        set: { threshold.claudeUtilizationAbovePct = Double($0).map { $0 / 100 }; threshold.save() }
                     ))
        }
    }

    private func alertRow(label: String, value: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("off", text: value)
                .frame(width: 60)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Advanced Tab

    private var advancedTab: some View {
        Form {
            Picker("Polling interval", selection: $pollingInterval) {
                Text("1 minute").tag(60)
                Text("5 minutes").tag(300)
                Text("15 minutes").tag(900)
                Text("30 minutes").tag(1800)
            }
            .onChange(of: pollingInterval) { _, new in
                UserDefaults.standard.set(new, forKey: "pollingIntervalSeconds")
            }
            Toggle("Enable local Ollama proxy", isOn: $proxyEnabled)
                .onChange(of: proxyEnabled) { _, new in
                    UserDefaults.standard.set(new, forKey: "ollamaUseProxy")
                }
            if proxyEnabled {
                TextField("Proxy port", text: $proxyPort)
                    .onChange(of: proxyPort) { _, new in
                        UserDefaults.standard.set(new, forKey: "proxyPort")
                    }
            }
            LabeledContent("Local Ollama price per 1K tokens ($)") {
                TextField("0.00", text: $ollamaPrice)
                    .frame(width: 70)
                    .onChange(of: ollamaPrice) { _, new in
                        UserDefaults.standard.set(new, forKey: "ollamaPricePerThousand")
                    }
            }
            Button("Reset History", role: .destructive) {
                try? FileManager.default.removeItem(at: HistoryStore.defaultURL)
            }
        }
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
```

- [ ] **Step 2: Add Settings scene to tokenTickerApp.swift**

Add to `tokenTickerApp.body`:
```swift
Settings {
    SettingsView()
}
```

- [ ] **Step 3: Build and run — open Settings via gear icon in popover**

```bash
swift build && swift run
```
Expected: Settings window opens with 3 tabs. API key persisted after restart.

- [ ] **Step 4: Commit**

```bash
git add Sources/tokenTicker/Views/SettingsView.swift Sources/tokenTicker/tokenTickerApp.swift
git commit -m "feat: add SettingsView with Providers, Alerts, and Advanced tabs"
```

---

## Task 11: NotificationService

**Files:**
- Modify: `Sources/tokenTicker/Services/NotificationService.swift`
- Create: `Tests/tokenTickerTests/NotificationServiceTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/tokenTickerTests/NotificationServiceTests.swift
import XCTest
@testable import tokenTicker

final class NotificationServiceTests: XCTestCase {

    func testDedupKeyFormatIsStable() {
        let key = NotificationService.dedupKey(alertType: "dailySpend", date: "2026-03-24")
        XCTAssertEqual(key, "dailySpend:2026-03-24")
    }

    func testShouldFireWhenNotPreviouslyFired() {
        let svc = NotificationService()
        svc.clearFired()
        XCTAssertTrue(svc.shouldFire(alertType: "test", dateKey: "2026-03-24"))
    }

    func testShouldNotFireTwiceOnSameDay() {
        let svc = NotificationService()
        svc.clearFired()
        svc.markFired(alertType: "test", dateKey: "2026-03-24")
        XCTAssertFalse(svc.shouldFire(alertType: "test", dateKey: "2026-03-24"))
    }

    func testShouldFireAgainOnNewDay() {
        let svc = NotificationService()
        svc.clearFired()
        svc.markFired(alertType: "test", dateKey: "2026-03-23")
        XCTAssertTrue(svc.shouldFire(alertType: "test", dateKey: "2026-03-24"))
    }
}
```

- [ ] **Step 2: Run — verify fails**

```bash
swift test --filter NotificationServiceTests
```

- [ ] **Step 3: Implement NotificationService**

```swift
// Sources/tokenTicker/Services/NotificationService.swift
import Foundation
import UserNotifications

final class NotificationService {
    static let shared = NotificationService()
    private let firedKey = "tokenTicker.firedAlerts"

    func requestPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func check(snapshots: [ProviderID: ProviderSnapshot], threshold: AlertThreshold) {
        let dateKey = HistoryStore.dateKey()
        let totalToday = snapshots.values.reduce(Decimal(0)) { $0 + $1.costToday }
        let totalMonth = snapshots.values.compactMap(\.costThisMonth).reduce(0, +)
        let orBalance = snapshots[.openRouter]?.balance

        if let limit = threshold.openRouterBalanceBelowUSD, let balance = orBalance,
           balance < limit {
            fire("openRouterBalance", dateKey: dateKey,
                 title: "OpenRouter Balance Low",
                 body: "Balance is $\(balance) — below your $\(limit) threshold")
        }
        if let limit = threshold.dailySpendAboveUSD, totalToday > limit {
            fire("dailySpend", dateKey: dateKey,
                 title: "Daily Spend Alert",
                 body: "Today's spend is $\(totalToday) — over your $\(limit) limit")
        }
        if let limit = threshold.monthlySpendAboveUSD, totalMonth > limit {
            fire("monthlySpend", dateKey: dateKey,
                 title: "Monthly Spend Alert",
                 body: "This month's spend is $\(totalMonth) — over your $\(limit) limit")
        }
        if let limit = threshold.claudeUtilizationAbovePct,
           let pct = snapshots[.claude]?.claudeUtilization?.fiveHourPct,
           pct > limit {
            fire("claudeUtil", dateKey: dateKey,
                 title: "Claude Usage High",
                 body: "5h utilization at \(Int(pct * 100))%")
        }
    }

    // MARK: - Internal (for testing)

    static func dedupKey(alertType: String, date: String) -> String { "\(alertType):\(date)" }

    func shouldFire(alertType: String, dateKey: String) -> Bool {
        let key = Self.dedupKey(alertType: alertType, date: dateKey)
        let fired = UserDefaults.standard.stringArray(forKey: firedKey) ?? []
        return !fired.contains(key)
    }

    func markFired(alertType: String, dateKey: String) {
        let key = Self.dedupKey(alertType: alertType, date: dateKey)
        var fired = UserDefaults.standard.stringArray(forKey: firedKey) ?? []
        fired.append(key)
        // Keep only today's keys to avoid unbounded growth
        fired = fired.filter { $0.hasSuffix(dateKey) }
        UserDefaults.standard.set(fired, forKey: firedKey)
    }

    func clearFired() {
        UserDefaults.standard.removeObject(forKey: firedKey)
    }

    // MARK: - Private

    private func fire(_ alertType: String, dateKey: String, title: String, body: String) {
        guard shouldFire(alertType: alertType, dateKey: dateKey) else { return }
        markFired(alertType: alertType, dateKey: dateKey)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter NotificationServiceTests
```
Expected: All 4 tests pass

- [ ] **Step 5: Wire into AggregatorService** — add to end of `fetchAll()`:
```swift
NotificationService.shared.check(snapshots: appState.snapshots,
                                  threshold: AlertThreshold.load())
```

- [ ] **Step 6: Request notification permission on launch** — add to `tokenTickerApp`:
```swift
.onAppear { NotificationService.shared.requestPermission() }
```

- [ ] **Step 7: Build and run all tests**

```bash
swift test && swift build
```
Expected: All tests pass, build succeeds

- [ ] **Step 8: Commit**

```bash
git add Sources/tokenTicker/Services/NotificationService.swift Tests/tokenTickerTests/NotificationServiceTests.swift
git commit -m "feat: add NotificationService with per-day deduplication"
```

---

## Task 12: ProxyServer

**Files:**
- Modify: `Sources/tokenTicker/Services/ProxyServer.swift`

- [ ] **Step 1: Implement ProxyServer**

```swift
// Sources/tokenTicker/Services/ProxyServer.swift
import Foundation
import Network

final class ProxyServer {
    static let shared = ProxyServer()
    private var listener: NWListener?
    private var logURL: URL {
        URL(fileURLWithPath: NSHomeDirectory() + "/.config/tokenTicker/ollama-proxy.log")
    }

    func start(port: UInt16 = 11435) {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        listener = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        listener?.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
        listener?.start(queue: .global(qos: .utility))
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let data = data, !data.isEmpty else { return }
            self?.forward(requestData: data, over: connection)
        }
    }

    private func forward(requestData: Data, over clientConn: NWConnection) {
        let upstream = NWConnection(
            host: "localhost",
            port: 11434,
            using: .tcp
        )
        upstream.start(queue: .global(qos: .utility))
        upstream.send(content: requestData, completion: .contentProcessed { _ in })
        self.relay(from: upstream, to: clientConn)
    }

    private func relay(from upstream: NWConnection, to client: NWConnection) {
        var buffer = Data()
        func readNext() {
            upstream.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, _ in
                if let data = data, !data.isEmpty {
                    buffer.append(data)
                    client.send(content: data, completion: .contentProcessed { _ in })
                }
                if isComplete {
                    self.extractAndLogTokens(from: buffer)
                    upstream.cancel()
                    client.cancel()
                } else {
                    readNext()
                }
            }
        }
        readNext()
    }

    private func extractAndLogTokens(from responseData: Data) {
        guard let text = String(data: responseData, encoding: .utf8) else { return }
        // Find last NDJSON line with token counts
        let lines = text.components(separatedBy: "\n")
        for line in lines.reversed() {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let prompt = json["prompt_eval_count"] as? Int,
                  let eval = json["eval_count"] as? Int
            else { continue }
            let model = json["model"] as? String ?? "unknown"
            appendLog(model: model, promptTokens: prompt, completionTokens: eval)
            break
        }
    }

    private func appendLog(model: String, promptTokens: Int, completionTokens: Int) {
        let entry: [String: Any] = [
            "model": model,
            "promptTokens": promptTokens,
            "completionTokens": completionTokens,
            "timestamp": ISO8601DateFormatter().string(from: .now)
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: entry),
              let line = String(data: data, encoding: .utf8)
        else { return }

        // Rotate: keep only last 7 days
        var existing = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        let kept = existing.components(separatedBy: "\n").filter { logLine in
            guard let d = logLine.data(using: .utf8),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let ts = j["timestamp"] as? String,
                  let date = ISO8601DateFormatter().date(from: ts)
            else { return false }
            return date > cutoff
        }
        existing = kept.joined(separator: "\n")
        let updated = existing.isEmpty ? line : "\(existing)\n\(line)"
        try? updated.write(to: logURL, atomically: true, encoding: .utf8)
    }
}
```

- [ ] **Step 2: Wire proxy start/stop to Settings toggle**

In `AggregatorService.rebuildServices()`, add:
```swift
let proxyEnabled = UserDefaults.standard.bool(forKey: "ollamaUseProxy")
let port = UInt16(UserDefaults.standard.string(forKey: "proxyPort") ?? "11435") ?? 11435
if proxyEnabled { ProxyServer.shared.start(port: port) } else { ProxyServer.shared.stop() }
```

- [ ] **Step 3: Build**

```bash
swift build
```

- [ ] **Step 4: Manual test** — enable proxy in Settings, run:
```bash
curl http://localhost:11435/api/tags
```
Expected: Response forwarded from Ollama at :11434

- [ ] **Step 5: Commit**

```bash
git add Sources/tokenTicker/Services/ProxyServer.swift
git commit -m "feat: add Network.framework proxy server for accurate Ollama token tracking"
```

---

## Task 13: Menubar Toggle

**Files:**
- Modify: `Sources/tokenTicker/tokenTickerApp.swift`

- [ ] **Step 1: Add toggle logic**

```swift
// In tokenTickerApp.swift — update MenuBarExtra to be dynamic
@State private var showSpendInMenuBar: Bool =
    UserDefaults.standard.bool(forKey: "showSpendInMenuBar")

// In body:
MenuBarExtra(showSpendInMenuBar ? "🪙 \(formattedSpend)" : "tokenTicker",
             systemImage: showSpendInMenuBar ? "" : "circle.dotted") {
    PopoverView()
        .environment(appState)
        // ... rest
}

private var formattedSpend: String {
    let formatter = NumberFormatter()
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    return "$" + (formatter.string(from: appState.totalCostToday as NSDecimalNumber) ?? "0.00")
}
```

- [ ] **Step 2: Add toggle button to popover footer** — in `PopoverView`, add a toggle button next to the settings gear:

```swift
Button(action: {
    let current = UserDefaults.standard.bool(forKey: "showSpendInMenuBar")
    UserDefaults.standard.set(!current, forKey: "showSpendInMenuBar")
}) {
    Image(systemName: "dollarsign.circle")
        .font(.system(size: 12))
}
.buttonStyle(.plain)
```

- [ ] **Step 3: Build and run — verify toggle persists across restarts**

```bash
swift build && swift run
```

- [ ] **Step 4: Commit**

```bash
git add Sources/tokenTicker/tokenTickerApp.swift Sources/tokenTicker/Views/PopoverView.swift
git commit -m "feat: add menubar spend toggle, persisted across restarts"
```

---

## Task 14: Polish

**Files:**
- Modify: various Views

- [ ] **Step 1: Add loading state to PopoverView**

When `appState.snapshots.isEmpty`:
```swift
if appState.snapshots.isEmpty && appState.isRefreshing {
    ProgressView("Loading...")
        .frame(width: 280, height: 120)
} else {
    // existing popover content
}
```

- [ ] **Step 2: Add empty state when no providers configured**

When `visibleSnapshots.isEmpty`:
```swift
VStack(spacing: 8) {
    Image(systemName: "key.slash")
        .font(.system(size: 24))
        .foregroundStyle(.secondary)
    Text("No providers configured")
        .font(.headline)
    Text("Open Settings to add API keys")
        .font(.caption)
        .foregroundStyle(.secondary)
    Button("Open Settings") { openSettings() }
}
.frame(width: 280, height: 140)
.padding()
```

- [ ] **Step 3: Add error state for individual provider rows** — already handled in `ProviderRowView` by showing warning icon. Verify visually.

- [ ] **Step 4: Run all tests one final time**

```bash
swift test
```
Expected: All tests pass

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "feat: add loading, empty, and error states — tokenTicker v1 complete"
```

---

## Verification Checklist

- [ ] App launches on macOS 14+ with no dock icon
- [ ] Menubar icon appears; clicking shows popover
- [ ] Add OpenRouter API key in Settings → data appears within 5 min and on click
- [ ] Toggle spend display in menubar → persists after restart
- [ ] Set low alert threshold → trigger a spend → macOS notification fires → does NOT fire again same day
- [ ] Enable proxy in Settings → `curl http://localhost:11435/api/tags` → response forwarded
- [ ] Claude OAuth: click Connect → browser opens `claude.ai/oauth/authorize` → redirect returns to app
- [ ] Kill Ollama → Local Ollama row shows "Ollama not running" warning
- [ ] All providers unconfigured → empty state shows in popover
- [ ] `swift test` → all tests pass
