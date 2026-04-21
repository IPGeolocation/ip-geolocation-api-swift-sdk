import Foundation
import XCTest
@testable import IPGeolocation

final class ClientTests: XCTestCase {
    func test_singleLookup_typedParsesAndAttachesMetadata() async throws {
        let transport = MockTransport()
        transport.enqueue(
            statusCode: 200,
            body: TestFixtures.singleLookup,
            headers: [
                "X-Credits-Charged": ["2"],
                "X-Successful-Records": ["1"],
                "Content-Type": ["application/json"],
            ]
        )

        let client = IPGeolocationClient(
            config: try IPGeolocationClientConfig(apiKey: "key"),
            transport: transport
        )

        let response = try await client.lookupIPGeolocation(LookupIPGeolocationRequest(ip: "8.8.8.8"))
        XCTAssertEqual(response.data.ip, "8.8.8.8")
        XCTAssertEqual(response.metadata.statusCode, 200)
        XCTAssertEqual(response.metadata.creditsCharged, 2)
        XCTAssertEqual(response.metadata.successfulRecords, 1)
        XCTAssertEqual(response.metadata.firstHeaderValue("content-type"), "application/json")

        let captured = transport.requireLast()
        XCTAssertEqual(captured.method, "GET")
        XCTAssertTrue(captured.url.absoluteString.hasPrefix("https://api.ipgeolocation.io/v3/ipgeo?"))
        XCTAssertTrue(captured.url.absoluteString.contains("apiKey=key"))
        XCTAssertTrue(captured.url.absoluteString.contains("ip=8.8.8.8"))
        XCTAssertEqual(captured.headers["Accept"], "application/json")
        XCTAssertEqual(captured.headers["User-Agent"], SDKVersion.defaultUserAgent())
        XCTAssertNil(captured.headers["Origin"])
    }

    func test_singleLookup_requiresAPIKeyOrRequestOrigin() async throws {
        let transport = MockTransport()
        let client = IPGeolocationClient(
            config: try IPGeolocationClientConfig(),
            transport: transport
        )

        await assertValidationAsync("single lookup requires apiKey or requestOrigin in client config") {
            _ = try await client.lookupIPGeolocation()
        }

        XCTAssertTrue(transport.capturedRequests.isEmpty)
    }

    func test_singleLookup_withRequestOriginOnly_setsOriginHeader() async throws {
        let transport = MockTransport()
        transport.enqueue(statusCode: 200, body: "{\"ip\": \"1.2.3.4\"}")

        let client = IPGeolocationClient(
            config: try IPGeolocationClientConfig(requestOrigin: "https://app.example.com"),
            transport: transport
        )

        _ = try await client.lookupIPGeolocation(LookupIPGeolocationRequest(ip: "1.2.3.4"))
        let captured = transport.requireLast()
        XCTAssertEqual(captured.headers["Origin"], "https://app.example.com")
        XCTAssertFalse(captured.url.absoluteString.contains("apiKey="))
    }

    func test_singleLookup_configRequestOriginOverridesRequestSuppliedOriginHeader() async throws {
        let transport = MockTransport()
        transport.enqueue(statusCode: 200, body: "{\"ip\": \"1.2.3.4\"}")

        let client = IPGeolocationClient(
            config: try IPGeolocationClientConfig(requestOrigin: "https://config.example.com"),
            transport: transport
        )

        _ = try await client.lookupIPGeolocation(
            LookupIPGeolocationRequest(ip: "1.2.3.4", headers: ["Origin": "https://caller.example.com"])
        )
        let captured = transport.requireLast()
        XCTAssertEqual(captured.headers["Origin"], "https://config.example.com")
    }

    func test_singleLookup_typedRejectsXMLBeforeTransport() async throws {
        let transport = MockTransport()
        let client = IPGeolocationClient(
            config: try IPGeolocationClientConfig(apiKey: "k"),
            transport: transport
        )

        await assertValidationAsync("typed methods support JSON only") {
            _ = try await client.lookupIPGeolocation(LookupIPGeolocationRequest(ip: "8.8.8.8", output: .xml))
        }
        XCTAssertTrue(transport.capturedRequests.isEmpty)
    }

    func test_bulkLookup_typedRejectsXMLBeforeTransport() async throws {
        let transport = MockTransport()
        let client = IPGeolocationClient(
            config: try IPGeolocationClientConfig(apiKey: "k"),
            transport: transport
        )

        await assertValidationAsync("typed methods support JSON only") {
            _ = try await client.bulkLookupIPGeolocation(
                BulkLookupIPGeolocationRequest(ips: ["8.8.8.8"], output: .xml)
            )
        }
        XCTAssertTrue(transport.capturedRequests.isEmpty)
    }

