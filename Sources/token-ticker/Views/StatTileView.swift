import SwiftUI

struct StatTileView: View {
    let label: String
    let value: String
    let valueColor: Color

    var body: some View {
        VStack(alignment: .center, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .kerning(0.5)

            Text(value)
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
