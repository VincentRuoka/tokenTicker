// Sources/tokenTicker/tokenTickerApp.swift
import SwiftUI

@main
struct tokenTickerApp: App {
    @State private var appState = AppState()
    @State private var aggregator: AggregatorService?

    var body: some Scene {
        MenuBarExtra("tokenTicker", systemImage: "circle.dotted") {
            Text("Loading...")
                .padding()
                .environment(appState)
                .onAppear {
                    if aggregator == nil {
                        let agg = AggregatorService(appState: appState)
                        aggregator = agg
                        agg.start()
                    }
                }
                .onOpenURL { url in
                    handleOAuthRedirect(url: url)
                }
        }
        .menuBarExtraStyle(.window)
    }

    private func handleOAuthRedirect(url: URL) {
        guard url.scheme == "tokenticker",
              let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "code" })?.value
        else { return }
        Task { await ClaudeService.shared.exchangeCode(code) }
    }
}
