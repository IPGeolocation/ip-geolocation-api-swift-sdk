import Foundation
import XCTest
@testable import IPGeolocation

final class JSONOutputTests: XCTestCase {
    func test_compactOmitsNilFields() throws {
        var response = IPGeolocationResponse()
        response.ip = "8.8.8.8"
        var location = Location()
        location.countryName = "United States"
        response.location = location

        let compact = try JSONOutput.toJSON(response)
        let object = try parse(compact)
        XCTAssertEqual(object["ip"] as? String, "8.8.8.8")
        XCTAssertNil(object["time_zone"])
        let nested = object["location"] as? [String: Any]
        XCTAssertEqual(nested?["country_name"] as? String, "United States")
        XCTAssertNil(nested?["city"])
    }

    func test_fullIncludesNilFieldsAsNull() throws {
        let response = IPGeolocationResponse()
        let full = try JSONOutput.toJSON(response, mode: .full)
        let object = try parse(full)
        XCTAssertTrue(object["ip"] is NSNull)
        XCTAssertTrue(object["location"] is NSNull)
    }

    func test_prettyProducesMultipleLines() throws {
        var response = IPGeolocationResponse()
        response.ip = "8.8.8.8"
        let pretty = try JSONOutput.toPrettyJSON(response)
        XCTAssertTrue(pretty.contains("\n"))
        XCTAssertTrue(pretty.contains("\"ip\""))
    }

    func test_snakeCasedAcronyms() throws {
        var security = Security()
        security.isVPN = true
        var response = IPGeolocationResponse()
        response.security = security

        let compact = try JSONOutput.toJSON(response)
        let object = try parse(compact)
        let sec = object["security"] as? [String: Any]
        XCTAssertEqual(sec?["is_vpn"] as? Bool, true)
    }

    func test_arraysPreserveOrder() throws {
        var country = CountryMetadata()
        country.languages = ["en-US", "es-US"]
        var response = IPGeolocationResponse()
        response.countryMetadata = country

        let compact = try JSONOutput.toJSON(response)
        let object = try parse(compact)
        let countryMetadata = object["country_metadata"] as? [String: Any]
        XCTAssertEqual(countryMetadata?["languages"] as? [String], ["en-US", "es-US"])
    }

    func test_camelToSnakeCase_handlesAcronyms() {
        XCTAssertEqual(JSONOutput.camelToSnakeCase("isEU"), "is_eu")
        XCTAssertEqual(JSONOutput.camelToSnakeCase("isVPN"), "is_vpn")
        XCTAssertEqual(JSONOutput.camelToSnakeCase("isDST"), "is_dst")
        XCTAssertEqual(JSONOutput.camelToSnakeCase("offsetWithDST"), "offset_with_dst")
        XCTAssertEqual(JSONOutput.camelToSnakeCase("currentTZ"), "current_tz")
        XCTAssertEqual(JSONOutput.camelToSnakeCase("currentTZAbbreviation"), "current_tz_abbreviation")
        XCTAssertEqual(JSONOutput.camelToSnakeCase("standardTZFullName"), "standard_tz_full_name")
        XCTAssertEqual(JSONOutput.camelToSnakeCase("userAgentString"), "user_agent_string")
        XCTAssertEqual(JSONOutput.camelToSnakeCase("asNumber"), "as_number")
        XCTAssertEqual(JSONOutput.camelToSnakeCase("vpnProviderNames"), "vpn_provider_names")
    }

    func test_camelToSnakeCase_handlesSimpleCases() {
        XCTAssertEqual(JSONOutput.camelToSnakeCase(""), "")
        XCTAssertEqual(JSONOutput.camelToSnakeCase("a"), "a")
        XCTAssertEqual(JSONOutput.camelToSnakeCase("ip"), "ip")
        XCTAssertEqual(JSONOutput.camelToSnakeCase("countryName"), "country_name")
        XCTAssertEqual(JSONOutput.camelToSnakeCase("countryISO"), "country_iso")
    }

    private func parse(_ json: String) throws -> [String: Any] {
        guard let data = json.data(using: .utf8) else {
            throw SerializationError("could not decode utf8")
        }
        let parsed = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return parsed as? [String: Any] ?? [:]
    }
}
