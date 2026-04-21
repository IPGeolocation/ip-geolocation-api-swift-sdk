import Foundation

public enum JSONOutputMode: Sendable {
    case compact
    case full
}

public enum JSONOutput {
    public static func toJSON(_ value: Any?, mode: JSONOutputMode = .compact) throws -> String {
        try write(value, mode: mode, pretty: false)
    }

    public static func toPrettyJSON(_ value: Any?, mode: JSONOutputMode = .compact) throws -> String {
        try write(value, mode: mode, pretty: true)
    }

    static func write(_ value: Any?, mode: JSONOutputMode, pretty: Bool) throws -> String {
        let jsonValue = encode(value, mode: mode) ?? NSNull()

        var options: JSONSerialization.WritingOptions = [.fragmentsAllowed, .sortedKeys]
        if pretty {
            options.insert(.prettyPrinted)
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: jsonValue, options: options)
            guard let string = String(data: data, encoding: .utf8) else {
                throw SerializationError("Failed to serialize output as JSON")
            }
            return string
        } catch let error as SerializationError {
            throw error
        } catch {
            throw SerializationError("Failed to serialize output as JSON", underlyingError: error)
        }
    }

    static func encode(_ value: Any?, mode: JSONOutputMode) -> Any? {
        guard let unwrapped = deepUnwrap(value) else {
            return mode == .full ? NSNull() : nil
        }

        if let string = unwrapped as? String {
            return string
        }
        if let bool = unwrapped as? Bool {
            return bool
        }
        if let number = unwrapped as? NSNumber {
            return number
        }

        let mirror = Mirror(reflecting: unwrapped)
        switch mirror.displayStyle {
        case .struct, .class:
            var object: [String: Any] = [:]
            for child in mirror.children {
                guard let label = child.label else { continue }
                let key = wireKeyForLabel(label)
                if let encoded = encode(child.value, mode: mode) {
                    object[key] = encoded
                } else if mode == .full {
                    object[key] = NSNull()
                }
            }
            if object.isEmpty && mode != .full { return nil }
            return object
        case .collection, .set:
            var array: [Any] = []
            for child in mirror.children {
                if let encoded = encode(child.value, mode: mode) {
                    array.append(encoded)
                } else if mode == .full {
                    array.append(NSNull())
                }
            }
            return array
        case .dictionary:
            var dictionary: [String: Any] = [:]
            for child in mirror.children {
                let pairMirror = Mirror(reflecting: child.value)
                var rawKey: Any?
                var rawValue: Any?
                for entry in pairMirror.children {
                    if entry.label == "key" { rawKey = entry.value }
                    if entry.label == "value" { rawValue = entry.value }
                }
                guard let key = rawKey else { continue }
                let keyString = "\(key)"
                if let encoded = encode(rawValue, mode: mode) {
                    dictionary[keyString] = encoded
                } else if mode == .full {
                    dictionary[keyString] = NSNull()
                }
            }
            return dictionary
        case .enum:
            return String(describing: unwrapped)
        default:
            if JSONSerialization.isValidJSONObject([unwrapped]) {
                return unwrapped
            }
            return String(describing: unwrapped)
        }
    }

    static func deepUnwrap(_ value: Any?) -> Any? {
        guard let value else { return nil }
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            if let first = mirror.children.first {
                return deepUnwrap(first.value)
            }
            return nil
        }
        return value
    }

    static func wireKeyForLabel(_ label: String) -> String {
        camelToSnakeCase(label)
    }

    /// Converts a Swift `lowerCamelCase` identifier to `snake_case`.
    /// Consecutive uppercase letters stay joined so acronyms like `isEU`,
    /// `isVPN`, and `currentTZAbbreviation` produce `is_eu`, `is_vpn`,
    /// and `current_tz_abbreviation` instead of `is_e_u`, `is_v_p_n`,
    /// and `current_t_z_abbreviation`.
    ///
    /// A word boundary before an uppercase char is:
    /// - the previous char is lowercase, or
    /// - the previous char is uppercase and the next char is lowercase
    ///   (which means this uppercase char starts a new word after an
    ///    acronym run, for example the `A` in `...TZAbbreviation`).
    static func camelToSnakeCase(_ value: String) -> String {
        let chars = Array(value)
        var result = ""
        result.reserveCapacity(value.count + 4)
        for i in 0..<chars.count {
            let char = chars[i]
            if char.isUppercase && i > 0 {
                let prev = chars[i - 1]
                let nextIsLowercase = i + 1 < chars.count && chars[i + 1].isLowercase
                if prev.isLowercase || (prev.isUppercase && nextIsLowercase) {
                    result.append("_")
                }
            }
            result.append(Character(char.lowercased()))
        }
        return result
    }
}
