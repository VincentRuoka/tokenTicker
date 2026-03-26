# OpenRouter Multi-Metric Cost Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add five configurable cost-metric rows (Total, Last 30d, Last 7d, Current week, Current month) to the OpenRouter expanded view, each togglable via a new Settings section.

**Architecture:** Extend `HistoryStore` with two new query methods and remove the 90-day prune cap. Wire the new queries into `ProviderRowView` behind `@AppStorage` visibility booleans. Add a "OpenRouter Metrics" section to `SettingsView`'s `ProvidersTab` with matching toggles.

**Tech Stack:** Swift 6, SwiftUI, `@Observable`, `@MainActor`, `@AppStorage` (UserDefaults), XCTest

---

## File Map

| File | Change |
|---|---|
| `Sources/token-ticker/Services/HistoryStore.swift` | Remove pruning; add `cost(for:lastDays:)` and `costCurrentWeek(for:)`; update docstring |
| `Sources/token-ticker/Services/OpenRouterService.swift` | Change `start_time` to `"0"` |
| `Sources/token-ticker/Views/ProviderRowView.swift` | Replace 2 rows with 5 `@AppStorage`-gated rows |
| `Sources/token-ticker/Views/SettingsView.swift` | Add `@AppStorage` properties and "OpenRouter Metrics" section to `ProvidersTab` |
| `Tests/token-ticker-tests/HistoryStoreTests.swift` | Delete `testRetentionDropsOldEntries`; add tests for the two new methods |

---

## Task 1: Remove pruning from HistoryStore

**Files:**
- Modify: `Sources/token-ticker/Services/HistoryStore.swift`

Context: `HistoryStore.persist()` currently calls `pruneOldEntries()` after every write, capping stored history at 90 days. We're removing this cap so history grows indefinitely (the JSON file stays tiny).

- [ ] **Step 1: Delete `testRetentionDropsOldEntries` from the test file**

Open `Tests/token-ticker-tests/HistoryStoreTests.swift` and delete the entire `testRetentionDropsOldEntries` function (lines 34–40). This test asserts pruning behaviour that is being removed.

- [ ] **Step 2: Verify tests still compile and pass before touching production code**

```bash
cd /Users/vince/Developer/token-ticker && swift test --filter HistoryStoreTests 2>&1 | tail -20
```

Expected: 2 tests pass (`testPersistAndLoadToday`, `testMonthlyTotalSumsAllDaysThisMonth`).

- [ ] **Step 3: Remove pruning from HistoryStore**

In `Sources/token-ticker/Services/HistoryStore.swift`:

1. In `persist()`, delete the line `pruneOldEntries()` (currently the second line of the function body).
2. Delete the entire `pruneOldEntries()` method (lines 93–99).
3. Update the docstring on `totalStoredCost(for:)` from `/// Sum of all stored daily costs for a provider (up to 30 days of history).` to `/// Sum of all stored daily costs for a provider across all stored history.`

The resulting `persist()` should look like:
```swift
func persist(provider: ProviderID, cost: Decimal) {
    let key = Self.dateKey()
    var day = store.days[key] ?? [:]
    day[provider.rawValue] = ProviderEntry(cost: "\(cost)", updatedAt: Self.isoFormatter.string(from: .now))
    store.days[key] = day
    save()
}
```

- [ ] **Step 4: Build to confirm no compile errors**

