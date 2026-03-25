import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc func handleGetURL(_ event: NSAppleEventDescriptor,
                             withReplyEvent reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString),
              url.scheme == "tokenticker",
              let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "code" })?.value
        else { return }
        Task { await ClaudeService.shared.exchangeCode(code) }
    }
}

@main
struct tokenTickerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()
    @State private var aggregator: AggregatorService?

    var body: some Scene {
        MenuBarExtra("tokenTicker", systemImage: "circle.dotted") {
            PopoverView()
                .environment(appState)
                .onAppear {
                    if aggregator == nil {
                        let agg = AggregatorService(appState: appState)
                        aggregator = agg
                        agg.start()
                    }
                }
        }
        .menuBarExtraStyle(.window)
    }
}
