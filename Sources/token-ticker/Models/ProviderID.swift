import SwiftUI

enum ProviderID: String, CaseIterable, Codable {
    case openRouter  = "OpenRouter"
    case ollamaCloud = "Ollama Cloud"
    case ollamaLocal = "Local Ollama"
    case claude      = "Claude"

    /// UserDefaults key controlling whether this provider is active.
    var enabledDefaultsKey: String {
        switch self {
        case .openRouter:  return "provider.openRouter.enabled"
        case .ollamaCloud: return "provider.ollamaCloud.enabled"
        case .ollamaLocal: return "provider.ollamaLocal.enabled"
        case .claude:      return "provider.claude.enabled"
        }
    }

    /// SF Symbol representing this provider.
    var symbol: String {
        switch self {
        case .openRouter:  return "arrow.2.circlepath"
        case .ollamaCloud: return "icloud"
        case .ollamaLocal: return "desktopcomputer"
        case .claude:      return "sparkles"
        }
    }

    /// Accent color — uses system adaptive colors for perfect dark/light mode.
    var color: Color {
        switch self {
        case .openRouter:  return .blue
        case .ollamaCloud: return .mint
        case .ollamaLocal: return .yellow
        case .claude:      return .orange
        }
    }
}