```bash
cd /Users/vince/Developer/token-ticker && swift build 2>&1 | tail -20
```

Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
cd /Users/vince/Developer/token-ticker && git add Sources/token-ticker/Services/HistoryStore.swift Tests/token-ticker-tests/HistoryStoreTests.swift && git commit -m "feat: remove HistoryStore 90-day prune cap for unlimited retention"
```

---

## Task 2: Add `cost(for:lastDays:)` to HistoryStore (TDD)

**Files:**
- Modify: `Tests/token-ticker-tests/HistoryStoreTests.swift`
- Modify: `Sources/token-ticker/Services/HistoryStore.swift`

- [ ] **Step 1: Write failing tests**

Add these test methods to `HistoryStoreTests` (inside the `final class HistoryStoreTests` body, after existing tests):

```swift
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
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd /Users/vince/Developer/token-ticker && swift test --filter HistoryStoreTests 2>&1 | tail -20
```

Expected: errors about `cost(for:lastDays:)` not existing.

- [ ] **Step 3: Implement `cost(for:lastDays:)`**

Add this method to `HistoryStore.swift`, after `costThisMonth(for:)`:

```swift
func cost(for provider: ProviderID, lastDays: Int) -> Decimal {
    guard lastDays > 0 else { return 0 }
    let cal = Calendar.current
    let today = cal.startOfDay(for: .now)
    return (0..<lastDays).reduce(into: Decimal(0)) { total, offset in
        guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { return }
        let key = Self.dateKey(for: date)
        if let costStr = store.days[key]?[provider.rawValue]?.cost,
           let cost = Decimal(string: costStr) {
            total += cost
        }
    }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
cd /Users/vince/Developer/token-ticker && swift test --filter HistoryStoreTests 2>&1 | tail -20
```

Expected: all 6 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/vince/Developer/token-ticker && git add Sources/token-ticker/Services/HistoryStore.swift Tests/token-ticker-tests/HistoryStoreTests.swift && git commit -m "feat: add HistoryStore.cost(for:lastDays:) with tests"
```

---

## Task 3: Add `costCurrentWeek(for:)` to HistoryStore (TDD)

**Files:**
- Modify: `Tests/token-ticker-tests/HistoryStoreTests.swift`
- Modify: `Sources/token-ticker/Services/HistoryStore.swift`

- [ ] **Step 1: Write failing tests**

Add these methods after the Task 2 tests:

```swift
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
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd /Users/vince/Developer/token-ticker && swift test --filter HistoryStoreTests 2>&1 | tail -20
```

Expected: errors about `costCurrentWeek(for:)` not existing.

- [ ] **Step 3: Implement `costCurrentWeek(for:)`**

Add this method to `HistoryStore.swift`, after `cost(for:lastDays:)`:

```swift
func costCurrentWeek(for provider: ProviderID) -> Decimal {
    var cal = Calendar.current
    cal.firstWeekday = 2  // Monday; ISO week regardless of system locale
    guard let interval = cal.dateInterval(of: .weekOfYear, for: .now) else { return 0 }
    var total = Decimal(0)
    var date = cal.startOfDay(for: interval.start)
    let end  = cal.startOfDay(for: interval.end)
    while date < end {
        let key = Self.dateKey(for: date)
        if let costStr = store.days[key]?[provider.rawValue]?.cost,
           let cost = Decimal(string: costStr) {
            total += cost
        }
        guard let next = cal.date(byAdding: .day, value: 1, to: date) else { break }
        date = next
    }
    return total
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
cd /Users/vince/Developer/token-ticker && swift test --filter HistoryStoreTests 2>&1 | tail -20
```

Expected: all 8 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/vince/Developer/token-ticker && git add Sources/token-ticker/Services/HistoryStore.swift Tests/token-ticker-tests/HistoryStoreTests.swift && git commit -m "feat: add HistoryStore.costCurrentWeek(for:) with tests"
```

---

## Task 4: Update OpenRouterService start_time

**Files:**
- Modify: `Sources/token-ticker/Services/OpenRouterService.swift`

- [ ] **Step 1: Change the start_time value**

In `Sources/token-ticker/Services/OpenRouterService.swift`, replace the `fetchActivityRaw` method body. Find these lines (around line 48–56):

```swift
private func fetchActivityRaw(key: String) async throws -> Data {
    var comps = URLComponents(string: "https://openrouter.ai/api/v1/activity")!
    // Fetch a wide window — API ignores start_time and returns more than requested,
    // so we filter on the client side using the entry's "date" field.
    let wideStart = Calendar.current.date(byAdding: .day, value: -90, to: .now)!
    comps.queryItems = [
        .init(name: "start_time", value: String(Int(wideStart.timeIntervalSince1970))),
        .init(name: "end_time",   value: String(Int(Date.now.timeIntervalSince1970)))
    ]
    return try await fetchRaw(url: comps.url!, key: key)
}
```

Replace with:

```swift
private func fetchActivityRaw(key: String) async throws -> Data {
    var comps = URLComponents(string: "https://openrouter.ai/api/v1/activity")!
    // start_time=0 requests maximum history; the API currently returns its own
    // fixed window regardless, but this future-proofs the request.
    comps.queryItems = [
        .init(name: "start_time", value: "0"),
        .init(name: "end_time",   value: String(Int(Date.now.timeIntervalSince1970)))
    ]
    return try await fetchRaw(url: comps.url!, key: key)
}
```

- [ ] **Step 2: Build and run all tests**

```bash
cd /Users/vince/Developer/token-ticker && swift test 2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
cd /Users/vince/Developer/token-ticker && git add Sources/token-ticker/Services/OpenRouterService.swift && git commit -m "feat: set OpenRouter start_time to epoch for maximum history window"
```

---

## Task 5: Add metric rows to ProviderRowView

**Files:**
- Modify: `Sources/token-ticker/Views/ProviderRowView.swift`

Context: `openRouterExpanded` currently shows a chart, then "Cost this month" and "Total cost" rows, then "Balance". We replace the two cost rows with five `@AppStorage`-gated rows.

- [ ] **Step 1: Add @AppStorage properties to ProviderRowView**

`ProviderRowView` is a `struct`. Add five `@AppStorage` stored properties at the top of the struct body, before the existing `let snapshot` line:

```swift
@AppStorage("showOR_total") private var showTotal = true
@AppStorage("showOR_30d")   private var show30d   = true
@AppStorage("showOR_7d")    private var show7d    = false
@AppStorage("showOR_week")  private var showWeek  = false
@AppStorage("showOR_month") private var showMonth = false
```

- [ ] **Step 2: Replace the two cost rows in `openRouterExpanded`**

Find this block inside `openRouterExpanded` (around lines 173–184 of the current file):

```swift
// ── Detail rows (balance at bottom) ───────────────────────
if let month = snapshot.costThisMonth {
    detailRow("Cost this month", value: "$\(formatted(month))")
}
let total = HistoryStore.shared.totalStoredCost(for: .openRouter)
if total > 0 {
    detailRow("Total cost", value: "$\(formatted(total))")
}
if let balance = snapshot.balance {
    detailRow("Balance",
              value: "$\(formatted(balance))",
              valueColor: balance < 2 ? .red : .green)
}
```

Replace with:

```swift
// ── Detail rows (balance at bottom) ───────────────────────
if showTotal {
    detailRow("Total", value: "$\(formatted(HistoryStore.shared.totalStoredCost(for: .openRouter)))")
}
if show30d {
    detailRow("Last 30 days", value: "$\(formatted(HistoryStore.shared.cost(for: .openRouter, lastDays: 30)))")
}
if show7d {
    detailRow("Last 7 days", value: "$\(formatted(HistoryStore.shared.cost(for: .openRouter, lastDays: 7)))")
}
if showWeek {
    detailRow("Current week", value: "$\(formatted(HistoryStore.shared.costCurrentWeek(for: .openRouter)))")
}
if showMonth {
    detailRow("Current month", value: "$\(formatted(HistoryStore.shared.costThisMonth(for: .openRouter)))")
}
if let balance = snapshot.balance {
    detailRow("Balance",
              value: "$\(formatted(balance))",
              valueColor: balance < 2 ? .red : .green)
}
```

- [ ] **Step 3: Build to confirm no errors**

```bash
cd /Users/vince/Developer/token-ticker && swift build 2>&1 | tail -20
```

Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
cd /Users/vince/Developer/token-ticker && git add Sources/token-ticker/Views/ProviderRowView.swift && git commit -m "feat: add five configurable cost-metric rows to OpenRouter expanded view"
```

---

## Task 6: Add OpenRouter Metrics section to SettingsView

**Files:**
- Modify: `Sources/token-ticker/Views/SettingsView.swift`

Context: `ProvidersTab` is a private struct inside `SettingsView.swift`. It already has `@AppStorage("provider.openRouter.enabled") private var openRouterEnabled`. We add five new `@AppStorage` properties and a new conditionally-shown `Section`.

- [ ] **Step 1: Add @AppStorage properties to ProvidersTab**

In `Sources/token-ticker/Views/SettingsView.swift`, inside `private struct ProvidersTab`, add five properties after the existing `@AppStorage("provider.ollamaCloud.enabled")` line:

```swift
// OpenRouter metric visibility
@AppStorage("showOR_total") private var showORTotal = true
@AppStorage("showOR_30d")   private var showOR30d   = true
@AppStorage("showOR_7d")    private var showOR7d    = false
@AppStorage("showOR_week")  private var showORWeek  = false
@AppStorage("showOR_month") private var showORMonth = false
```

- [ ] **Step 2: Add the new Section to the Form**

In `ProvidersTab.body`, inside the `Form { ... }`, find the closing `}` of the OpenRouter `Section` block (ends around line 101 with `} header: { Label("OpenRouter", systemImage: "arrow.2.circlepath") }`). Insert the following new section immediately after it:

```swift
if openRouterEnabled {
    Section {
        Toggle("Total (all time)", isOn: $showORTotal)
        Toggle("Last 30 days",     isOn: $showOR30d)
        Toggle("Last 7 days",      isOn: $showOR7d)
        Toggle("Current week",     isOn: $showORWeek)
        Toggle("Current month",    isOn: $showORMonth)
    } header: {
        Label("OpenRouter Metrics", systemImage: "chart.bar")
    }
}
```

- [ ] **Step 3: Build and run all tests**

```bash
cd /Users/vince/Developer/token-ticker && swift test 2>&1 | tail -20
```

Expected: all tests pass, `Build complete!`

- [ ] **Step 4: Commit**

```bash
cd /Users/vince/Developer/token-ticker && git add Sources/token-ticker/Views/SettingsView.swift && git commit -m "feat: add OpenRouter Metrics section to Settings with per-metric toggles"
```

---

## Task 7: Smoke test the full feature

This is a manual verification step.

- [ ] **Step 1: Build and run the app**

```bash
cd /Users/vince/Developer/token-ticker && swift run
```

Or build and launch via Xcode.

- [ ] **Step 2: Verify popover**

Open the popover and expand the OpenRouter row. Confirm:
- "Total" row appears (default on)
- "Last 30 days" row appears (default on)
- "Last 7 days", "Current week", "Current month" rows do NOT appear (default off)
- "Balance" row still appears
- Chart is unchanged

- [ ] **Step 3: Verify Settings**

Open Settings → Providers tab. With OpenRouter enabled, confirm the "OpenRouter Metrics" section appears with 5 toggles. Toggle "Last 7 days" on, close Settings, reopen the popover — the row should now appear.

- [ ] **Step 4: Verify Settings section hides when OpenRouter is disabled**

In Settings, toggle OpenRouter off. Confirm the "OpenRouter Metrics" section disappears.
