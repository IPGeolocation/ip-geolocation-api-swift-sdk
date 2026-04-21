import Foundation

enum ResponseMapper {
    static func parseSingle(_ body: String) throws -> IPGeolocationResponse {
        let object = try decodeObject(body, context: "single lookup response body")
        return parseResponse(object)
    }

    static func parseBulk(_ body: String, apiKey: String? = nil) throws -> [BulkLookupResult] {
        guard let data = body.data(using: .utf8) else {
            throw SerializationError("Failed to parse bulk lookup response body")
        }

        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw SerializationError("Failed to parse bulk lookup response body", underlyingError: error)
        }

        guard let items = parsed as? [Any] else {
            throw SerializationError("Failed to parse bulk lookup response body: expected JSON array")
        }

        var results: [BulkLookupResult] = []
        results.reserveCapacity(items.count)
        for item in items {
            guard let object = item as? [String: Any] else {
                throw SerializationError("Failed to parse bulk lookup response body: expected JSON object item")
            }

            if isBulkError(object) {
                let rawMessage = bulkErrorMessage(object)
                // Use the same finalizer as top-level APIError so bulk item
                // error messages are both scrubbed AND truncated at the
                // same 2048-char cap. Scrubbing without truncation would
                // let a hostile 200 bulk response produce an unbounded
                // BulkLookupError.message.
                let finalized = finalizeAPIMessage(rawMessage, apiKey: apiKey)
                results.append(BulkLookupResult(data: nil, error: BulkLookupError(message: finalized)))
                continue
            }

            results.append(BulkLookupResult(data: parseResponse(object), error: nil))
        }

