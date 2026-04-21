import XCTest
@testable import IPGeolocation

final class RequestTests: XCTestCase {
    func test_lookupRequest_defaultsAreSafe() throws {
        let request = LookupIPGeolocationRequest()
        try request.validate()
        XCTAssertNil(request.ip)
        XCTAssertEqual(request.output, .json)
    }

    func test_lookupRequest_trimsAndPreservesIP() throws {
        let request = LookupIPGeolocationRequest(ip: "  8.8.8.8  ")
        let normalized = try RequestNormalizer.normalizeLookup(request)
        XCTAssertEqual(normalized.ip, "8.8.8.8")
    }

    func test_lookupRequest_ipMustNotBeBlankWhenProvided() {
        let request = LookupIPGeolocationRequest(ip: "   ")
        assertValidation("ip must not be blank") { try request.validate() }
    }

    func test_lookupRequest_ipRejectsCRLF() {
        let request = LookupIPGeolocationRequest(ip: "8.8\n.8.8")
        assertValidation("ip must not contain CR or LF") { try request.validate() }
    }

    func test_lookupRequest_includeDeduplicatesWhileKeepingOrder() throws {
        let request = LookupIPGeolocationRequest(include: ["security", "abuse", "security"])
        let normalized = try RequestNormalizer.normalizeLookup(request)
        XCTAssertEqual(normalized.include, ["security", "abuse"])
    }

    func test_lookupRequest_includeBlankValuesRejected() {
        let request = LookupIPGeolocationRequest(include: ["security", "  "])
        assertValidation("include must not contain blank values") { try request.validate() }
    }

    func test_lookupRequest_userAgentRejectsCRLF() {
        let request = LookupIPGeolocationRequest(userAgent: "ag\rent")
        assertValidation("userAgent must not contain CR or LF") { try request.validate() }
    }

    func test_lookupRequest_includeRejectsCommas() {
        let request = LookupIPGeolocationRequest(include: ["security,abuse"])
        assertValidation("include entries must not contain commas") { try request.validate() }
    }

    func test_lookupRequest_fieldsRejectsCommas() {
        let request = LookupIPGeolocationRequest(fields: ["location.country_name,location.city"])
        assertValidation("fields entries must not contain commas") { try request.validate() }
    }

    func test_lookupRequest_excludesRejectsCommas() {
        let request = LookupIPGeolocationRequest(excludes: ["currency,abuse"])
        assertValidation("excludes entries must not contain commas") { try request.validate() }
    }

    func test_lookupRequest_includeRejectsCRLF() {
        let request = LookupIPGeolocationRequest(include: ["secu\r\nrity"])
        assertValidation("include entries must not contain CR or LF") { try request.validate() }
    }

    func test_lookupRequest_fieldsRejectsCRLF() {
        let request = LookupIPGeolocationRequest(fields: ["location.country_name\nsecurity.threat_score"])
        assertValidation("fields entries must not contain CR or LF") { try request.validate() }
    }

    func test_lookupRequest_excludesRejectsCRLF() {
        let request = LookupIPGeolocationRequest(excludes: ["curren\rcy"])
        assertValidation("excludes entries must not contain CR or LF") { try request.validate() }
    }

    func test_lookupRequest_headersCanonicalizedToPascalCase() throws {
        let normalized = try RequestNormalizer.normalizeLookup(
            LookupIPGeolocationRequest(headers: ["accept-language": "en"])
        )
        XCTAssertEqual(normalized.headers["Accept-Language"], "en")
    }

    func test_lookupRequest_headerNameRejectsCRLF() {
        let request = LookupIPGeolocationRequest(headers: ["X-Bad\rName": "value"])
        assertValidation("headers must not contain CR or LF") { try request.validate() }
    }

    func test_lookupRequest_headerValueRejectsCRLF() {
        let request = LookupIPGeolocationRequest(headers: ["X-Custom": "val\r\nue"])
        assertValidation("headers must not contain CR or LF") { try request.validate() }
    }

    func test_lookupRequest_headersRejectBlankName() {
        let request = LookupIPGeolocationRequest(headers: ["   ": "value"])
        assertValidation("headers must not contain blank names") { try request.validate() }
    }

    func test_lookupRequest_headersRejectBlankValue() {
        let request = LookupIPGeolocationRequest(headers: ["X-Key": " "])
        assertValidation("headers must not contain blank values") { try request.validate() }
    }

    func test_bulkRequest_emptyIPsRejected() {
        let request = BulkLookupIPGeolocationRequest(ips: [])
        assertValidation("ips must contain at least one IP address or domain") { try request.validate() }
    }

    func test_bulkRequest_blankIPRejected() {
        let request = BulkLookupIPGeolocationRequest(ips: ["8.8.8.8", "   "])
        assertValidation("ips must not contain blank values") { try request.validate() }
    }

    func test_bulkRequest_ipRejectsCRLF() {
        let request = BulkLookupIPGeolocationRequest(ips: ["8.8.8.8", "1.1\n.1.1"])
        assertValidation("ip must not contain CR or LF") { try request.validate() }
    }

    func test_bulkRequest_preservesOrderAndDuplicates() throws {
        let request = BulkLookupIPGeolocationRequest(ips: ["1.1.1.1", "8.8.8.8", "1.1.1.1"])
        let normalized = try RequestNormalizer.normalizeBulk(request)
        XCTAssertEqual(normalized.ips, ["1.1.1.1", "8.8.8.8", "1.1.1.1"])
    }

    func test_bulkRequest_overLimitRejected() {
        let ips = Array(repeating: "8.8.8.8", count: 50_001)
        let request = BulkLookupIPGeolocationRequest(ips: ips)
        assertValidation("ips must not contain more than 50000 entries") { try request.validate() }
    }

    func test_languageEnumEmitsWireCode() throws {
        let normalized = try RequestNormalizer.normalizeLookup(
            LookupIPGeolocationRequest(lang: .fr)
        )
        XCTAssertEqual(normalized.lang, "fr")
    }
}
