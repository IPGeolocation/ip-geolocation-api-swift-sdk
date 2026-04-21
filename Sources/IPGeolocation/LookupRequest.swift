import Foundation

public struct LookupIPGeolocationRequest: Sendable {
    public var ip: String?
    public var lang: Language?
    public var include: [String]
    public var fields: [String]
    public var excludes: [String]
    public var userAgent: String?
    public var headers: [String: String]
    public var output: ResponseFormat

    public init(
        ip: String? = nil,
        lang: Language? = nil,
        include: [String] = [],
        fields: [String] = [],
        excludes: [String] = [],
        userAgent: String? = nil,
        headers: [String: String] = [:],
        output: ResponseFormat = .json
    ) {
        self.ip = ip
        self.lang = lang
        self.include = include
        self.fields = fields
        self.excludes = excludes
        self.userAgent = userAgent
        self.headers = headers
        self.output = output
    }

    public func validate() throws {
        _ = try RequestNormalizer.normalizeLookup(self)
    }
}

public struct BulkLookupIPGeolocationRequest: Sendable {
    public var ips: [String]
    public var lang: Language?
    public var include: [String]
    public var fields: [String]
    public var excludes: [String]
    public var userAgent: String?
    public var headers: [String: String]
    public var output: ResponseFormat

    public init(
        ips: [String],
        lang: Language? = nil,
        include: [String] = [],
        fields: [String] = [],
        excludes: [String] = [],
        userAgent: String? = nil,
        headers: [String: String] = [:],
        output: ResponseFormat = .json
    ) {
        self.ips = ips
        self.lang = lang
        self.include = include
        self.fields = fields
        self.excludes = excludes
        self.userAgent = userAgent
        self.headers = headers
        self.output = output
    }

    public func validate() throws {
        _ = try RequestNormalizer.normalizeBulk(self)
    }
}
