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
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 4
        return f
    }()
}
