import Foundation

enum QueryBuilder {
    static func build(_ pairs: [(name: String, value: String?)]) -> String {
        var items: [URLQueryItem] = []
        for pair in pairs {
            guard let raw = pair.value else { continue }
            if raw.isEmpty { continue }
            items.append(URLQueryItem(name: pair.name, value: raw))
        }

        if items.isEmpty { return "" }

        var components = URLComponents()
        components.queryItems = items
        let encoded = components.percentEncodedQuery ?? ""
        if encoded.isEmpty { return "" }
        return "?" + encoded
    }
}
