import Foundation

public enum ResponseFormat: String, Sendable, Codable {
    case json
    case xml

    var wireValue: String { rawValue }

    var acceptHeader: String {
        switch self {
        case .json: return "application/json"
        case .xml: return "application/xml"
        }
    }
}
