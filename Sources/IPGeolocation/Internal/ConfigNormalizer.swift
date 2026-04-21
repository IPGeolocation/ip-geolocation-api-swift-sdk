import Foundation

enum ConfigNormalizer {
    static func normalizeAPIKey(_ value: String?) throws -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw ValidationError("apiKey must not be blank")
        }
        return trimmed
    }

    static func normalizeRequestOrigin(_ value: String?) throws -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw ValidationError("requestOrigin must not be blank")
        }
        if trimmed.containsCROrLF {
            throw ValidationError("requestOrigin must not contain CR or LF")
        }

        guard let components = URLComponents(string: trimmed) else {
            throw ValidationError("requestOrigin must be an absolute http or https origin")
        }

        guard let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw ValidationError("requestOrigin must be an absolute http or https origin")
        }

        if components.user != nil || components.password != nil {
            throw ValidationError("requestOrigin must not include userinfo")
        }

        if components.query != nil || components.fragment != nil {
            throw ValidationError("requestOrigin must not include query or fragment")
        }

        guard let host = components.host, !host.isEmpty else {
            throw ValidationError("requestOrigin must include a valid host")
        }

        let path = components.path
        if !path.isEmpty && path != "/" {
            throw ValidationError("requestOrigin must not include a path")
        }

        // Some Foundation versions strip the enclosing brackets from IPv6
        // literals in `URLComponents.host`; others keep them. Normalize to a
        // bracketless form first, then wrap when the result looks like IPv6.
        // Without this, the reconstructed origin could be either the
        // ambiguous `https://2001:db8::1:8443` (missing brackets) or the
        // invalid `https://[[2001:db8::1]]:8443` (double wrap).
        let bareHost: String = {
            if host.hasPrefix("[") && host.hasSuffix("]") {
                return String(host.dropFirst().dropLast())
            }
            return host
        }()
        let hostPart = bareHost.contains(":") ? "[\(bareHost)]" : bareHost

        if let port = components.port {
            return "\(scheme)://\(hostPart):\(port)"
        }

        return "\(scheme)://\(hostPart)"
    }

    static func normalizeBaseURL(_ value: String, allowInsecureHTTP: Bool) throws -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        if trimmed.isEmpty {
            throw ValidationError("baseURL must not be blank")
        }
        if trimmed.containsCROrLF {
            throw ValidationError("baseURL must not contain CR or LF")
        }

        guard let components = URLComponents(string: trimmed) else {
            throw ValidationError("baseURL must be an absolute http or https URL")
        }

        let scheme = components.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else {
            throw ValidationError("baseURL must be an absolute http or https URL")
        }

        if scheme == "http" && !allowInsecureHTTP {
            throw ValidationError(
                "baseURL must use https. The SDK sends apiKey in the query string, "
                + "so http would transmit it in plaintext. Pass allowInsecureHTTP: true "
                + "in IPGeolocationClientConfig only for local testing or a trusted proxy."
            )
        }

        if components.user != nil || components.password != nil {
            throw ValidationError("baseURL must not include userinfo")
        }

        if components.query != nil || components.fragment != nil {
            throw ValidationError("baseURL must not include query or fragment")
        }

        guard let host = components.host, !host.isEmpty else {
            throw ValidationError("baseURL must include a valid host")
        }

        return trimmed
    }

    static func normalizeTimeout(_ value: TimeInterval, fieldName: String) throws -> TimeInterval {
        if !value.isFinite || value <= 0 {
            throw ValidationError("\(fieldName) must be greater than zero")
        }
        return value
    }

    static func normalizeMaxResponseBodyBytes(_ value: Int) throws -> Int {
        if value <= 0 {
            throw ValidationError("maxResponseBodyBytes must be greater than zero")
        }
        return value
    }
}

extension String {
    var containsCROrLF: Bool {
        // Check at the Unicode scalar level because "\r\n" is a single
        // `Character` (extended grapheme cluster) in Swift. String.contains
        // with "\r" or "\n" returns false on a string like "val\r\nue".
        unicodeScalars.contains(where: { $0 == "\r" || $0 == "\n" })
    }
}
