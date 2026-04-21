import Foundation

public struct IPGeolocationResponse: Sendable, Equatable {
    public var ip: String?
    public var hostname: String?
    public var domain: String?
    public var location: Location?
    public var countryMetadata: CountryMetadata?
    public var currency: Currency?
    public var network: Network?
    public var asn: ASNInfo?
    public var company: Company?
    public var timeZone: TimeZoneInfo?
    public var security: Security?
    public var userAgent: UserAgentInfo?
    public var abuse: Abuse?

    public init(
        ip: String? = nil,
        hostname: String? = nil,
        domain: String? = nil,
        location: Location? = nil,
        countryMetadata: CountryMetadata? = nil,
        currency: Currency? = nil,
        network: Network? = nil,
        asn: ASNInfo? = nil,
        company: Company? = nil,
        timeZone: TimeZoneInfo? = nil,
        security: Security? = nil,
        userAgent: UserAgentInfo? = nil,
        abuse: Abuse? = nil
    ) {
        self.ip = ip
        self.hostname = hostname
        self.domain = domain
        self.location = location
        self.countryMetadata = countryMetadata
        self.currency = currency
        self.network = network
        self.asn = asn
        self.company = company
        self.timeZone = timeZone
        self.security = security
        self.userAgent = userAgent
        self.abuse = abuse
    }
}

public struct Location: Sendable, Equatable {
    public var continentCode: String?
    public var continentName: String?
    public var countryCode2: String?
    public var countryCode3: String?
    public var countryName: String?
    public var countryNameOfficial: String?
    public var countryCapital: String?
    public var stateProv: String?
    public var stateCode: String?
    public var district: String?
    public var city: String?
    public var locality: String?
    public var accuracyRadius: String?
    public var confidence: String?
    public var dmaCode: String?
    public var zipcode: String?
    public var latitude: String?
    public var longitude: String?
    public var isEU: Bool?
    public var countryFlag: String?
    public var geonameId: String?
    public var countryEmoji: String?

    public init() {}
}

public struct CountryMetadata: Sendable, Equatable {
    public var callingCode: String?
    public var tld: String?
    public var languages: [String]?

    public init() {}
}

public struct Currency: Sendable, Equatable {
    public var code: String?
    public var name: String?
    public var symbol: String?

    public init() {}
}

public struct Network: Sendable, Equatable {
    public var connectionType: String?
    public var route: String?
    public var isAnycast: Bool?

    public init() {}
}

public struct ASNInfo: Sendable, Equatable {
    public var asNumber: String?
    public var organization: String?
    public var country: String?
    public var type: String?
    public var domain: String?
    public var dateAllocated: String?
    public var rir: String?

    public init() {}
}

public struct Company: Sendable, Equatable {
    public var name: String?
    public var type: String?
    public var domain: String?

    public init() {}
}

public struct TimeZoneInfo: Sendable, Equatable {
    public var name: String?
    public var offset: Double?
    public var offsetWithDST: Double?
    public var currentTime: String?
    public var currentTimeUnix: Double?
    public var currentTZAbbreviation: String?
    public var currentTZFullName: String?
    public var standardTZAbbreviation: String?
    public var standardTZFullName: String?
    public var isDST: Bool?
    public var dstSavings: Double?
    public var dstExists: Bool?
    public var dstTZAbbreviation: String?
    public var dstTZFullName: String?
    public var dstStart: DSTTransition?
    public var dstEnd: DSTTransition?

    public init() {}
}

public struct DSTTransition: Sendable, Equatable {
    public var utcTime: String?
    public var duration: String?
    public var gap: Bool?
    public var dateTimeAfter: String?
    public var dateTimeBefore: String?
    public var overlap: Bool?

    public init() {}
}

public struct Security: Sendable, Equatable {
    public var threatScore: Double?
    public var isTor: Bool?
    public var isProxy: Bool?
    public var proxyProviderNames: [String]?
    public var proxyConfidenceScore: Double?
    public var proxyLastSeen: String?
    public var isResidentialProxy: Bool?
    public var isVPN: Bool?
    public var vpnProviderNames: [String]?
    public var vpnConfidenceScore: Double?
    public var vpnLastSeen: String?
    public var isRelay: Bool?
    public var relayProviderName: String?
    public var isAnonymous: Bool?
    public var isKnownAttacker: Bool?
    public var isBot: Bool?
    public var isSpam: Bool?
    public var isCloudProvider: Bool?
    public var cloudProviderName: String?

    public init() {}
}

public struct Abuse: Sendable, Equatable {
    public var route: String?
    public var country: String?
    public var name: String?
    public var organization: String?
    public var kind: String?
    public var address: String?
    public var emails: [String]?
    public var phoneNumbers: [String]?

    public init() {}
}

public struct UserAgentInfo: Sendable, Equatable {
    public var userAgentString: String?
    public var name: String?
    public var type: String?
    public var version: String?
    public var versionMajor: String?
    public var device: UserAgentDevice?
    public var engine: UserAgentEngine?
    public var operatingSystem: UserAgentOperatingSystem?

    public init() {}
}

public struct UserAgentDevice: Sendable, Equatable {
    public var name: String?
    public var type: String?
    public var brand: String?
    public var cpu: String?

    public init() {}
}

public struct UserAgentEngine: Sendable, Equatable {
    public var name: String?
    public var type: String?
    public var version: String?
    public var versionMajor: String?

    public init() {}
}

public struct UserAgentOperatingSystem: Sendable, Equatable {
    public var name: String?
    public var type: String?
    public var version: String?
    public var versionMajor: String?
    public var build: String?

    public init() {}
}

public struct BulkLookupError: Sendable, Equatable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

public struct BulkLookupResult: Sendable, Equatable {
    public let data: IPGeolocationResponse?
    public let error: BulkLookupError?

    public init(data: IPGeolocationResponse?, error: BulkLookupError?) {
        self.data = data
        self.error = error
    }

    public var isSuccess: Bool {
        data != nil && error == nil
    }
}
