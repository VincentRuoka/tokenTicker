import Foundation

struct AlertThreshold: Codable {
    var openRouterBalanceBelowUSD: Double?
    var dailySpendAboveUSD: Double?
    var monthlySpendAboveUSD: Double?
    var claudeUtilizationAbovePct: Double?   // 0.0–1.0, e.g. 0.8 = 80%

    static let `default` = AlertThreshold(
        openRouterBalanceBelowUSD: nil,
        dailySpendAboveUSD: nil,
        monthlySpendAboveUSD: nil,
        claudeUtilizationAbovePct: nil
    )

    static let userDefaultsKey = "tokenTicker.alertThreshold"
}

extension AlertThreshold {
    static func load() -> AlertThreshold {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let threshold = try? JSONDecoder().decode(AlertThreshold.self, from: data)
        else { return .default }
        return threshold
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: AlertThreshold.userDefaultsKey)
    }
}
