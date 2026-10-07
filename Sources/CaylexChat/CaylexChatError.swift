import Foundation

public enum CaylexChatError: LocalizedError, Equatable, Sendable {
    case invalidConfiguration(String)
    case notReady
    case missingResources
    case bridge(String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let reason), .bridge(let reason): return reason
        case .notReady: return "The chat widget is not ready"
        case .missingResources: return "The bundled Caylex widget resources could not be found"
        }
    }
}
