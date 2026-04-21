import XCTest
@testable import IPGeolocation

final class ResponseMapperTests: XCTestCase {
    func test_parseSingle_mapsAllModels() throws {
        let parsed = try ResponseMapper.parseSingle(TestFixtures.singleLookup)

        XCTAssertEqual(parsed.ip, "8.8.8.8")
        XCTAssertEqual(parsed.hostname, "dns.google")
        XCTAssertEqual(parsed.domain, "google.com")
        XCTAssertEqual(parsed.location?.countryCode2, "US")
        XCTAssertEqual(parsed.location?.isEU, false)
        XCTAssertEqual(parsed.countryMetadata?.languages, ["en-US", "es-US"])
        XCTAssertEqual(parsed.currency?.code, "USD")
        XCTAssertEqual(parsed.network?.isAnycast, true)
        XCTAssertEqual(parsed.asn?.asNumber, "AS15169")
        XCTAssertEqual(parsed.asn?.rir, "ARIN")
        XCTAssertEqual(parsed.company?.name, "Google LLC")
        XCTAssertEqual(parsed.timeZone?.name, "America/Los_Angeles")
        XCTAssertEqual(parsed.timeZone?.currentTZAbbreviation, "PDT")
        XCTAssertEqual(parsed.timeZone?.dstStart?.gap, true)
        XCTAssertEqual(parsed.timeZone?.dstEnd?.overlap, true)
        XCTAssertEqual(parsed.security?.threatScore, 0.1)
        XCTAssertEqual(parsed.security?.isCloudProvider, true)
        XCTAssertEqual(parsed.abuse?.emails, ["abuse@google.com"])
        XCTAssertEqual(parsed.userAgent?.name, "Safari")
        XCTAssertEqual(parsed.userAgent?.device?.brand, "Apple")
        XCTAssertEqual(parsed.userAgent?.operatingSystem?.version, "10.11.2")
    }

    func test_parseSingle_fallbackTimezoneKeys() throws {
        let legacy = """
        {
          "time_zone": {
            "name": "America/Los_Angeles",
            "current_timezone_abbreviation": "PDT",
            "current_timezone_name": "Pacific Daylight Time",
            "timezone_abbreviation": "PST",
            "timezone_name": "Pacific Standard Time",
            "dst_timezone_abbreviation": "PDT",
            "dst_timezone_name": "Pacific Daylight Time"
          }
        }
        """
        let parsed = try ResponseMapper.parseSingle(legacy)
        XCTAssertEqual(parsed.timeZone?.currentTZAbbreviation, "PDT")
        XCTAssertEqual(parsed.timeZone?.standardTZAbbreviation, "PST")
        XCTAssertEqual(parsed.timeZone?.dstTZAbbreviation, "PDT")
    }

    func test_parseSingle_emptyObjectBecomesNilForNestedTypes() throws {
        let body = """
        {"ip": "8.8.8.8", "time_zone": {}, "security": []}
        """
        let parsed = try ResponseMapper.parseSingle(body)
        // Empty JSON object `{}` should surface as nil, not as a struct with
        // every field nil. Otherwise `if let tz = response.timeZone` would
        // enter a branch with no useful data.
        XCTAssertNil(parsed.timeZone)
        XCTAssertNil(parsed.security)
    }

    func test_parseSingle_boolAcceptsNumericZeroAndOne() throws {
        let body = """
        {"location": {"is_eu": 1}, "security": {"is_vpn": 0, "is_proxy": true}}
        """
        let parsed = try ResponseMapper.parseSingle(body)
        XCTAssertEqual(parsed.location?.isEU, true)
        XCTAssertEqual(parsed.security?.isVPN, false)
        XCTAssertEqual(parsed.security?.isProxy, true)
    }

    func test_parseSingle_boolRejectsNumericOtherThanZeroOrOne() throws {
        let body = """
        {"location": {"is_eu": 42}}
        """
        let parsed = try ResponseMapper.parseSingle(body)
        XCTAssertNil(parsed.location?.isEU)
    }

    func test_parseSingle_invalidJSONThrowsSerializationError() {
        XCTAssertThrowsError(try ResponseMapper.parseSingle("not json")) { error in
            XCTAssertTrue(error is SerializationError)
        }
    }

    func test_parseSingle_rejectsNonObjectRoot() {
        XCTAssertThrowsError(try ResponseMapper.parseSingle("[]")) { error in
            XCTAssertTrue(error is SerializationError)
        }
    }

    func test_parseBulk_mixedResult() throws {
        let parsed = try ResponseMapper.parseBulk(TestFixtures.bulkMixed)

        XCTAssertEqual(parsed.count, 3)
        XCTAssertTrue(parsed[0].isSuccess)
        XCTAssertEqual(parsed[0].data?.ip, "8.8.8.8")
        XCTAssertFalse(parsed[1].isSuccess)
        XCTAssertEqual(parsed[1].error?.message, "Invalid IP address")
        XCTAssertFalse(parsed[2].isSuccess)
        XCTAssertEqual(parsed[2].error?.message, "rate limited")
    }

    func test_parseBulk_rejectsNonArrayRoot() {
        XCTAssertThrowsError(try ResponseMapper.parseBulk("{}")) { error in
            XCTAssertTrue(error is SerializationError)
        }
    }

    func test_parseBulk_handlesNestedErrorString() throws {
        let body = """
        [{"error": "rate limited"}]
        """
        let parsed = try ResponseMapper.parseBulk(body)
        XCTAssertFalse(parsed[0].isSuccess)
        XCTAssertEqual(parsed[0].error?.message, "rate limited")
    }

