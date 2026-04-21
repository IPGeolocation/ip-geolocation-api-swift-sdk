import Foundation
import XCTest
@testable import IPGeolocation

final class LiveFieldParityTests: XCTestCase {
    func test_live_includeStarResponseMatchesTypedModel() async throws {
        try await assertSingleLookupParity(
            LookupIPGeolocationRequest(ip: "8.8.8.8", include: ["*"])
        )
    }

    func test_live_geoAccuracyAndDMAResponseMatchesTypedModel() async throws {
        try await assertSingleLookupParity(
            LookupIPGeolocationRequest(ip: "8.8.8.8", include: ["geo_accuracy", "dma_code"])
        )
    }

    func test_live_domainLookupWithHostnameFallbackLiveMatchesTypedModel() async throws {
        try await assertSingleLookupParity(
            LookupIPGeolocationRequest(ip: "ipgeolocation.io", include: ["hostnameFallbackLive"])
        )
    }

    func test_live_securityAbuseAndUserAgentResponseMatchesTypedModel() async throws {
        try await assertSingleLookupParity(
            LookupIPGeolocationRequest(
                ip: "8.8.8.8",
                include: ["security", "abuse", "user_agent"],
                userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_2) AppleWebKit/601.3.9 (KHTML, like Gecko) Version/9.0.2 Safari/601.3.9"
            )
        )
    }

    func test_live_filteredSecurityResponseMatchesTypedModel() async throws {
        try await assertSingleLookupParity(
            LookupIPGeolocationRequest(
                ip: "8.8.8.8",
                include: ["security"],
                fields: ["location.city", "security.threat_score", "security.is_vpn"]
            )
        )
    }

    func test_live_filteredCountryMetadataResponseMatchesTypedModel() async throws {
        try await assertSingleLookupParity(
            LookupIPGeolocationRequest(
                ip: "8.8.8.8",
                fields: ["country_metadata.calling_code"]
            )
        )
    }

    func test_live_bulkIncludeStarResponseMatchesTypedModel() async throws {
        try await assertBulkLookupParity(
            BulkLookupIPGeolocationRequest(ips: ["8.8.8.8", "1.1.1.1"], include: ["*"])
        )
    }

    func test_live_bulkMixedResponseMatchesTypedModel() async throws {
        try await assertBulkLookupParity(
            BulkLookupIPGeolocationRequest(ips: ["8.8.8.8", "not-a-valid-ip", "1.1.1.1"])
        )
    }

    func test_live_bulkFilteredSecurityResponseMatchesTypedModel() async throws {
        try await assertBulkLookupParity(
            BulkLookupIPGeolocationRequest(
                ips: ["8.8.8.8", "1.1.1.1"],
                include: ["security"],
                fields: ["location.city", "security.threat_score", "security.is_vpn"]
            )
        )
    }

    private func assertSingleLookupParity(
        _ request: LookupIPGeolocationRequest,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws {
        let paidKey = try LiveTestGuard.requireLiveFieldParity()
        let client = IPGeolocationClient(config: try IPGeolocationClientConfig(apiKey: paidKey))
        defer { client.close() }

        let raw = try await client.lookupIPGeolocationRaw(request)
        let typed = try await client.lookupIPGeolocation(request)

        let rawNode = try parseJSON(raw.data)
        let typedNode = try parseJSON(JSONOutput.toJSON(typed.data))
        assertJSONSubset(rawNode, typedNode, path: "$", file: file, line: line)
    }

    private func assertBulkLookupParity(
        _ request: BulkLookupIPGeolocationRequest,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws {
        let paidKey = try LiveTestGuard.requireLiveFieldParity()
        let client = IPGeolocationClient(config: try IPGeolocationClientConfig(apiKey: paidKey))
        defer { client.close() }

        let raw = try await client.bulkLookupIPGeolocationRaw(request)
        let typed = try await client.bulkLookupIPGeolocation(request)

        let rawNode = try parseJSON(raw.data)
        guard let rawArray = rawNode as? [Any] else {
            XCTFail("bulk raw response should be a JSON array", file: file, line: line)
            return
        }
        XCTAssertEqual(typed.data.count, rawArray.count, "bulk item count", file: file, line: line)

        for (index, rawItem) in rawArray.enumerated() {
            let path = "$[\(index)]"
            let typedItem = typed.data[index]

            if typedItem.isSuccess {
                guard let typedData = typedItem.data else {
                    XCTFail("\(path) typed success must have data", file: file, line: line)
                    continue
                }
                // Some bulk responses wrap the payload under a `data` key.
                var rawPayload = rawItem
                if let rawObject = rawItem as? [String: Any],
                   let nested = rawObject["data"] {
                    rawPayload = nested
                }
                let typedPayload = try parseJSON(JSONOutput.toJSON(typedData))
                assertJSONSubset(rawPayload, typedPayload, path: path, file: file, line: line)
            } else {
                guard let rawObject = rawItem as? [String: Any] else {
                    XCTFail("\(path) raw error item should be an object", file: file, line: line)
                    continue
                }
                let rawMessage = (rawObject["message"] as? String)
                    ?? ((rawObject["error"] as? [String: Any])?["message"] as? String)
                    ?? (rawObject["error"] as? String)
                XCTAssertNotNil(rawMessage, "\(path) raw error should expose a message", file: file, line: line)
                XCTAssertEqual(typedItem.error?.message, rawMessage, path, file: file, line: line)
            }
        }
    }

    /// Recursive raw-vs-typed JSON comparison. The raw node is the source of
    /// truth; every field the API returned must survive the typed round-trip.
    /// Mirrors the Python, Ruby, and C++ sister SDKs so field-level drift in
    /// any one language is caught by the same shape of assertion.
    private func assertJSONSubset(
        _ rawNode: Any?,
        _ typedNode: Any?,
        path: String,
        file: StaticString,
        line: UInt
    ) {
        if isJSONNull(rawNode) {
            XCTAssertTrue(isJSONNull(typedNode), "\(path) should be null or absent", file: file, line: line)
            return
        }

        XCTAssertFalse(isJSONNull(typedNode), "\(path) should be present in typed response", file: file, line: line)

        // `time_zone.current_time` and `current_time_unix` drift between the
        // raw and typed reads because the API stamps a fresh clock value on
        // each call. Presence is asserted above; value comparison is skipped.
        if isLiveClockField(path) {
            return
        }

        if let rawDict = rawNode as? [String: Any] {
            guard let typedDict = typedNode as? [String: Any] else {
                XCTFail("\(path) should be an object", file: file, line: line)
                return
            }
            for (key, rawValue) in rawDict {
                let childPath = path + "." + key
                if typedDict[key] == nil && isOmittableEmptyObject(rawValue, path: childPath) {
                    continue
                }
                XCTAssertNotNil(typedDict[key], "\(childPath) missing in typed response", file: file, line: line)
                assertJSONSubset(rawValue, typedDict[key], path: childPath, file: file, line: line)
            }
            return
        }

        if let rawArray = rawNode as? [Any] {
            guard let typedArray = typedNode as? [Any] else {
                XCTFail("\(path) should be an array", file: file, line: line)
                return
            }
            XCTAssertEqual(typedArray.count, rawArray.count, "\(path) size", file: file, line: line)
            for (index, rawItem) in rawArray.enumerated() {
                let indexed = typedArray.indices.contains(index) ? typedArray[index] : nil
                assertJSONSubset(rawItem, indexed, path: "\(path)[\(index)]", file: file, line: line)
            }
            return
        }

        if let rawBool = asBool(rawNode) {
            guard let typedBool = asBool(typedNode) else {
                XCTFail("\(path) should be boolean", file: file, line: line)
                return
            }
            XCTAssertEqual(typedBool, rawBool, path, file: file, line: line)
            return
        }

        if let rawNumber = asNumber(rawNode) {
            guard let typedNumber = asNumber(typedNode) else {
                XCTFail("\(path) should be numeric", file: file, line: line)
                return
            }
            // Use string round-trip so the numeric literals the typed model
            // emits (e.g. `8.0`) compare equal to whatever the API emitted,
            // without losing precision on floats the way a plain `==` can.
            XCTAssertEqual(
                Decimal(string: String(describing: typedNumber)),
                Decimal(string: String(describing: rawNumber)),
                path,
                file: file,
                line: line
            )
            return
        }

        if let rawString = rawNode as? String {
            guard let typedString = typedNode as? String else {
                XCTFail("\(path) should be a string", file: file, line: line)
                return
            }
            XCTAssertEqual(typedString, rawString, path, file: file, line: line)
            return
        }

        XCTFail("\(path) has unsupported type \(type(of: rawNode as Any))", file: file, line: line)
    }

    private func parseJSON(_ body: String) throws -> Any {
        guard let data = body.data(using: .utf8) else {
            throw SerializationError("parity: body is not UTF-8")
        }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private func isJSONNull(_ node: Any?) -> Bool {
        node == nil || node is NSNull
    }

    private func isLiveClockField(_ path: String) -> Bool {
        path.hasSuffix(".time_zone.current_time") || path.hasSuffix(".time_zone.current_time_unix")
    }

    private func isOmittableEmptyObject(_ rawNode: Any, path: String) -> Bool {
        guard path.hasSuffix(".time_zone.dst_start") || path.hasSuffix(".time_zone.dst_end") else {
            return false
        }
        if let dict = rawNode as? [String: Any] {
            return dict.isEmpty
        }
        return rawNode is NSNull
    }

    /// NSNumber bridges booleans and numbers to the same type in
    /// `JSONSerialization` output. Use the underlying Objective-C type code
    /// to pick booleans apart from numeric 0/1.
    private func asBool(_ node: Any?) -> Bool? {
        guard let node else { return nil }
        if let number = node as? NSNumber, String(cString: number.objCType) == "c" {
            return number.boolValue
        }
        return nil
    }

    private func asNumber(_ node: Any?) -> NSNumber? {
        guard let node else { return nil }
        guard let number = node as? NSNumber else { return nil }
        if String(cString: number.objCType) == "c" {
            return nil
        }
        return number
    }
}
