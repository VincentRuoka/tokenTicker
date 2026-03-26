import SwiftUI
import Charts

struct ClaudeDetailView: View {
    let utilization: ClaudeUtilization
    let onBack: () -> Void

    @State private var selectedRange: TimeRange = .sixHours

    enum TimeRange: String, CaseIterable {
        case oneHour   = "1h"
        case sixHours  = "6h"
        case oneDay    = "1d"
        case sevenDays = "7d"
        case thirtyDays = "30d"

        var since: Date {
            let cal = Calendar.current
            switch self {
            case .oneHour:    return Date.now.addingTimeInterval(-3600)
            case .sixHours:   return Date.now.addingTimeInterval(-6 * 3600)
            case .oneDay:     return Date.now.addingTimeInterval(-24 * 3600)
            case .sevenDays:  return cal.date(byAdding: .day, value: -7, to: .now)!
            case .thirtyDays: return cal.date(byAdding: .day, value: -30, to: .now)!
            }
        }
    }

    // Live history points for the selected time range
    private var chartPoints: [ClaudeDataPoint] {
        ClaudeUsageHistory.shared.points(since: selectedRange.since)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header ─────────────────────────────────────────────────
            HStack {
                Button {
                    onBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {

                    // Title
                    Text("Claude Usage")
                        .font(.system(size: 16, weight: .bold))
                        .padding(.horizontal, 16)

                    // ── 5-Hour Window ──────────────────────────────────
                    utilizationSection(
                        title: "5-Hour Window",
                        pct: utilization.fiveHourPct,
                        resetsAt: utilization.fiveHourResetsAt,
                        color: barColor(for: utilization.fiveHourPct)
                    )

                    // ── 7-Day Window ───────────────────────────────────
                    utilizationSection(
                        title: "7-Day Window",
                        pct: utilization.sevenDayPct,
                        resetsAt: utilization.sevenDayResetsAt,
                        color: barColor(for: utilization.sevenDayPct)
                    )

                    thinDivider

                    // ── Time range picker ──────────────────────────────
                    Picker("Range", selection: $selectedRange) {
                        ForEach(TimeRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)

                    // ── Chart ──────────────────────────────────────────
                    if chartPoints.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 6) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.system(size: 24, weight: .thin))
                                    .foregroundStyle(.tertiary)
                                Text("No data yet for this range")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                        }
                        .frame(height: 140)
                    } else {
                        Chart {
                            ForEach(chartPoints) { point in
                                LineMark(
                                    x: .value("Time", point.timestamp),
                                    y: .value("5h", point.fiveHourPct * 100)
                                )
                                .foregroundStyle(.blue)
                                .lineStyle(StrokeStyle(lineWidth: 1.5))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(by: .value("Series", "5h"))

                                LineMark(
                                    x: .value("Time", point.timestamp),
                                    y: .value("7d", point.sevenDayPct * 100)
                                )
                                .foregroundStyle(.orange)
                                .lineStyle(StrokeStyle(lineWidth: 1.5))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(by: .value("Series", "7d"))
                            }

                            // Dashed guide lines
                            RuleMark(y: .value("75%", 75))
                                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
                                .foregroundStyle(Color.primary.opacity(0.12))
                            RuleMark(y: .value("50%", 50))
                                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
                                .foregroundStyle(Color.primary.opacity(0.12))
                            RuleMark(y: .value("25%", 25))
                                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
                                .foregroundStyle(Color.primary.opacity(0.12))
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                                    .foregroundStyle(Color.primary.opacity(0.1))
                                AxisValueLabel()
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                                AxisValueLabel {
                                    if let v = value.as(Double.self) {
                                        Text("\(Int(v))%")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                        .chartYScale(domain: 0...100)
                        .chartForegroundStyleScale([
                            "5h": Color.blue,
                            "7d": Color.orange
                        ])
                        .chartLegend(.hidden)
                        .frame(height: 130)
                        .padding(.horizontal, 16)
                    }

                    // ── Legend ─────────────────────────────────────────
                    HStack(spacing: 14) {
                        legendDot(color: .blue,   label: "5h")
                        legendDot(color: .orange, label: "7d")
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }
            }
        }
        .frame(width: 300)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func utilizationSection(title: String, pct: Double, resetsAt: Date, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(Int(pct * 100))%")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.07))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.gradient)
                        .frame(width: geo.size.width * CGFloat(pct))
                }
            }
            .frame(height: 8)

            Text("Resets \(resetLabel(for: resetsAt))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var thinDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal, 16)
    }

    // MARK: - Helpers

    private func barColor(for pct: Double) -> Color {
        pct > 0.8 ? .red : pct > 0.6 ? .orange : .green
    }

    private func resetLabel(for date: Date) -> String {
        let diff = date.timeIntervalSinceNow
        guard diff > 0 else { return "soon" }
        let hours = Int(diff) / 3600
        let mins  = (Int(diff) % 3600) / 60
        let days  = hours / 24
        let remHours = hours % 24
        if days > 0 { return "\(days) day\(days == 1 ? "" : "s"), \(remHours) hr" }
        if hours > 0 { return "\(hours) hr, \(mins) min" }
        return "\(mins) min"
    }
}
