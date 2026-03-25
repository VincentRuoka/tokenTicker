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

    private static let tileFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    private func formatted(_ value: Decimal) -> String {
        Self.tileFormatter.string(from: value as NSDecimalNumber) ?? "0.00"
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
