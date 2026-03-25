import SwiftUI

enum ProviderID: String, CaseIterable, Codable {
    case openRouter = "OpenRouter"
    case ollamaCloud = "Ollama Cloud"
    case ollamaLocal = "Local Ollama"
    case claude = "Claude"

    var color: Color {
        switch self {
        case .openRouter: return .blue
        case .ollamaCloud: return .green
        case .ollamaLocal: return .yellow
        case .claude: return .orange
        }
    }
}
