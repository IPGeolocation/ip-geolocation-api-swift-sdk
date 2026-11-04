import Foundation
import XCTest
@testable import IPGeolocation

final class LanguageCompatibilityTests: XCTestCase {
    func test_existingEnumRemainsExhaustive() {
        func code(_ language: Language) -> String {
            switch language {
            case .en: return "en"
            case .de: return "de"
            case .ru: return "ru"
            case .ja: return "ja"
            case .fr: return "fr"
            case .cn: return "cn"
            case .es: return "es"
            case .cs: return "cs"
            case .it: return "it"
            case .ko: return "ko"
            case .fa: return "fa"
            case .pt: return "pt"
            }
        }
        XCTAssertEqual(Language.allCases.map(code), Language.allCases.map(\.rawValue))
    }

    func test_existingInitializerReferencesRemainAvailable() {
        let single: (String?, Language?, [String], [String], [String], String?, [String: String], ResponseFormat) -> LookupIPGeolocationRequest = LookupIPGeolocationRequest.init
        let bulk: ([String], Language?, [String], [String], [String], String?, [String: String], ResponseFormat) -> BulkLookupIPGeolocationRequest = BulkLookupIPGeolocationRequest.init
        XCTAssertEqual(single("8.8.8.8", .fr, [], [], [], nil, [:], .json).lang, .fr)
        XCTAssertEqual(bulk(["8.8.8.8"], .de, [], [], [], nil, [:], .json).lang, .de)
    }

    func test_languageCodesValidateAndOverrideEnumForBothRequests() throws {
        for code in Language.allCases.map(\.rawValue) + ["ar"] {
            var single = LookupIPGeolocationRequest(lang: .de)
            var bulk = BulkLookupIPGeolocationRequest(ips: ["8.8.8.8"], lang: .de)
            single.languageCode = code
            bulk.languageCode = code
            XCTAssertEqual(try RequestNormalizer.normalizeLookup(single).lang, code)
            XCTAssertEqual(try RequestNormalizer.normalizeBulk(bulk).lang, code)
            single.lang = .fr
            bulk.lang = .fr
            XCTAssertEqual(try RequestNormalizer.normalizeLookup(single).lang, code)
            XCTAssertEqual(try RequestNormalizer.normalizeBulk(bulk).lang, code)
            single.languageCode = nil
            bulk.languageCode = nil
            XCTAssertEqual(try RequestNormalizer.normalizeLookup(single).lang, "fr")
            XCTAssertEqual(try RequestNormalizer.normalizeBulk(bulk).lang, "fr")
        }
        for code in ["", "AR", " ar ", "xx", "ar\r\nX-Test: injected", "ar&apiKey=other"] {
            var single = LookupIPGeolocationRequest()
            var bulk = BulkLookupIPGeolocationRequest(ips: ["8.8.8.8"])
            single.languageCode = code
            bulk.languageCode = code
            XCTAssertThrowsError(try single.validate()) { XCTAssertTrue($0 is ValidationError) }
            XCTAssertThrowsError(try bulk.validate()) { XCTAssertTrue($0 is ValidationError) }
        }
    }

    func test_arabicIsSentByTypedAndRawSingleAndBulkMethods() async throws {
        let transport = MockTransport()
        transport.enqueue(body: "{\"ip\":\"8.8.8.8\",\"location\":{\"country_name\":\"الولايات المتحدة\"}}")
        transport.enqueue(body: "[{\"ip\":\"8.8.8.8\"}]")
        transport.enqueue(body: "<response>العربية</response>")
        transport.enqueue(body: "<response>العربية</response>")
        let client = IPGeolocationClient(config: try IPGeolocationClientConfig(apiKey: "fixture-key"), transport: transport)
        defer { client.close() }
        var single = LookupIPGeolocationRequest(ip: "8.8.8.8")
        var bulk = BulkLookupIPGeolocationRequest(ips: ["8.8.8.8"])
        single.languageCode = "ar"
        bulk.languageCode = "ar"
        let result = try await client.lookupIPGeolocation(single)
        XCTAssertEqual(result.data.location?.countryName, "الولايات المتحدة")
        _ = try await client.bulkLookupIPGeolocation(bulk)
        single.output = .xml
        bulk.output = .xml
        _ = try await client.lookupIPGeolocationRaw(single)
        _ = try await client.bulkLookupIPGeolocationRaw(bulk)
        for request in transport.capturedRequests {
            XCTAssertEqual(URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "lang" }?.value, "ar")
        }
        XCTAssertEqual(transport.capturedRequests.count, 4)
    }
}
