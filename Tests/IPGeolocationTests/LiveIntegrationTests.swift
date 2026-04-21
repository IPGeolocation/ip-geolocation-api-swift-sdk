import Foundation
import XCTest
@testable import IPGeolocation

final class LiveIntegrationTests: XCTestCase {
    func test_live_singleLookupReturnsIP() async throws {
        let keys = try LiveTestGuard.requireLiveTests()
        let client = IPGeolocationClient(config: try IPGeolocationClientConfig(apiKey: keys.freeKey))
        defer { client.close() }

        let response = try await client.lookupIPGeolocation(LookupIPGeolocationRequest(ip: "8.8.8.8"))
        XCTAssertEqual(response.data.ip, "8.8.8.8")
        XCTAssertNotNil(response.data.location?.countryName)
        XCTAssertEqual(response.metadata.statusCode, 200)
    }

    func test_live_singleLookupRawXMLContainsIPElement() async throws {
        let keys = try LiveTestGuard.requireLiveTests()
        let client = IPGeolocationClient(config: try IPGeolocationClientConfig(apiKey: keys.freeKey))
        defer { client.close() }

        let response = try await client.lookupIPGeolocationRaw(
            LookupIPGeolocationRequest(ip: "8.8.8.8", output: .xml)
        )
        XCTAssertTrue(response.data.contains("<ip>"), "expected <ip> element, got \(response.data.prefix(200))")
    }

    func test_live_freeKeyRejectsSecurityInclude() async throws {
        let keys = try LiveTestGuard.requireLiveTests()
        let client = IPGeolocationClient(config: try IPGeolocationClientConfig(apiKey: keys.freeKey))
        defer { client.close() }

        do {
            _ = try await client.lookupIPGeolocation(
                LookupIPGeolocationRequest(ip: "8.8.8.8", include: ["security"])
            )
            XCTFail("expected APIError for free-plan paid module request")
        } catch let error as APIError {
            // The API documents this path as 401 Unauthorized, not a generic
            // 4xx. Asserting the exact status code keeps this test a real
            // regression gate instead of passing on any error.
            XCTAssertEqual(error.statusCode, 401)
            XCTAssertEqual(error.kind, .unauthorized)
        }
    }

    func test_live_freeKeyIncludesWildcardFallsBackToBaseModules() async throws {
        let keys = try LiveTestGuard.requireLiveTests()
        let client = IPGeolocationClient(config: try IPGeolocationClientConfig(apiKey: keys.freeKey))
        defer { client.close() }

        let response = try await client.lookupIPGeolocation(
            LookupIPGeolocationRequest(ip: "8.8.8.8", include: ["*"])
        )
        XCTAssertEqual(response.data.ip, "8.8.8.8")
        // The contract is that `include=["*"]` on a free key does not unlock
        // paid modules. Assert each paid module is absent so a future
        // regression where the API quietly leaks them would fail the test.
        XCTAssertNil(response.data.security, "free plan include=* must not surface security")
        XCTAssertNil(response.data.abuse, "free plan include=* must not surface abuse")
        XCTAssertNil(response.data.userAgent, "free plan include=* must not surface user_agent")
        XCTAssertNil(response.data.hostname, "free plan include=* must not surface hostname")
    }

    func test_live_freeKeyBulkLookupRejected() async throws {
        let keys = try LiveTestGuard.requireLiveTests()
        let client = IPGeolocationClient(config: try IPGeolocationClientConfig(apiKey: keys.freeKey))
        defer { client.close() }

        do {
            _ = try await client.bulkLookupIPGeolocation(BulkLookupIPGeolocationRequest(ips: ["8.8.8.8"]))
            XCTFail("expected APIError for free-plan bulk")
        } catch let error as APIError {
            XCTAssertEqual(error.statusCode, 401)
            XCTAssertEqual(error.kind, .unauthorized)
        }
    }

    func test_live_paidKeyReturnsSecurityAndAbuse() async throws {
        let keys = try LiveTestGuard.requireLiveTests()
        let client = IPGeolocationClient(config: try IPGeolocationClientConfig(apiKey: keys.paidKey))
        defer { client.close() }

        let response = try await client.lookupIPGeolocation(
            LookupIPGeolocationRequest(ip: "9.9.9.9", include: ["security", "abuse"])
        )
        XCTAssertNotNil(response.data.security)
        XCTAssertNotNil(response.data.abuse)
    }

    func test_live_paidKeyBulkLookupMixed() async throws {
        let keys = try LiveTestGuard.requireLiveTests()
        let client = IPGeolocationClient(config: try IPGeolocationClientConfig(apiKey: keys.paidKey))
        defer { client.close() }

        let response = try await client.bulkLookupIPGeolocation(
            BulkLookupIPGeolocationRequest(ips: ["8.8.8.8", "not-a-valid-ip"])
        )
        XCTAssertEqual(response.data.count, 2)
        XCTAssertTrue(response.data.first?.isSuccess ?? false)
        XCTAssertFalse(response.data.last?.isSuccess ?? true)
    }

    // Typed-XML-rejection is covered by `ClientTests.test_singleLookup_typedRejectsXMLBeforeTransport`
    // and `ClientTests.test_bulkLookup_typedRejectsXMLBeforeTransport`. Those tests do not touch the
    // network, so they belong in the unit suite, not behind the `LiveTestGuard` here.

    func test_live_requestUserAgentOverrideReachesAPI() async throws {
        let keys = try LiveTestGuard.requireLiveTests()
        let client = IPGeolocationClient(config: try IPGeolocationClientConfig(apiKey: keys.paidKey))
        defer { client.close() }

        let override = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_2) AppleWebKit/601.3.9 Version/9.0.2 Safari/601.3.9"
        let response = try await client.lookupIPGeolocation(
            LookupIPGeolocationRequest(
                ip: "115.240.90.163",
                include: ["user_agent"],
                userAgent: override
            )
        )

        // Assert fields derived from the override, not just non-nil. If the
        // SDK ever dropped the override header, the API would parse the SDK
        // default UA instead and this test used to still pass. Mac Safari
        // 9.0.2 is a stable signature: name is Safari, engine name is
        // AppleWebKit, and the operating system name is populated.
        let parsed = try XCTUnwrap(response.data.userAgent)
        XCTAssertEqual(parsed.userAgentString, override)
        XCTAssertEqual(parsed.name, "Safari")
        XCTAssertEqual(parsed.engine?.name, "AppleWebKit")
        XCTAssertNotNil(parsed.operatingSystem?.name)
    }
}
