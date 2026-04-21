import Foundation

public struct IPGeolocationClientConfig: Sendable {
    public static let defaultBaseURL: String = "https://api.ipgeolocation.io"
    public static let defaultRequestTimeout: TimeInterval = 10
    public static let defaultResourceTimeout: TimeInterval = 30
    public static let defaultMaxResponseBodyBytes: Int = 32 * 1024 * 1024

    public let apiKey: String?
    public let requestOrigin: String?
    public let baseURL: String
    /// Maximum time, in seconds, `URLSession` will wait for additional data on
    /// an in-flight request. Covers connect, headers, and inter-chunk body
    /// inactivity. Maps to `URLSessionConfiguration.timeoutIntervalForRequest`.
    public let requestTimeout: TimeInterval
    /// Maximum total time, in seconds, for the entire request. Maps to
    /// `URLSessionConfiguration.timeoutIntervalForResource`.
    public let resourceTimeout: TimeInterval
    public let maxResponseBodyBytes: Int
    /// Allows `baseURL` to use `http://`. Off by default because the SDK
    /// transmits `apiKey` as a query-string parameter, which would travel
    /// in plaintext over `http`. Set this to `true` only for local testing
    /// or a trusted proxy where you have accepted the risk.
    public let allowInsecureHTTP: Bool

    public init(
        apiKey: String? = nil,
        requestOrigin: String? = nil,
        baseURL: String = IPGeolocationClientConfig.defaultBaseURL,
        requestTimeout: TimeInterval = IPGeolocationClientConfig.defaultRequestTimeout,
        resourceTimeout: TimeInterval = IPGeolocationClientConfig.defaultResourceTimeout,
        maxResponseBodyBytes: Int = IPGeolocationClientConfig.defaultMaxResponseBodyBytes,
        allowInsecureHTTP: Bool = false
    ) throws {
        self.apiKey = try ConfigNormalizer.normalizeAPIKey(apiKey)
        self.requestOrigin = try ConfigNormalizer.normalizeRequestOrigin(requestOrigin)
        self.baseURL = try ConfigNormalizer.normalizeBaseURL(baseURL, allowInsecureHTTP: allowInsecureHTTP)
        self.requestTimeout = try ConfigNormalizer.normalizeTimeout(requestTimeout, fieldName: "requestTimeout")
        self.resourceTimeout = try ConfigNormalizer.normalizeTimeout(resourceTimeout, fieldName: "resourceTimeout")
        self.maxResponseBodyBytes = try ConfigNormalizer.normalizeMaxResponseBodyBytes(maxResponseBodyBytes)
        self.allowInsecureHTTP = allowInsecureHTTP

        if self.requestTimeout > self.resourceTimeout {
            throw ValidationError("requestTimeout must be <= resourceTimeout")
        }
    }

    public func safeDescription() -> [String: String] {
        [
            "apiKey": apiKey == nil ? "nil" : "[REDACTED]",
            "requestOrigin": requestOrigin ?? "nil",
            "baseURL": baseURL,
            "requestTimeout": "\(requestTimeout)s",
            "resourceTimeout": "\(resourceTimeout)s",
            "maxResponseBodyBytes": "\(maxResponseBodyBytes)",
            "allowInsecureHTTP": "\(allowInsecureHTTP)",
        ]
    }
}

extension IPGeolocationClientConfig: CustomStringConvertible {
    public var description: String {
        "IPGeolocationClientConfig(\(safeDescription()))"
    }
}

extension IPGeolocationClientConfig: CustomReflectable {
    public var customMirror: Mirror {
        let redacted: [(label: String?, value: Any)] = [
            ("apiKey", apiKey == nil ? "nil" : "[REDACTED]" as Any),
            ("requestOrigin", requestOrigin as Any),
            ("baseURL", baseURL),
            ("requestTimeout", requestTimeout),
            ("resourceTimeout", resourceTimeout),
            ("maxResponseBodyBytes", maxResponseBodyBytes),
            ("allowInsecureHTTP", allowInsecureHTTP),
        ]
        return Mirror(
            self,
            children: redacted,
            displayStyle: .struct,
            ancestorRepresentation: .suppressed
        )
    }
}

extension IPGeolocationClientConfig: CustomDebugStringConvertible {
    public var debugDescription: String {
        "IPGeolocationClientConfig(\(safeDescription()))"
    }
}
