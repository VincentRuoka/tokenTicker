import SwiftUI

// MARK: - Root SettingsView

struct SettingsView: View {
    var body: some View {
        TabView {
            ProvidersTab()
                .tabItem { Label("Providers", systemImage: "key") }
            AlertsTab()
                .tabItem { Label("Alerts", systemImage: "bell") }
            AdvancedTab()
                .tabItem { Label("Advanced", systemImage: "gearshape") }
        }
        .frame(width: 480, height: 360)
    }
}

// MARK: - Providers Tab

private struct ProvidersTab: View {
    @State private var openRouterKey: String = ""
    @FocusState private var openRouterFieldFocused: Bool
    @State private var claudeConnected: Bool = false

    var body: some View {
        Form {
            Section("OpenRouter") {
                LabeledContent("API Key") {
                    SecureField("sk-or-…", text: $openRouterKey)
                        .focused($openRouterFieldFocused)
                        .onSubmit { saveOpenRouterKey() }
                        .onChange(of: openRouterFieldFocused) { _, focused in
                            if !focused { saveOpenRouterKey() }
                        }
                }
            }

            Section("Ollama Cloud") {
                LabeledContent("Status") {
                    Text("Coming in v2")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Claude") {
                LabeledContent("Status") {
                    if claudeConnected {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Connect Claude") {
                            ClaudeService.shared.startOAuthFlow()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            openRouterKey = Keychain.load(for: Keychain.openRouterAPIKey) ?? ""
            claudeConnected = Keychain.load(for: Keychain.claudeAccessToken) != nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .tokenTickerOAuthComplete)) { _ in
            claudeConnected = Keychain.load(for: Keychain.claudeAccessToken) != nil
        }
    }

    private func saveOpenRouterKey() {
        Keychain.save(openRouterKey, for: Keychain.openRouterAPIKey)
        // Notify AggregatorService to rebuild its provider list with the new key.
        NotificationCenter.default.post(name: .tokenTickerRebuildServices, object: nil)
    }
}

// MARK: - Alerts Tab

private struct AlertsTab: View {
    @State private var threshold: AlertThreshold = .default

    // Enabled toggles (derived from whether the threshold value is non-nil)
    @State private var dailyEnabled: Bool = false
    @State private var monthlyEnabled: Bool = false
    @State private var balanceEnabled: Bool = false
    @State private var claudeEnabled: Bool = false

    // Text-field strings for Double? values
    @State private var dailyText: String = ""
    @State private var monthlyText: String = ""
    @State private var balanceText: String = ""
    @State private var claudeText: String = ""

    @FocusState private var focusedField: String?

    private static let usdFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    private static let pctFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        return f
    }()

    var body: some View {
        Form {
            Section("Spend Alerts") {
                alertRow(
                    label: "Daily spend above ($)",
                    enabled: $dailyEnabled,
                    text: $dailyText,
                    placeholder: "5.00",
                    fieldID: "daily"
                ) { save() }

                alertRow(
                    label: "Monthly spend above ($)",
                    enabled: $monthlyEnabled,
                    text: $monthlyText,
                    placeholder: "50.00",
                    fieldID: "monthly"
                ) { save() }

                alertRow(
                    label: "OpenRouter balance below ($)",
                    enabled: $balanceEnabled,
                    text: $balanceText,
                    placeholder: "10.00",
                    fieldID: "balance"
                ) { save() }
            }

            Section("Claude Alerts") {
                alertRow(
                    label: "Claude utilization above (%)",
                    enabled: $claudeEnabled,
                    text: $claudeText,
                    placeholder: "80",
                    fieldID: "claude"
                ) { save() }
                Text("Enter 0–100. E.g. 80 = 80% utilization.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: focusedField) { _, _ in save() }
        .onAppear { loadThreshold() }
    }

    @ViewBuilder
    private func alertRow(
        label: String,
        enabled: Binding<Bool>,
        text: Binding<String>,
        placeholder: String,
        fieldID: String,
        onChange: @escaping () -> Void
    ) -> some View {
        HStack {
            Toggle(label, isOn: enabled)
                .onChange(of: enabled.wrappedValue) { _, _ in onChange() }
            Spacer()
            TextField(placeholder, text: text)
                .frame(width: 80)
                .multilineTextAlignment(.trailing)
                .disabled(!enabled.wrappedValue)
                .focused($focusedField, equals: fieldID)
                .onSubmit { onChange() }
        }
    }

    private func loadThreshold() {
        threshold = AlertThreshold.load()
        dailyEnabled = threshold.dailySpendAboveUSD != nil
        dailyText = threshold.dailySpendAboveUSD.map { Self.usdFormatter.string(from: NSNumber(value: $0)) ?? "" } ?? ""

        monthlyEnabled = threshold.monthlySpendAboveUSD != nil
        monthlyText = threshold.monthlySpendAboveUSD.map { Self.usdFormatter.string(from: NSNumber(value: $0)) ?? "" } ?? ""

        balanceEnabled = threshold.openRouterBalanceBelowUSD != nil
        balanceText = threshold.openRouterBalanceBelowUSD.map { Self.usdFormatter.string(from: NSNumber(value: $0)) ?? "" } ?? ""

        claudeEnabled = threshold.claudeUtilizationAbovePct != nil
        // claudeUtilizationAbovePct is stored as 0.0–1.0; display as 0–100
        claudeText = threshold.claudeUtilizationAbovePct.map { Self.pctFormatter.string(from: NSNumber(value: $0 * 100)) ?? "" } ?? ""
    }

    private func save() {
        // Daily spend
        if dailyEnabled {
            if let v = doubleFrom(dailyText) {
                threshold.dailySpendAboveUSD = v
            } else {
                dailyEnabled = false
                threshold.dailySpendAboveUSD = nil
            }
        } else {
            threshold.dailySpendAboveUSD = nil
        }

        // Monthly spend
        if monthlyEnabled {
            if let v = doubleFrom(monthlyText) {
                threshold.monthlySpendAboveUSD = v
            } else {
                monthlyEnabled = false
                threshold.monthlySpendAboveUSD = nil
            }
        } else {
            threshold.monthlySpendAboveUSD = nil
        }

        // OpenRouter balance
        if balanceEnabled {
            if let v = doubleFrom(balanceText) {
                threshold.openRouterBalanceBelowUSD = v
            } else {
                balanceEnabled = false
                threshold.openRouterBalanceBelowUSD = nil
            }
        } else {
            threshold.openRouterBalanceBelowUSD = nil
        }

        // Convert percent display (0–100) back to fraction (0.0–1.0)
        if claudeEnabled {
            if let pct = doubleFrom(claudeText) {
                threshold.claudeUtilizationAbovePct = pct / 100.0
            } else {
                claudeEnabled = false
                threshold.claudeUtilizationAbovePct = nil
            }
        } else {
            threshold.claudeUtilizationAbovePct = nil
        }

        threshold.save()
    }

    private func doubleFrom(_ text: String) -> Double? {
        // Accept both locale-formatted and plain numeric strings.
        if let n = Self.usdFormatter.number(from: text) { return n.doubleValue }
        return Double(text)
    }
}

// MARK: - Advanced Tab

private struct AdvancedTab: View {
    @AppStorage("pollingIntervalSeconds") private var pollingInterval: Int = 300
    @AppStorage("ollamaProxyEnabled")     private var proxyEnabled: Bool = false
    @AppStorage("ollamaProxyPort")        private var proxyPort: Int = 11435
    @AppStorage("showSpendInMenubar")     private var showSpendInMenubar: Bool = false

    @State private var showResetConfirm: Bool = false
    @State private var proxyPortText: String = ""

    private let intervalOptions: [(label: String, value: Int)] = [
        ("1 minute",  60),
        ("5 minutes", 300),
        ("15 minutes", 900),
        ("30 minutes", 1800)
    ]

    var body: some View {
        Form {
            Section("Polling") {
                Picker("Refresh interval", selection: $pollingInterval) {
                    ForEach(intervalOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .onChange(of: pollingInterval) { _, _ in
                    // Restart the aggregator timer with the new interval.
                    NotificationCenter.default.post(name: .tokenTickerRestartTimer, object: nil)
                }
            }

            Section("Ollama Proxy") {
                Toggle("Enable proxy mode", isOn: $proxyEnabled)
                if proxyEnabled {
                    Text("Set Ollama endpoint to http://localhost:\(proxyPort)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Proxy port") {
                    TextField("11435", text: $proxyPortText)
                        .frame(width: 70)
                        .multilineTextAlignment(.trailing)
                        .disabled(!proxyEnabled)
                        .onSubmit { saveProxyPort() }
                }
            }

            Section("Display") {
                Toggle("Show spend in menu bar", isOn: $showSpendInMenubar)
            }

            Section("Data") {
                Button("Reset History", role: .destructive) {
                    showResetConfirm = true
                }
                .alert("Reset History?", isPresented: $showResetConfirm) {
                    Button("Reset", role: .destructive) {
                        Task { @MainActor in
                            HistoryStore.shared.deleteAll()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will permanently delete all stored spend history. This action cannot be undone.")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            proxyPortText = "\(proxyPort)"
        }
    }

    private func saveProxyPort() {
        if let value = Int(proxyPortText), value > 0, value < 65536 {
            proxyPort = value
        } else {
            // Reset text to current stored value if input is invalid
            proxyPortText = "\(proxyPort)"
        }
    }
}