        return results
    }

    static func isBulkError(_ object: [String: Any]) -> Bool {
        let hasError = object["error"] != nil
        let hasMessage = object["message"] != nil
        let hasIP = object["ip"] != nil
        return hasError || (hasMessage && !hasIP)
    }

    static func bulkErrorMessage(_ object: [String: Any]) -> String {
        if let message = object["message"] as? String, !message.isEmpty {
            return message
        }
        if let nested = object["error"] as? [String: Any],
           let nestedMessage = nested["message"] as? String,
           !nestedMessage.isEmpty {
            return nestedMessage
        }
        if let nestedString = object["error"] as? String, !nestedString.isEmpty {
            return nestedString
        }
        return "Bulk lookup item failed"
    }

    static func parseResponse(_ object: [String: Any]) -> IPGeolocationResponse {
        IPGeolocationResponse(
            ip: readString(object, "ip"),
            hostname: readString(object, "hostname"),
            domain: readString(object, "domain"),
            location: readNestedObject(object, "location", parseLocation),
            countryMetadata: readNestedObject(object, "country_metadata", parseCountryMetadata),
            currency: readNestedObject(object, "currency", parseCurrency),
            network: readNestedObject(object, "network", parseNetwork),
            asn: readNestedObject(object, "asn", parseASN),
            company: readNestedObject(object, "company", parseCompany),
            timeZone: readNestedObject(object, "time_zone", parseTimeZone),
            security: readNestedObject(object, "security", parseSecurity),
            userAgent: readNestedObject(object, "user_agent", parseUserAgent),
            abuse: readNestedObject(object, "abuse", parseAbuse)
        )
    }

    static func parseLocation(_ object: [String: Any]) -> Location {
        var value = Location()
        value.continentCode = readString(object, "continent_code")
        value.continentName = readString(object, "continent_name")
        value.countryCode2 = readString(object, "country_code2")
        value.countryCode3 = readString(object, "country_code3")
        value.countryName = readString(object, "country_name")
        value.countryNameOfficial = readString(object, "country_name_official")
        value.countryCapital = readString(object, "country_capital")
        value.stateProv = readString(object, "state_prov")
        value.stateCode = readString(object, "state_code")
        value.district = readString(object, "district")
        value.city = readString(object, "city")
        value.locality = readString(object, "locality")
        value.accuracyRadius = readString(object, "accuracy_radius")
        value.confidence = readString(object, "confidence")
        value.dmaCode = readString(object, "dma_code")
        value.zipcode = readString(object, "zipcode")
        value.latitude = readString(object, "latitude")
        value.longitude = readString(object, "longitude")
        value.isEU = readBool(object, "is_eu")
        value.countryFlag = readString(object, "country_flag")
        value.geonameId = readString(object, "geoname_id")
        value.countryEmoji = readString(object, "country_emoji")
        return value
    }

    static func parseCountryMetadata(_ object: [String: Any]) -> CountryMetadata {
        var value = CountryMetadata()
        value.callingCode = readString(object, "calling_code")
        value.tld = readString(object, "tld")
        value.languages = readStringArray(object, "languages")
        return value
    }

    static func parseCurrency(_ object: [String: Any]) -> Currency {
        var value = Currency()
        value.code = readString(object, "code")
        value.name = readString(object, "name")
        value.symbol = readString(object, "symbol")
        return value
    }

    static func parseNetwork(_ object: [String: Any]) -> Network {
        var value = Network()
        value.connectionType = readString(object, "connection_type")
        value.route = readString(object, "route")
        value.isAnycast = readBool(object, "is_anycast")
        return value
    }

    static func parseASN(_ object: [String: Any]) -> ASNInfo {
        var value = ASNInfo()
        value.asNumber = readString(object, "as_number")
        value.organization = readString(object, "organization")
        value.country = readString(object, "country")
        value.type = readString(object, "type")
        value.domain = readString(object, "domain")
        value.dateAllocated = readString(object, "date_allocated")
        value.rir = readString(object, "rir")
        return value
    }

    static func parseCompany(_ object: [String: Any]) -> Company {
        var value = Company()
        value.name = readString(object, "name")
        value.type = readString(object, "type")
        value.domain = readString(object, "domain")
        return value
    }

    static func parseTimeZone(_ object: [String: Any]) -> TimeZoneInfo {
        var value = TimeZoneInfo()
        value.name = readString(object, "name")
        value.offset = readDouble(object, "offset")
        value.offsetWithDST = readDouble(object, "offset_with_dst")
        value.currentTime = readString(object, "current_time")
        value.currentTimeUnix = readDouble(object, "current_time_unix")
        value.currentTZAbbreviation = readFirstString(object, ["current_tz_abbreviation", "current_timezone_abbreviation"])
        value.currentTZFullName = readFirstString(object, ["current_tz_full_name", "current_timezone_name"])
        value.standardTZAbbreviation = readFirstString(object, ["standard_tz_abbreviation", "timezone_abbreviation"])
        value.standardTZFullName = readFirstString(object, ["standard_tz_full_name", "timezone_name"])
        value.isDST = readBool(object, "is_dst")
        value.dstSavings = readDouble(object, "dst_savings")
        value.dstExists = readBool(object, "dst_exists")
        value.dstTZAbbreviation = readFirstString(object, ["dst_tz_abbreviation", "dst_timezone_abbreviation"])
        value.dstTZFullName = readFirstString(object, ["dst_tz_full_name", "dst_timezone_name"])
        value.dstStart = readNestedObject(object, "dst_start", parseDSTTransition)
        value.dstEnd = readNestedObject(object, "dst_end", parseDSTTransition)
        return value
    }

    static func parseDSTTransition(_ object: [String: Any]) -> DSTTransition {
        var value = DSTTransition()
        value.utcTime = readString(object, "utc_time")
        value.duration = readString(object, "duration")
        value.gap = readBool(object, "gap")
        value.dateTimeAfter = readString(object, "date_time_after")
        value.dateTimeBefore = readString(object, "date_time_before")
        value.overlap = readBool(object, "overlap")
        return value
    }

    static func parseSecurity(_ object: [String: Any]) -> Security {
        var value = Security()
        value.threatScore = readDouble(object, "threat_score")
        value.isTor = readBool(object, "is_tor")
        value.isProxy = readBool(object, "is_proxy")
        value.proxyProviderNames = readStringArray(object, "proxy_provider_names")
        value.proxyConfidenceScore = readDouble(object, "proxy_confidence_score")
        value.proxyLastSeen = readString(object, "proxy_last_seen")
        value.isResidentialProxy = readBool(object, "is_residential_proxy")
        value.isVPN = readBool(object, "is_vpn")
        value.vpnProviderNames = readStringArray(object, "vpn_provider_names")
        value.vpnConfidenceScore = readDouble(object, "vpn_confidence_score")
        value.vpnLastSeen = readString(object, "vpn_last_seen")
        value.isRelay = readBool(object, "is_relay")
        value.relayProviderName = readString(object, "relay_provider_name")
        value.isAnonymous = readBool(object, "is_anonymous")
        value.isKnownAttacker = readBool(object, "is_known_attacker")
        value.isBot = readBool(object, "is_bot")
        value.isSpam = readBool(object, "is_spam")
        value.isCloudProvider = readBool(object, "is_cloud_provider")
        value.cloudProviderName = readString(object, "cloud_provider_name")
        return value
    }

    static func parseAbuse(_ object: [String: Any]) -> Abuse {
        var value = Abuse()
        value.route = readString(object, "route")
        value.country = readString(object, "country")
        value.name = readString(object, "name")
        value.organization = readString(object, "organization")
        value.kind = readString(object, "kind")
        value.address = readString(object, "address")
        value.emails = readStringArray(object, "emails")
        value.phoneNumbers = readStringArray(object, "phone_numbers")
        return value
    }

    static func parseUserAgent(_ object: [String: Any]) -> UserAgentInfo {
        var value = UserAgentInfo()
        value.userAgentString = readString(object, "user_agent_string")
        value.name = readString(object, "name")
        value.type = readString(object, "type")
        value.version = readString(object, "version")
        value.versionMajor = readString(object, "version_major")
        value.device = readNestedObject(object, "device", parseUserAgentDevice)
        value.engine = readNestedObject(object, "engine", parseUserAgentEngine)
        value.operatingSystem = readNestedObject(object, "operating_system", parseUserAgentOperatingSystem)
        return value
    }

    static func parseUserAgentDevice(_ object: [String: Any]) -> UserAgentDevice {
        var value = UserAgentDevice()
        value.name = readString(object, "name")
        value.type = readString(object, "type")
        value.brand = readString(object, "brand")
        value.cpu = readString(object, "cpu")
        return value
    }

    static func parseUserAgentEngine(_ object: [String: Any]) -> UserAgentEngine {
        var value = UserAgentEngine()
        value.name = readString(object, "name")
        value.type = readString(object, "type")
        value.version = readString(object, "version")
        value.versionMajor = readString(object, "version_major")
        return value
    }

    static func parseUserAgentOperatingSystem(_ object: [String: Any]) -> UserAgentOperatingSystem {
        var value = UserAgentOperatingSystem()
        value.name = readString(object, "name")
        value.type = readString(object, "type")
        value.version = readString(object, "version")
        value.versionMajor = readString(object, "version_major")
        value.build = readString(object, "build")
        return value
    }

    static func decodeObject(_ body: String, context: String) throws -> [String: Any] {
        guard let data = body.data(using: .utf8) else {
            throw SerializationError("Failed to parse \(context)")
        }

        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw SerializationError("Failed to parse \(context)", underlyingError: error)
        }

        guard let object = parsed as? [String: Any] else {
            throw SerializationError("Failed to parse \(context): expected JSON object")
        }

        return object
    }

    static func readString(_ object: [String: Any], _ key: String) -> String? {
        guard let raw = object[key] else { return nil }
        if raw is NSNull { return nil }
        if let value = raw as? String { return value }
        if let number = raw as? NSNumber {
            if isBoolNumber(number) {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }
        if let bool = raw as? Bool { return bool ? "true" : "false" }
        return nil
    }

    static func readFirstString(_ object: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let value = readString(object, key) {
                return value
            }
        }
        return nil
    }

    static func readBool(_ object: [String: Any], _ key: String) -> Bool? {
        guard let raw = object[key] else { return nil }
        if raw is NSNull { return nil }
        if let value = raw as? Bool { return value }
        if let number = raw as? NSNumber {
            if isBoolNumber(number) {
                return number.boolValue
            }
            // Accept numeric 0 / 1 as booleans so the JSON input `1` maps to
            // `true` the same way the string input `"1"` already does. Anything
            // else (42, -1, 0.5) falls through to nil.
            let intValue = number.intValue
            if intValue == 0 && number.doubleValue == 0 { return false }
            if intValue == 1 && number.doubleValue == 1 { return true }
        }
        if let string = raw as? String {
            switch string.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        }
        return nil
    }

    static func readDouble(_ object: [String: Any], _ key: String) -> Double? {
        guard let raw = object[key] else { return nil }
        if raw is NSNull { return nil }
        if let number = raw as? NSNumber {
            if isBoolNumber(number) {
                return nil
            }
            return number.doubleValue
        }
        if let string = raw as? String {
            return Double(string)
        }
        return nil
    }

    /// Returns true when the NSNumber is actually an Objective-C `BOOL` and
    /// not a regular integer or floating-point value. Uses the Objective-C
    /// type encoding (`"c"` = `char`, which is how `BOOL` bridges) because
    /// that check is portable to Linux swift-corelibs-foundation. The older
    /// `CFNumberGetType(number) == .charType` approach is Apple-only.
    static func isBoolNumber(_ number: NSNumber) -> Bool {
        String(cString: number.objCType) == "c"
    }

    static func readStringArray(_ object: [String: Any], _ key: String) -> [String]? {
        guard let raw = object[key] else { return nil }
        if raw is NSNull { return nil }
        guard let array = raw as? [Any] else { return nil }
        var result: [String] = []
        result.reserveCapacity(array.count)
        for element in array {
            if element is NSNull { continue }
            if let value = element as? String, !value.isEmpty {
                result.append(value)
            } else if let number = element as? NSNumber {
                result.append(number.stringValue)
            }
        }
        return result
    }

    static func readNestedObject<T>(_ object: [String: Any], _ key: String, _ parser: ([String: Any]) -> T) -> T? {
        guard let raw = object[key] else { return nil }
        if raw is NSNull { return nil }
        if let array = raw as? [Any], array.isEmpty { return nil }
        guard let nested = raw as? [String: Any] else { return nil }
        if nested.isEmpty { return nil }
        return parser(nested)
    }
}