    func test_parseBulk_fallbackMessageForMalformedError() throws {
        let body = """
        [{"error": {}}]
        """
        let parsed = try ResponseMapper.parseBulk(body)
        XCTAssertEqual(parsed[0].error?.message, "Bulk lookup item failed")
    }

    func test_apiErrorFactory_mapsStatusToKind() {
        XCTAssertEqual(APIErrorFactory.kind(for: 400), .badRequest)
        XCTAssertEqual(APIErrorFactory.kind(for: 401), .unauthorized)
        XCTAssertEqual(APIErrorFactory.kind(for: 403), .forbidden)
        XCTAssertEqual(APIErrorFactory.kind(for: 404), .notFound)
        XCTAssertEqual(APIErrorFactory.kind(for: 405), .methodNotAllowed)
        XCTAssertEqual(APIErrorFactory.kind(for: 413), .contentTooLarge)
        XCTAssertEqual(APIErrorFactory.kind(for: 415), .unsupportedMediaType)
        XCTAssertEqual(APIErrorFactory.kind(for: 423), .locked)
        XCTAssertEqual(APIErrorFactory.kind(for: 429), .tooManyRequests)
        XCTAssertEqual(APIErrorFactory.kind(for: 499), .clientClosedRequest)
        XCTAssertEqual(APIErrorFactory.kind(for: 500), .internalServerError)
        XCTAssertEqual(APIErrorFactory.kind(for: 418), .other)
    }

    func test_apiErrorFactory_extractsNestedMessage() {
        let body = """
        {"error": {"message": "too many requests"}}
        """
        let error = APIErrorFactory.make(statusCode: 429, body: body)
        XCTAssertEqual(error.message, "too many requests")
        XCTAssertEqual(error.kind, .tooManyRequests)
    }

    func test_apiErrorFactory_fallsBackToStatusMessage() {
        let error = APIErrorFactory.make(statusCode: 500, body: "")
        XCTAssertEqual(error.message, "Internal server error")
    }

    func test_apiErrorFactory_usesRawBodyWhenNotJson() {
        let error = APIErrorFactory.make(statusCode: 418, body: "I am a teapot")
        XCTAssertEqual(error.message, "I am a teapot")
    }

    func test_apiError_localizedDescriptionSurvivesTypeErasure() {
        let concrete = APIError(kind: .unauthorized, statusCode: 401, message: "Invalid API key", apiMessage: "Invalid API key")
        let erased: Error = concrete
        XCTAssertEqual(erased.localizedDescription, "Invalid API key")
    }

    func test_validationError_localizedDescriptionSurvivesTypeErasure() {
        let concrete = ValidationError("apiKey must not be blank")
        let erased: Error = concrete
        XCTAssertEqual(erased.localizedDescription, "apiKey must not be blank")
    }

    func test_transportError_localizedDescriptionSurvivesTypeErasure() {
        let concrete = TransportError("connection refused")
        let erased: Error = concrete
        XCTAssertEqual(erased.localizedDescription, "connection refused")
    }

    func test_scrubAPIKey_replacesKnownKeyValue() {
        let scrubbed = scrubAPIKey(
            "lookup failed for request https://example.com?apiKey=supersecret&ip=8.8.8.8",
            apiKey: "supersecret"
        )
        XCTAssertFalse(scrubbed.contains("supersecret"))
        XCTAssertTrue(scrubbed.contains("[REDACTED]"))
    }

    func test_scrubAPIKey_replacesApiKeyQueryPatternEvenWithoutKnownKey() {
        let scrubbed = scrubAPIKey("upstream error: GET /path?apiKey=abc123xyz", apiKey: nil)
        XCTAssertFalse(scrubbed.contains("abc123xyz"))
        XCTAssertTrue(scrubbed.contains("apiKey=[REDACTED]"))
    }

    func test_scrubAPIKey_handlesMultipleOccurrencesWithoutLooping() {
        let body = "tried apiKey=a then apiKey=b and apiKey=c"
        let scrubbed = scrubAPIKey(body, apiKey: nil)
        XCTAssertFalse(scrubbed.contains("apiKey=a"))
        XCTAssertFalse(scrubbed.contains("apiKey=b"))
        XCTAssertFalse(scrubbed.contains("apiKey=c"))
        XCTAssertEqual(scrubbed.components(separatedBy: "apiKey=[REDACTED]").count - 1, 3)
    }

    func test_extractAPIMessage_scrubsReflectedRequestURL() throws {
        let body = "{\"message\": \"Upstream error for https://api.ipgeolocation.io/v3/ipgeo?apiKey=supersecret&ip=8.8.8.8\"}"
        let extracted = try XCTUnwrap(extractAPIMessage(from: body, apiKey: "supersecret"))
        XCTAssertFalse(extracted.contains("supersecret"))
        XCTAssertTrue(extracted.contains("[REDACTED]"))
    }

    func test_apiErrorFactory_passesApiKeyForScrubbing() {
        let body = "{\"message\": \"failed: apiKey=supersecret\"}"
        let error = APIErrorFactory.make(statusCode: 500, body: body, apiKey: "supersecret")
        XCTAssertFalse(error.message.contains("supersecret"))
        XCTAssertTrue(error.message.contains("[REDACTED]"))
    }

    func test_parseBulk_scrubsApiKeyFromBulkErrorMessage() throws {
        let body = """
        [{"error": {"message": "reflected http://example.com?apiKey=supersecret"}}]
        """
        let parsed = try ResponseMapper.parseBulk(body, apiKey: "supersecret")
        let message = try XCTUnwrap(parsed.first?.error?.message)
        XCTAssertFalse(message.contains("supersecret"))
        XCTAssertTrue(message.contains("[REDACTED]"))
    }
}
