import SwiftUI
import Charts

struct ProviderRowView: View {
    @AppStorage("showOR_total") private var showTotal = true
    @AppStorage("showOR_30d")   private var show30d   = true
    @AppStorage("showOR_7d")    private var show7d    = false
    @AppStorage("showOR_week")  private var showWeek  = false
    @AppStorage("showOR_month") private var showMonth = false
    let snapshot: ProviderSnapshot
    var isExpanded: Bool = false

    // Claude is always shown expanded (its bars are the primary content)
    private var showExpanded: Bool {
        isExpanded || (snapshot.provider == .claude && snapshot.claudeUtilization != nil)
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Collapsed header ──────────────────────────────────────
            HStack(spacing: 9) {
                Image(systemName: snapshot.provider.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(snapshot.provider.color)
                    .frame(width: 16, alignment: .center)
                    .symbolRenderingMode(.hierarchical)

                Text(snapshot.provider.rawValue)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.primary)

                Spacer()

                valueView

                if !(snapshot.provider == .claude && snapshot.claudeUtilization != nil) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.quaternary)
                        .rotationEffect(.degrees(showExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.18), value: showExpanded)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)

            // ── Expanded content ──────────────────────────────────────
            if showExpanded {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.05))
                        .frame(height: 1)
                        .padding(.horizontal, 16)

                    expandedContent
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Collapsed value

    @ViewBuilder
    private var valueView: some View {
        if let error = snapshot.error {
            errorView(error)
        } else if let u = snapshot.claudeUtilization {
            utilizationBadge(u)
        } else {
            costView
        }
    }

    private func errorView(_ error: ProviderError) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
                .foregroundStyle(.orange)
            Text(error.errorDescription ?? "Error")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private func utilizationBadge(_ u: ClaudeUtilization) -> some View {
        // When Claude is always expanded, the bars below are the full story —
        // just show a subtle connected indicator in the header.
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 10))
            .foregroundStyle(.green.opacity(0.7))
    }

    private var costView: some View {
        let prefix = snapshot.provider == .ollamaLocal ? "~" : ""
        return Text("\(prefix)$\(snapshot.costToday as NSDecimalNumber, formatter: Self.costFormatter)")
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(.secondary)
    }

    // MARK: - Expanded content

    @ViewBuilder
    private var expandedContent: some View {
        switch snapshot.provider {
        case .openRouter: openRouterExpanded
        case .claude:     claudeExpanded
        case .ollamaLocal: ollamaLocalExpanded
        case .ollamaCloud: EmptyView()
        }
    }

    private var openRouterExpanded: some View {
        let daysThisMonth = Calendar.current.component(.day, from: .now)
        let cumulative = cumulativeSpend(for: .openRouter, days: daysThisMonth)

        return VStack(alignment: .leading, spacing: 10) {

            // ── Cumulative spend line chart ────────────────────────────
            if cumulative.isEmpty {
                Text("No history yet")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 70)
            } else {
                Chart {
                    ForEach(cumulative, id: \.date) { point in
                        LineMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Spend", point.cost)
                        )
                        .foregroundStyle(ProviderID.openRouter.color)
                        .interpolationMethod(.monotone)

                        AreaMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Spend", point.cost)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [ProviderID.openRouter.color.opacity(0.25), .clear],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.monotone)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                            .foregroundStyle(Color.primary.opacity(0.08))
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                            .foregroundStyle(Color.primary.opacity(0.08))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("$\(v, specifier: v < 0.01 ? "%.3f" : "%.2f")")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .frame(height: 70)
            }

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
        }
    }

    /// Builds cumulative (running total) spend for a provider over the last N days, oldest first.
    private func cumulativeSpend(for provider: ProviderID, days: Int) -> [(date: Date, cost: Double)] {
        let daily = HistoryStore.shared.dailyCosts(for: provider, days: days)
        let cal   = Calendar.current
        let today = cal.startOfDay(for: .now)

        var byDate: [Date: Double] = [:]
        for point in daily { byDate[cal.startOfDay(for: point.date)] = point.cost }

        var result: [(date: Date, cost: Double)] = []
        var running = 0.0
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            running += byDate[date] ?? 0
            if running > 0 || !result.isEmpty {
                result.append((date: date, cost: running))
            }
        }
        return result
    }

    @ViewBuilder
    private var claudeExpanded: some View {
        if let u = snapshot.claudeUtilization {
            VStack(spacing: 10) {
                utilizationRow("5h Window",
                               pct: u.fiveHourPct,
                               resetsAt: u.fiveHourResetsAt)

                utilizationRow("7d Window",
                               pct: u.sevenDayPct,
                               resetsAt: u.sevenDayResetsAt)

                // Extra (extended) usage — only visible on Pro/Teams when non-zero
                if u.hasExtraUsage {
                    thinDividerInline
                    utilizationRow("Extra usage (Sonnet)",
                                   pct: u.extraUsagePct,
                                   resetsAt: u.extraUsageResetsAt,
                                   accent: .purple)
                }
            }
        }
    }

    private var thinDividerInline: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 1)
    }

    private var ollamaLocalExpanded: some View {
        VStack(spacing: 6) {
            detailRow("Endpoint", value: "localhost:11434")
            if let month = snapshot.costThisMonth {
                detailRow("This Month", value: "~$\(formatted(month))")
            }
        }
    }

    // MARK: - Sub-components

    private func detailRow(_ label: String, value: String,
                           valueColor: Color = .secondary) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
            Text(value)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(valueColor)
        }
    }

    private func utilizationRow(_ title: String, pct: Double, resetsAt: Date,
                                accent: Color? = nil) -> some View {
        let color = accent ?? utilizationColor(pct)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(Int(pct * 100))%")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(accent != nil ? color : utilizationColor(pct))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.07))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.85))
                        .frame(width: geo.size.width * CGFloat(min(pct, 1.0)))
                }
            }
            .frame(height: 4)
            Text("Resets \(resetLabel(for: resetsAt))")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
        }
    }

    // MARK: - Helpers

    private func utilizationColor(_ pct: Double) -> Color {
        pct > 0.8 ? .red : pct > 0.6 ? .orange : .green
    }

    private func resetLabel(for date: Date) -> String {
        let diff = date.timeIntervalSinceNow
        guard diff > 0 else { return "soon" }
        let hours = Int(diff) / 3600
        let mins  = (Int(diff) % 3600) / 60
        let days  = hours / 24
        let remHours = hours % 24
        if days > 0 { return "in \(days)d \(remHours)h" }
        if hours > 0 { return "in \(hours)h \(mins)m" }
        return "in \(mins)m"
    }

    private func formatted(_ value: Decimal) -> String {
        Self.costFormatter.string(from: value as NSDecimalNumber) ?? "0.00"
    }

    private static let costFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 4
        return f
    }()
}
