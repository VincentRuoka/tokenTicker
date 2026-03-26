# OpenRouter Multi-Metric Cost Display

**Date:** 2026-03-26
**Status:** Approved

## Summary

Add five configurable cost-metric rows to the OpenRouter expanded view in the popover: Total (all time), Last 30 days, Last 7 days, Current week, and Current month. Each row can be individually shown or hidden via a new "OpenRouter Metrics" section in Settings. Only Total and Last 30 days are visible by default. "Current month" (the API-backed row that previously appeared unconditionally) is hidden by default after this change; users can re-enable it in Settings.

## Architecture

No new files. Changes span three existing layers:

1. **HistoryStore** — data queries + remove pruning
2. **OpenRouterService** — API window
3. **ProviderRowView + SettingsView** — presentation

## Data Layer (HistoryStore)

### Remove pruning
Remove the call to `pruneOldEntries()` from `persist()` and delete the `pruneOldEntries()` method entirely. History accumulates indefinitely. The JSON file is tiny (~70 KB/year) so there is no practical storage concern.

Update the docstring on `totalStoredCost(for:)` — it currently says "up to 30 days of history" which will be stale after pruning is removed.

**Migration note:** Existing installs have had entries older than 90 days pruned on every write, so data before that window is already lost. The "Total (all time)" row will display data only from the earliest surviving entry — this is a known limitation, not a bug. No user-facing messaging is needed.

### New query methods

Both methods use `Calendar.current` (the user's local calendar), consistent with how `HistoryStore` already keys entries by local-date strings.

```swift
/// Sum of all stored daily costs for `provider` over the last `days` calendar dates,
/// inclusive of today's local date. Implemented by generating `days` date-key strings
/// (using dateKey(for:)) ending with today and summing matching entries.
/// Not a rolling time interval — it matches whole calendar days.
/// Example: lastDays=7 on 2026-03-26 covers date keys 2026-03-20 through 2026-03-26.
/// Returns Decimal(0) for lastDays <= 0 or when no matching entries exist.
func cost(for provider: ProviderID, lastDays: Int) -> Decimal

/// Sum of stored daily costs for `provider` for Monday–Sunday of the current week.
/// Implementation:
///   var cal = Calendar.current
///   cal.firstWeekday = 2  // Monday; ISO week regardless of system locale
///   guard let interval = cal.dateInterval(of: .weekOfYear, for: .now) else { return 0 }
///   // then iterate date keys from interval.start through interval.end - 1 day
/// Returns Decimal(0) if the week interval cannot be determined or no entries match.
func costCurrentWeek(for provider: ProviderID) -> Decimal
```

`totalStoredCost(for:)` already exists and serves as the "Total (all time)" source — no changes to its implementation.

## API Layer (OpenRouterService)

In `fetchActivityRaw`, change the `wideStart` calculation from 90 days ago to Unix epoch:

```swift
// Before:
let wideStart = Calendar.current.date(byAdding: .day, value: -90, to: .now)!
comps.queryItems = [
    .init(name: "start_time", value: String(Int(wideStart.timeIntervalSince1970))),
    ...
]

// After:
comps.queryItems = [
    .init(name: "start_time", value: "0"),
    ...
]
```

The OpenRouter API currently ignores `start_time` and returns its own fixed window, so this has no current effect. If the API begins honouring it in future, the response may grow, which is an acceptable trade-off.

## UI Layer

### ProviderRowView

`detailRow` is an existing private helper in `ProviderRowView`:
```swift
func detailRow(_ label: String, value: String, valueColor: Color = .secondary) -> some View
```

All cost values from `HistoryStore` are formatted using the existing `formatted(_: Decimal) -> String` private helper (already used for the Balance row). The `$` prefix is added at the call site, matching the existing Balance row pattern.

SwiftUI view bodies always execute on the main actor. `HistoryStore` is `@MainActor`. Calling `HistoryStore.shared` methods directly from the view body is safe.

Replace the current "Cost this month" and "Total cost" rows in `openRouterExpanded` with five `@AppStorage`-gated `detailRow` calls:

| Row label | Data source | AppStorage key | Default |
|---|---|---|---|
| Total | `HistoryStore.shared.totalStoredCost(for: .openRouter)` | `showOR_total` | `true` |
| Last 30 days | `HistoryStore.shared.cost(for: .openRouter, lastDays: 30)` | `showOR_30d` | `true` |
| Last 7 days | `HistoryStore.shared.cost(for: .openRouter, lastDays: 7)` | `showOR_7d` | `false` |
| Current week | `HistoryStore.shared.costCurrentWeek(for: .openRouter)` | `showOR_week` | `false` |
| Current month | `snapshot.costThisMonth` (API value) | `showOR_month` | `false` |

The `@AppStorage` bool controls rendering only. The "Current month" row wraps the existing `if let month = snapshot.costThisMonth` guard; it renders only when `showOR_month` is true and the value is non-nil.

The cumulative spend chart and the Balance row are unchanged.

### SettingsView (`ProvidersTab`)

The new section goes in `ProvidersTab` (the private struct in `SettingsView.swift`), in the `Form`, as a new `Section("OpenRouter Metrics")` placed immediately after the existing `Section { ... } header: { Label("OpenRouter", ...) }` block.

The section is rendered inside `if openRouterEnabled { }` — the same `@AppStorage("provider.openRouter.enabled")` bool already used in `ProvidersTab` — so it appears and disappears with the provider toggle. No Keychain access is needed.

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

Each `@AppStorage` binding mirrors the keys in the table above.

## Error Handling

No new error surface. All `HistoryStore` queries return `Decimal(0)` when no data matches. `snapshot.costThisMonth` is `Optional<Decimal>` handled by an existing `if let` guard.

## Testing

**`cost(for:lastDays:)` — add to `HistoryStoreTests`**
- `lastDays=7`: entry 6 days ago and 7 days ago are included; entry 8 days ago is not.
- `lastDays=1`: returns only today's cost; yesterday's entry is excluded.
- `lastDays=0` and `lastDays=-1`: return `Decimal(0)`.
- Empty store: returns `Decimal(0)`.

**`costCurrentWeek` — add to `HistoryStoreTests`**
- Entries on Monday and Wednesday of the current week plus the previous Sunday: result equals Monday + Wednesday only.
- Called on a Monday: result equals that Monday's cost only; Sunday's entry is excluded.
- No entries in the current week: returns `Decimal(0)`.

**`testRetentionDropsOldEntries` — delete from `HistoryStoreTests`**
This test verifies pruning behaviour that is being removed. Delete it entirely.

**`OpenRouterServiceTests`**
No changes needed — the existing tests do not assert on `start_time` query parameters.
