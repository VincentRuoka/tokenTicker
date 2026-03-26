import SwiftUI
import AppKit

struct PopoverView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    @State private var expandedProvider: ProviderID? = nil

    private static let bg = Color(red: 43/255, green: 43/255, blue: 43/255)

    var body: some View {
        if isInitialLoading {
            loadingView
        } else if visibleSnapshots.isEmpty && !appState.isRefreshing {
            emptyStateView
        } else {
            contentView
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView().scaleEffect(0.7)
            Text("Loading…")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(width: 300, height: 110)
        .background(Self.bg.ignoresSafeArea())
    }

    // MARK: - Empty state

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.slash")
                .font(.system(size: 30, weight: .thin))
                .foregroundStyle(.tertiary)
            VStack(spacing: 5) {
                Text("No providers configured")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Enable providers in Settings to start\ntracking your AI costs.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            Button("Open Settings") {
                openSettingsAndFocus()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(width: 300, height: 210)
        .padding()
        .background(Self.bg.ignoresSafeArea())
    }

    // MARK: - Main content

    private var contentView: some View {
        VStack(spacing: 0) {
            statsSection
            thinDivider
            if spendSegments.contains(where: { $0.value > 0 }) {
                barSection
                thinDivider
            }
            providerSection
            thinDivider
            footerSection
        }
        .frame(width: 300)
        .background(Self.bg.ignoresSafeArea())
    }

    // MARK: - Stats

    private var statsSection: some View {
        HStack(alignment: .center, spacing: 0) {
            StatTileView(
                label: "Today",
                value: "$\(formatted(appState.totalCostToday))",
                valueColor: .primary
            )
            verticalSep
            StatTileView(
                label: "Cost this month",
                value: "$\(formatted(appState.totalCostThisMonth))",
                valueColor: .primary
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 15)
        .padding(.bottom, 13)
    }

    private var verticalSep: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(width: 1, height: 28)
            .padding(.horizontal, 14)
    }

    // MARK: - Spend bar

    private var barSection: some View {
        SpendBarView(segments: spendSegments)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
    }

    // MARK: - Provider rows

    private var providerSection: some View {
        VStack(spacing: 0) {
            ForEach(Array(visibleSnapshots.enumerated()), id: \.element.provider) { index, snapshot in
                ProviderRowView(snapshot: snapshot,
                                isExpanded: expandedProvider == snapshot.provider)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expandedProvider = expandedProvider == snapshot.provider
                                ? nil
                                : snapshot.provider
                        }
                    }

                if index < visibleSnapshots.count - 1 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.05))
                        .frame(height: 1)
                        .padding(.horizontal, 16)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: 0) {
            Group {
                if appState.isRefreshing {
                    HStack(spacing: 5) {
                        ProgressView().scaleEffect(0.45).frame(width: 10, height: 10)
                        Text("Refreshing…")
                    }
                } else if let refreshed = appState.lastRefreshedAt {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.quaternary)
                        Text("Updated \(refreshed, style: .relative) ago")
                    }
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)

            Spacer()

            HStack(spacing: 12) {
                Button("Refresh") {
                    NotificationCenter.default.post(name: .tokenTickerManualRefresh, object: nil)
                }
                Button("Settings") {
                    openSettingsAndFocus()
                }
                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Shared

    private var thinDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }

    // MARK: - Helpers

    private func openSettingsAndFocus() {
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }

    private var isInitialLoading: Bool {
        appState.isRefreshing && appState.totalCostToday == 0 && visibleSnapshots.isEmpty
    }

    private var visibleSnapshots: [ProviderSnapshot] {
        ProviderID.allCases.compactMap { id -> ProviderSnapshot? in
            guard let snapshot = appState.snapshots[id] else { return nil }
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
}