    func test_rawSingleLookup_returnsRawBodyAndAllowsXML() async throws {
        let transport = MockTransport()
        let xmlBody = "<ipgeolocation><ip>8.8.8.8</ip></ipgeolocation>"
        transport.enqueue(statusCode: 200, body: xmlBody, headers: ["Content-Type": ["application/xml"]])

        let client = IPGeolocationClient(
            config: try IPGeolocationClientConfig(apiKey: "k"),
            transport: transport
        )

        let response = try await client.lookupIPGeolocationRaw(
            LookupIPGeolocationRequest(ip: "8.8.8.8", output: .xml)
        )
        XCTAssertEqual(response.data, xmlBody)
        let captured = transport.requireLast()
        XCTAssertEqual(captured.headers["Accept"], "application/xml")
    }

    func test_requestUserAgentOverridesHeaderAndDefault() async throws {
        let transport = MockTransport()
        transport.enqueue(statusCode: 200, body: "{\"ip\": \"8.8.8.8\"}")

        let client = IPGeolocationClient(
            config: try IPGeolocationClientConfig(apiKey: "k"),
            transport: transport
        )

        _ = try await client.lookupIPGeolocation(
            LookupIPGeolocationRequest(
                ip: "8.8.8.8",
                userAgent: "explicit/1.0",
                headers: ["User-Agent": "header/1.0"]
            )
        )

        let captured = transport.requireLast()
        XCTAssertEqual(captured.headers["User-Agent"], "explicit/1.0")
    }

    func test_headerUserAgentOverridesDefault() async throws {
        let transport = MockTransport()
        transport.enqueue(statusCode: 200, body: "{\"ip\": \"8.8.8.8\"}")

        let client = IPGeolocationClient(
            config: try IPGeolocationClientConfig(apiKey: "k"),
            transport: transport
        )

        _ = try await client.lookupIPGeolocation(
            LookupIPGeolocationRequest(ip: "8.8.8.8", headers: ["User-Agent": "header/1.0"])
        )
        let captured = transport.requireLast()
        XCTAssertEqual(captured.headers["User-Agent"], "header/1.0")
    }

    func test_bulkLookup_requiresAPIKeyEvenWithRequestOrigin() async throws {
        let transport = MockTransport()
        let client = IPGeolocationClient(
            config: try IPGeolocationClientConfig(requestOrigin: "https://app.example.com"),
            transport: transport
        )

        await assertValidationAsync("bulk lookup requires apiKey in client config") {
            _ = try await client.bulkLookupIPGeolocation(BulkLookupIPGeolocationRequest(ips: ["8.8.8.8"]))
        }
        XCTAssertTrue(transport.capturedRequests.isEmpty)
    }

    func test_bulkLookup_doesNotSendOriginHeaderEvenWhenConfigured() async throws {
        let transport = MockTransport()
        transport.enqueue(statusCode: 200, body: "[]")

        let client = IPGeolocationClient(
            config: try IPGeolocationClientConfig(
                apiKey: "k",
                requestOrigin: "https://app.example.com"
            ),
            transport: transport
        )

        _ = try await client.bulkLookupIPGeolocation(BulkLookupIPGeolocationRequest(ips: ["8.8.8.8"]))

        let captured = transport.requireLast()
        XCTAssertNil(captured.headers["Origin"], "Origin must not ride along with bulk; bulk only supports apiKey auth")
    }

    func test_singleLookup_sendsOriginWhenConfigured() async throws {
        let transport = MockTransport()
        transport.enqueue(statusCode: 200, body: "{}")

        let client = IPGeolocationClient(
            config: try IPGeolocationClientConfig(requestOrigin: "https://app.example.com"),
            transport: transport
        )

        _ = try await client.lookupIPGeolocation(LookupIPGeolocationRequest(ip: "8.8.8.8"))

        let captured = transport.requireLast()
        XCTAssertEqual(captured.headers["Origin"], "https://app.example.com")
    }

    func test_bulkLookup_preservesDuplicatesInBodyAndParsesMixedResults() async throws {
        let transport = MockTransport()
        transport.enqueue(statusCode: 200, body: TestFixtures.bulkMixed)

        let client = IPGeolocationClient(
            config: try IPGeolocationClientConfig(apiKey: "k"),
            transport: transport
        )

        let response = try await client.bulkLookupIPGeolocation(
            BulkLookupIPGeolocationRequest(ips: ["8.8.8.8", "1.1.1.1", "8.8.8.8"])
        )
        XCTAssertEqual(response.data.count, 3)

        let captured = transport.requireLast()
        XCTAssertEqual(captured.method, "POST")
        XCTAssertEqual(captured.headers["Content-Type"], "application/json")
        XCTAssertNotNil(captured.body)

        if let bodyData = captured.body {
            let parsed = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            XCTAssertEqual(parsed?["ips"] as? [String], ["8.8.8.8", "1.1.1.1", "8.8.8.8"])
        }
    }

