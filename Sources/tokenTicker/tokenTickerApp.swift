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
    @AppStorage("showSpendInMenubar") private var showSpendInMenubar = false

    private static let menubarFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    private var menubarSpendText: String {
        let formatted = Self.menubarFormatter.string(for: appState.totalCostToday) ?? "0.00"
        return "$\(formatted)"
    }

    private var menubarIconName: String {
        if appState.isRefreshing { return "arrow.clockwise" }
        let snapshots = Array(appState.snapshots.values)
        let allFailed = !snapshots.isEmpty && snapshots.allSatisfy {
            $0.error != nil && $0.error != .missingCredentials
        }
        if allFailed { return "exclamationmark.circle" }
        return "circle.dotted"
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(appState)
                .onAppear {
                    if aggregator == nil {
                        let agg = AggregatorService(appState: appState)
                        aggregator = agg
                        agg.start()
                    }
                    // Start proxy if enabled
                    syncProxy()
                }
                .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                    syncProxy()
                }
        } label: {
            if showSpendInMenubar {
                Text("🪙 \(menubarSpendText)")
            } else {
                Image(systemName: menubarIconName)
            }
        }
        .menuBarExtraStyle(.window)

        // Standard macOS Settings window — opened via gear button in PopoverView.
        Settings {
            SettingsView()
        }
    }

    @MainActor
    private func syncProxy() {
        let enabled = UserDefaults.standard.bool(forKey: "ollamaProxyEnabled")
        if enabled {
            let stored = UserDefaults.standard.integer(forKey: "ollamaProxyPort")
            let port = UInt16(stored > 0 ? stored : 11435)
            ProxyServer.shared.start(port: port)
        } else {
            ProxyServer.shared.stop()
        }
    }
}
