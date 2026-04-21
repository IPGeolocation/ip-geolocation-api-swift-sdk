import Foundation

public protocol IPGeolocationError: LocalizedError, CustomStringConvertible {
    var message: String { get }
}

public extension IPGeolocationError {
    var description: String { message }
    var errorDescription: String? { message }
}

public struct ValidationError: IPGeolocationError, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}

public struct TransportError: IPGeolocationError {
    public let message: String
    public let underlyingError: Error?

    public init(_ message: String, underlyingError: Error? = nil) {
        self.message = message
        self.underlyingError = underlyingError
    }
}

public struct RequestTimeoutError: IPGeolocationError {
    public let message: String
    public let underlyingError: Error?

    public init(_ message: String, underlyingError: Error? = nil) {
        self.message = message
        self.underlyingError = underlyingError
    }
}

public struct SerializationError: IPGeolocationError {
    public let message: String
    public let underlyingError: Error?

    public init(_ message: String, underlyingError: Error? = nil) {
        self.message = message
        self.underlyingError = underlyingError
    }
}

public enum APIErrorKind: Sendable, Equatable {
    case badRequest
    case unauthorized
    case forbidden
    case notFound
    case methodNotAllowed
    case contentTooLarge
    case unsupportedMediaType
    case locked
    case tooManyRequests
    case clientClosedRequest
    case internalServerError
    case other
}

public struct APIError: IPGeolocationError, Equatable {
    public let kind: APIErrorKind
    public let statusCode: Int
    public let message: String
    public let apiMessage: String?

    public init(kind: APIErrorKind, statusCode: Int, message: String, apiMessage: String?) {
        self.kind = kind
        self.statusCode = statusCode
        self.message = message
        self.apiMessage = apiMessage
    }
}

enum APIErrorFactory {
    static func make(statusCode: Int, body: String, apiKey: String? = nil) -> APIError {
        let extracted = extractAPIMessage(from: body, apiKey: apiKey)
        let resolved = extracted ?? defaultMessage(for: statusCode)
        return APIError(
            kind: kind(for: statusCode),
            statusCode: statusCode,
            message: resolved,
            apiMessage: extracted
        )
    }

    static func kind(for statusCode: Int) -> APIErrorKind {
        switch statusCode {
        case 400: return .badRequest
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 405: return .methodNotAllowed
        case 413: return .contentTooLarge
        case 415: return .unsupportedMediaType
        case 423: return .locked
        case 429: return .tooManyRequests
        case 499: return .clientClosedRequest
        case 500: return .internalServerError
        default: return .other
        }
    }

    static func defaultMessage(for statusCode: Int) -> String {
        switch statusCode {
        case 400: return "Bad request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not found"
        case 405: return "Method not allowed"
        case 413: return "Content too large"
        case 415: return "Unsupported media type"
        case 423: return "Locked"
        case 429: return "Too many requests"
        case 499: return "Client closed request"
        case 500: return "Internal server error"
        default: return "API request failed with status code \(statusCode)"
        }
    }
}

/// Maximum length of an extracted API error message. Extracted messages are
/// surfaced in `APIError.message`. Capping protects against a hostile or
/// buggy server that returns a huge error body while keeping enough room for
/// any realistic message the API would emit.
let apiErrorMessageMaxLength: Int = 2048

func extractAPIMessage(from body: String, apiKey: String? = nil) -> String? {
    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    guard let data = trimmed.data(using: .utf8),
          let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
        return finalizeAPIMessage(trimmed, apiKey: apiKey)
    }

    guard let object = parsed as? [String: Any] else {
        return finalizeAPIMessage(trimmed, apiKey: apiKey)
    }

    if let message = object["message"] as? String, !message.isEmpty {
        return finalizeAPIMessage(message, apiKey: apiKey)
    }

    if let nested = object["error"] as? [String: Any],
       let nestedMessage = nested["message"] as? String,
       !nestedMessage.isEmpty {
        return finalizeAPIMessage(nestedMessage, apiKey: apiKey)
    }

    if let nestedString = object["error"] as? String, !nestedString.isEmpty {
        return finalizeAPIMessage(nestedString, apiKey: apiKey)
    }

    return finalizeAPIMessage(trimmed, apiKey: apiKey)
}

/// Applies API-key scrubbing and then truncation. Scrub must happen first so
/// a long secret leaks only the redaction marker, not a truncated prefix.
func finalizeAPIMessage(_ value: String, apiKey: String?) -> String {
    truncateAPIMessage(scrubAPIKey(value, apiKey: apiKey))
}

/// Removes the configured API key and any `apiKey=<value>` query-parameter
/// occurrence from the given string. Defends against proxies or upstream
/// error handlers that reflect the original request URL (including its
/// query string) back in the response body.
func scrubAPIKey(_ value: String, apiKey: String?) -> String {
    var result = value

    if let key = apiKey, !key.isEmpty, result.contains(key) {
        result = result.replacingOccurrences(of: key, with: "[REDACTED]")
    }

    // Catch any `apiKey=...` occurrence even when the value does not match
    // the configured key, for example on a proxy that substitutes its own.
    // The value pattern stops at the first boundary character so the match
    // does not span multiple query parameters.
    result = result.replacingOccurrences(
        of: "apiKey=[^&\\s\"'<>]+",
        with: "apiKey=[REDACTED]",
        options: .regularExpression
    )

    return result
}

func truncateAPIMessage(_ value: String) -> String {
    guard value.count > apiErrorMessageMaxLength else { return value }
    let end = value.index(value.startIndex, offsetBy: apiErrorMessageMaxLength)
    return String(value[..<end]) + "..."
}
