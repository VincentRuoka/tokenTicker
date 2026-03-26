import SwiftUI

// MARK: - Root

struct SettingsView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView {
                ProvidersTab()
                    .tabItem { Label("Providers", systemImage: "key") }
                AdvancedTab()
                    .tabItem { Label("Advanced", systemImage: "gearshape") }
            }
            .padding(.bottom, 28)

            // Footer: Buy Me a Coffee + version
            HStack(spacing: 12) {
                Button {
                    NSWorkspace.shared.open(URL(string: "https://buymeacoffee.com/ruoka")!)
                } label: {
                    HStack(spacing: 4) {
                        Text("☕")
                        Text("Buy me a coffee")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Text("v\(appVersion)")
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 11))
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .frame(width: 540, height: 500)
        .background(Color(red: 43/255, green: 43/255, blue: 43/255).ignoresSafeArea())
    }
}

// MARK: - Providers Tab

private struct ProvidersTab: View {

    // All disabled by default — user explicitly opts in
    @AppStorage("provider.openRouter.enabled")  private var openRouterEnabled  = false
    @AppStorage("provider.claude.enabled")      private var claudeEnabled      = false
    @AppStorage("provider.ollamaLocal.enabled") private var ollamaLocalEnabled = false
    @AppStorage("provider.ollamaCloud.enabled") private var ollamaCloudEnabled = false

    // OpenRouter
    @State private var openRouterKey   = ""
    @State private var openRouterSaved = false

    // Claude session cookie
    @State private var claudeCookieInput  = ""
    @State private var claudeHasCookie    = false
    @State private var claudeShowInstructions = false

