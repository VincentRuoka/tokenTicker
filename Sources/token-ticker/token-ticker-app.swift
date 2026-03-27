import SwiftUI
import AppKit

@main
struct TokenTickerApp: App {
    @State private var appState = AppState()
    @State private var aggregator: AggregatorService?
    // "off" | "orBalance" | "claude5h"
    @AppStorage("menubarDisplayMode") private var menubarDisplayMode = "off"

    private static let menubarFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    private var menubarText: String? {
        switch menubarDisplayMode {
        case "orBalance":
            guard let balance = appState.snapshots[.openRouter]?.balance else { return nil }
            let s = Self.menubarFormatter.string(from: balance as NSDecimalNumber) ?? "0.00"
            return "$\(s)"
        case "claude5h":
            guard let pct = appState.snapshots[.claude]?.claudeUtilization?.fiveHourPct else { return nil }
            return "\(Int(pct * 100))%"
        default:
            return nil
        }
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

    /// Custom app icon for the menubar, resized to 18pt.
    /// Loads the bundled PNG directly rather than relying on NSApp.applicationIconImage,
    /// which returns the system document icon when the app bundle isn't fully set up.
    private var menubarNSImage: NSImage? {
        // Bundle.module finds the SPM side-car bundle when running via Xcode / swift run.
        // Bundle.main finds the resource in Contents/Resources/ in the final .app bundle.
        let url = Bundle.module.url(forResource: "token-ticker", withExtension: "png")
               ?? Bundle.main.url(forResource: "token-ticker", withExtension: "png")
        guard let url, let img = NSImage(contentsOf: url) else { return nil }
        let size = NSSize(width: 18, height: 18)
        let result = NSImage(size: size, flipped: false) { rect in
            img.draw(in: rect, from: NSRect(origin: .zero, size: img.size),
                     operation: NSCompositingOperation.copy, fraction: 1.0)
            return true
        }
        result.isTemplate = true
        return result
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
                    syncProxy()
                }
                .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                    syncProxy()
                }
        } label: {
            HStack(alignment: .center, spacing: 4) {
                if let img = menubarNSImage {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 18, height: 18)
                        .offset(y: -1)
                } else {
                    Image(systemName: menubarIconName)
                        .offset(y: -1)
                }
                if let text = menubarText {
                    Text(text)
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .frame(height: 18)
                }
            }
        }
        .menuBarExtraStyle(.window)

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
