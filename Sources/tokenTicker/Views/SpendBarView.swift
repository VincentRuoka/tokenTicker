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