    var body: some View {
        Form {

            // ── OpenRouter ──────────────────────────────────────────────
            Section {
                providerToggle("Active", isOn: $openRouterEnabled,
                               key: ProviderID.openRouter.enabledDefaultsKey)

                if openRouterEnabled {
                    HStack(spacing: 8) {
                        Text("API")
                            .foregroundStyle(.secondary)
                            .fixedSize()
                        SecureField("", text: $openRouterKey)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                        Button { saveOpenRouterKey() } label: {
                            ZStack {
                                Text("Save")
                                    .opacity(openRouterSaved ? 0 : 1)
                                Image(systemName: "checkmark")
                                    .opacity(openRouterSaved ? 1 : 0)
                            }
                            .frame(minWidth: 36)
                        }
                        .controlSize(.small)
                        .disabled(openRouterKey.isEmpty || openRouterSaved)
                        Button("Clear", role: .destructive) { clearOpenRouterKey() }
                            .controlSize(.small)
                            .disabled(openRouterKey.isEmpty)
                    }
                    Text("Requires a **Management Key** (not a regular API key).\nCreate one at https://openrouter.ai/settings/management-keys .")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } header: {
                Label("OpenRouter", systemImage: "arrow.2.circlepath")
            }

            // ── Claude ──────────────────────────────────────────────────
            Section {
                providerToggle("Active", isOn: $claudeEnabled,
                               key: ProviderID.claude.enabledDefaultsKey)

                if claudeEnabled {
                    if claudeHasCookie {
                        // Connected state
                        LabeledContent("Status") {
                            HStack(spacing: 10) {
                                Label("Cookie saved", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Button("Clear", role: .destructive) { clearClaudeCookie() }
                            }
                        }
                    } else {
                        // Cookie input
                        VStack(alignment: .leading, spacing: 10) {
                            // Instructions toggle
                            Button {
                                claudeShowInstructions.toggle()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: claudeShowInstructions
                                          ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text("How to get your session cookie")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)

                            if claudeShowInstructions {
                                VStack(alignment: .leading, spacing: 4) {
                                    instructionRow("1.", "Go to Settings > Usage on claude.ai")
                                    instructionRow("2.", "Press Cmd+Option+I to open DevTools")
                                    instructionRow("3.", "Go to the Network tab")
                                    instructionRow("4.", "Refresh the page, then click the 'usage' request")
                                    instructionRow("5.", "Find 'Cookie' in the Request Headers")
                                    instructionRow("6.", "Copy the full cookie value")
                                }
                                .padding(10)
                                .background(Color.primary.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }

                            Text("Paste full cookie string:")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)

                            TextEditor(text: $claudeCookieInput)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(height: 72)
                                .scrollContentBackground(.hidden)
                                .background(Color.primary.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                            HStack(spacing: 10) {
                                Button("Save Cookie & Fetch") { saveClaudeCookie() }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .disabled(claudeCookieInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                Button("Clear Cookie") { clearClaudeCookie() }
                                    .controlSize(.small)
                                    .disabled(!claudeHasCookie)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Text("Tracks your Claude Pro / Team quota usage. Requires a claude.ai account.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } header: {
                Label("Claude", systemImage: "sparkles")
            }

            // ── Local Ollama ─────────────────────────────────────────────
            Section {
                providerToggle("Active", isOn: $ollamaLocalEnabled,
                               key: ProviderID.ollamaLocal.enabledDefaultsKey)
                if ollamaLocalEnabled {
                    Text("Auto-detected. Requires Ollama running at localhost:11434.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } header: {
                Label("Local Ollama", systemImage: "desktopcomputer")
            }

            // ── Ollama Cloud ─────────────────────────────────────────────
            Section {
                LabeledContent("Status") {
                    Text("Coming in v2").foregroundStyle(.secondary)
                }
            } header: {
                Label("Ollama Cloud", systemImage: "icloud")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            openRouterKey  = Keychain.load(for: Keychain.openRouterAPIKey) ?? ""
            claudeHasCookie = Keychain.load(for: Keychain.claudeSessionCookie)?.isEmpty == false
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func providerToggle(_ label: String, isOn: Binding<Bool>, key: String) -> some View {
        Toggle(label, isOn: isOn)
            .onChange(of: isOn.wrappedValue) { _, _ in
                NotificationCenter.default.post(name: .tokenTickerRebuildServices, object: nil)
            }
    }

    @ViewBuilder
    private func instructionRow(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(number)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .leading)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
        }
    }

    private func clearOpenRouterKey() {
        Keychain.delete(for: Keychain.openRouterAPIKey)
        openRouterKey = ""
        openRouterSaved = false
        NotificationCenter.default.post(name: .tokenTickerRebuildServices, object: nil)
    }

    private func saveOpenRouterKey() {
        let key = openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        Keychain.save(key, for: Keychain.openRouterAPIKey)
        NotificationCenter.default.post(name: .tokenTickerRebuildServices, object: nil)
        NotificationCenter.default.post(name: .tokenTickerManualRefresh, object: nil)
        withAnimation(.easeInOut(duration: 0.15)) { openRouterSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.15)) { openRouterSaved = false }
        }
    }

    private func saveClaudeCookie() {
        let cookie = claudeCookieInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cookie.isEmpty else { return }
        Keychain.save(cookie, for: Keychain.claudeSessionCookie)
        claudeHasCookie   = true
        claudeCookieInput = ""
        NotificationCenter.default.post(name: .tokenTickerRebuildServices, object: nil)
        NotificationCenter.default.post(name: .tokenTickerManualRefresh, object: nil)
    }

    private func clearClaudeCookie() {
        Keychain.delete(for: Keychain.claudeSessionCookie)
        claudeHasCookie   = false
        claudeCookieInput = ""
        NotificationCenter.default.post(name: .tokenTickerRebuildServices, object: nil)
    }
}

// MARK: - Advanced Tab

private struct AdvancedTab: View {
    @AppStorage("pollingIntervalSeconds") private var pollingInterval: Int  = 300
    @AppStorage("ollamaProxyEnabled")     private var proxyEnabled: Bool    = false
    @AppStorage("ollamaProxyPort")        private var proxyPort: Int        = 11435
    @AppStorage("showSpendInMenubar")     private var showSpendInMenubar: Bool = false

    @State private var showResetConfirm = false
    @State private var proxyPortText    = ""

    private let intervalOptions: [(label: String, value: Int)] = [
        ("1 minute",   60),
        ("5 minutes",  300),
        ("15 minutes", 900),
        ("30 minutes", 1800)
    ]

    var body: some View {
        Form {
            Section {
                Picker("Refresh interval", selection: $pollingInterval) {
                    ForEach(intervalOptions, id: \.value) { opt in
                        Text(opt.label).tag(opt.value)
                    }
                }
                .onChange(of: pollingInterval) { _, _ in
                    NotificationCenter.default.post(name: .tokenTickerRestartTimer, object: nil)
                }
            } header: {
                Label("Polling", systemImage: "clock")
            }

            Section {
                Toggle("Enable proxy mode", isOn: $proxyEnabled)
                if proxyEnabled {
                    Text("Set Ollama endpoint to http://localhost:\(String(proxyPort))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TextField("Port (default: 11435)", text: $proxyPortText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!proxyEnabled)
                    .onSubmit { saveProxyPort() }

                DisclosureGroup("What is proxy mode?") {
                    Text("Token Ticker runs a lightweight local proxy on port \(String(proxyPort)). Point your AI tool's Ollama endpoint to http://localhost:\(String(proxyPort)) — requests are forwarded to port 11434 and token counts are logged for cost tracking.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Label("Ollama Proxy", systemImage: "desktopcomputer")
            }

            Section {
                Toggle("Show spend in menu bar", isOn: $showSpendInMenubar)
            } header: {
                Label("Display", systemImage: "menubar.rectangle")
            }

            Section {
                Button("Reset History", role: .destructive) { showResetConfirm = true }
                    .alert("Reset History?", isPresented: $showResetConfirm) {
                        Button("Reset", role: .destructive) {
                            Task { @MainActor in HistoryStore.shared.deleteAll() }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will permanently delete all stored spend history.")
                    }
            } header: {
                Label("Data", systemImage: "tray")
            }
        }
        .formStyle(.grouped)
        .onAppear { proxyPortText = "\(proxyPort)" }
    }

    private func saveProxyPort() {
        if let value = Int(proxyPortText), value > 0, value < 65536 {
            proxyPort = value
        } else {
            proxyPortText = "\(proxyPort)"
        }
    }
}
