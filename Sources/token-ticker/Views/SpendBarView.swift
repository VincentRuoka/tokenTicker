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

    private var activeSegments: [SpendBarSegment] {
        segments.filter { $0.value > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ── Bar track ────────────────────────────────────────────────
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.07))
                        .frame(height: 7)

                    // Filled segments
                    if total > 0 {
                        HStack(spacing: 2) {
                            ForEach(activeSegments) { segment in
                                let fraction = CGFloat(
                                    truncating: (segment.value / total) as NSDecimalNumber
                                )
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(segment.color.gradient)
                                    .frame(width: max(4, geo.size.width * fraction - 2))
                            }
                        }
                        .frame(height: 7)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            .frame(height: 7)

            // ── Legend ────────────────────────────────────────────────────
            if !activeSegments.isEmpty {
                HStack(spacing: 12) {
                    ForEach(activeSegments) { segment in
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(segment.color)
                                .frame(width: 8, height: 8)
                            Text(segment.id.rawValue)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