    func test_apiError_nonSuccessStatusExtractsMessage() async throws {
        let transport = MockTransport()
        transport.enqueue(statusCode: 401, body: "{\"message\": \"Invalid API key\"}")

        let client = IPGeolocationClient(
            config: try IPGeolocationClientConfig(apiKey: "bad"),
            transport: transport
        )

        do {
            _ = try await client.lookupIPGeolocation(LookupIPGeolocationRequest(ip: "8.8.8.8"))
            XCTFail("expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error.kind, .unauthorized)
            XCTAssertEqual(error.statusCode, 401)
            XCTAssertEqual(error.message, "Invalid API key")
        }
    }

    func test_closeIsIdempotent() async throws {
        let transport = MockTransport()
        let client = IPGeolocationClient(
            config: try IPGeolocationClientConfig(apiKey: "k"),
            transport: transport
        )
        client.close()
        client.close()
        XCTAssertEqual(transport.closeCount, 1)
        XCTAssertTrue(client.isClosed)

        await assertValidationAsync("client is closed") {
            _ = try await client.lookupIPGeolocation()
        }
    }

    func test_closedClient_translatesTransportErrorToClientClosed() async throws {
        final class OneShotClosingTransport: HTTPTransport, @unchecked Sendable {
            nonisolated(unsafe) weak var client: IPGeolocationClient?
            func send(_ request: HTTPRequestData) async throws -> HTTPResponseData {
                // Simulate a concurrent close landing while the send is in
                // flight: close the client, then fail the send with a
                // transport-level error. executeWithMetrics must translate
                // this to ValidationError("client is closed").
                client?.close()
                throw TransportError("HTTP request was cancelled")
            }
            func close() {}
        }

        let transport = OneShotClosingTransport()
        let client = IPGeolocationClient(
            config: try IPGeolocationClientConfig(apiKey: "k"),
            transport: transport
        )
        transport.client = client

        do {
            _ = try await client.lookupIPGeolocation(LookupIPGeolocationRequest(ip: "8.8.8.8"))
            XCTFail("expected ValidationError")
        } catch let error as ValidationError {
            XCTAssertEqual(error.message, "client is closed")
        }
    }

    func test_concurrentLookupsWithCloseDoNotCrash() async throws {
        let transport = MockTransport()
        // Queue enough success stubs that any early winners succeed before the
        // close lands. Extra stubs are harmless because `close()` makes
        // subsequent lookups throw `ValidationError` before the transport is
        // asked for another stub.
        for _ in 0..<64 {
            transport.enqueue(statusCode: 200, body: "{\"ip\": \"8.8.8.8\"}")
        }

        let client = IPGeolocationClient(
            config: try IPGeolocationClientConfig(apiKey: "k"),
            transport: transport
        )

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<32 {
                group.addTask {
                    _ = try? await client.lookupIPGeolocation(LookupIPGeolocationRequest(ip: "8.8.8.8"))
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 1_000_000)
                client.close()
            }
        }

        XCTAssertTrue(client.isClosed)
        XCTAssertEqual(transport.closeCount, 1)

        await assertValidationAsync("client is closed") {
            _ = try await client.lookupIPGeolocation(LookupIPGeolocationRequest(ip: "8.8.8.8"))
        }
    }

    func test_metadata_readsFallbackSuccessfulRecordHeader() async throws {
        let transport = MockTransport()
        transport.enqueue(
            statusCode: 200,
            body: "{}",
            headers: ["X-Successful-Record": ["7"]]
        )

        let client = IPGeolocationClient(
            config: try IPGeolocationClientConfig(apiKey: "k"),
            transport: transport
        )

        let response = try await client.lookupIPGeolocation(LookupIPGeolocationRequest(ip: "8.8.8.8"))
        XCTAssertEqual(response.metadata.successfulRecords, 7)
    }

    func test_queryBuilder_omitsEmptyValues() {
        let query = QueryBuilder.build([
            ("apiKey", "k"),
            ("ip", ""),
            ("lang", nil),
        ])
        XCTAssertEqual(query, "?apiKey=k")
    }

    func test_queryBuilder_emptyPairsReturnEmptyString() {
        XCTAssertEqual(QueryBuilder.build([]), "")
    }

    func test_transport_surfacesTimeoutAsRequestTimeoutError() async throws {
        let transport = MockTransport()
        transport.enqueue(error: RequestTimeoutError("HTTP request timed out"))

        let client = IPGeolocationClient(
            config: try IPGeolocationClientConfig(apiKey: "k"),
            transport: transport
        )

        do {
            _ = try await client.lookupIPGeolocation(LookupIPGeolocationRequest(ip: "8.8.8.8"))
            XCTFail("expected RequestTimeoutError")
        } catch let error as RequestTimeoutError {
            XCTAssertTrue(error.message.contains("timed out"))
        }
    }

    func test_transport_surfacesTransportError() async throws {
        let transport = MockTransport()
        transport.enqueue(error: TransportError("connection refused"))

        let client = IPGeolocationClient(
            config: try IPGeolocationClientConfig(apiKey: "k"),
            transport: transport
        )

        do {
            _ = try await client.lookupIPGeolocation(LookupIPGeolocationRequest(ip: "8.8.8.8"))
            XCTFail("expected TransportError")
        } catch let error as TransportError {
            XCTAssertEqual(error.message, "connection refused")
        }
    }
}
