import Foundation

public struct APIResponse<T: Sendable>: Sendable {
    public let data: T
    public let metadata: ResponseMetadata

    public init(data: T, metadata: ResponseMetadata) {
        self.data = data
        self.metadata = metadata
    }
}

public struct ResponseMetadata: Sendable {
    public let statusCode: Int
    public let durationMs: Int
    public let creditsCharged: Int?
    public let successfulRecords: Int?
    public let rawHeaders: [String: [String]]

    public init(
        statusCode: Int,
        durationMs: Int,
        creditsCharged: Int?,
        successfulRecords: Int?,
        rawHeaders: [String: [String]]
    ) {
        self.statusCode = statusCode
        self.durationMs = durationMs
        self.creditsCharged = creditsCharged
        self.successfulRecords = successfulRecords
        self.rawHeaders = rawHeaders
    }

    public func headerValues(_ name: String) -> [String] {
        let key = RequestNormalizer.canonicalHeaderName(name)
        return rawHeaders[key] ?? []
    }

    public func firstHeaderValue(_ name: String) -> String? {
        headerValues(name).first
    }
}
