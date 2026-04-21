import XCTest
@testable import IPGeolocation

final class ConfigTests: XCTestCase {
    func test_defaultConfig_acceptsAPIKey() throws {
        let config = try IPGeolocationClientConfig(apiKey: "abc123")
        XCTAssertEqual(config.apiKey, "abc123")
        XCTAssertNil(config.requestOrigin)
        XCTAssertEqual(config.baseURL, "https://api.ipgeolocation.io")
        XCTAssertEqual(config.requestTimeout, 10)
        XCTAssertEqual(config.resourceTimeout, 30)
    }

    func test_apiKey_trimsWhitespace() throws {
        let config = try IPGeolocationClientConfig(apiKey: "  abc  ")
        XCTAssertEqual(config.apiKey, "abc")
    }

    func test_apiKey_blankStringRejected() {
        assertValidation("apiKey must not be blank") {
            _ = try IPGeolocationClientConfig(apiKey: "   ")
        }
    }

    func test_requestOrigin_acceptsAbsoluteHTTPS() throws {
        let config = try IPGeolocationClientConfig(requestOrigin: "https://app.example.com")
        XCTAssertEqual(config.requestOrigin, "https://app.example.com")
    }

    func test_requestOrigin_acceptsPortAndStripsTrailingSlash() throws {
        let config = try IPGeolocationClientConfig(requestOrigin: "https://app.example.com:8443/")
        XCTAssertEqual(config.requestOrigin, "https://app.example.com:8443")
    }

    func test_requestOrigin_rejectsPath() {
        assertValidation("requestOrigin must not include a path") {
            _ = try IPGeolocationClientConfig(requestOrigin: "https://app.example.com/path")
        }
    }

    func test_requestOrigin_rejectsScheme() {
        assertValidation("requestOrigin must be an absolute http or https origin") {
            _ = try IPGeolocationClientConfig(requestOrigin: "ftp://example.com")
        }
    }

    func test_requestOrigin_rejectsUserinfo() {
        assertValidation("requestOrigin must not include userinfo") {
            _ = try IPGeolocationClientConfig(requestOrigin: "https://user:pass@example.com")
        }
    }

    func test_requestOrigin_rejectsQuery() {
        assertValidation("requestOrigin must not include query or fragment") {
            _ = try IPGeolocationClientConfig(requestOrigin: "https://example.com?x=1")
        }
    }

    func test_requestOrigin_rejectsCRLF() {
        assertValidation("requestOrigin must not contain CR or LF") {
            _ = try IPGeolocationClientConfig(requestOrigin: "https://examp\rle.com")
        }
        assertValidation("requestOrigin must not contain CR or LF") {
            _ = try IPGeolocationClientConfig(requestOrigin: "https://examp\nle.com")
        }
        assertValidation("requestOrigin must not contain CR or LF") {
            _ = try IPGeolocationClientConfig(requestOrigin: "https://examp\r\nle.com")
        }
    }

    func test_baseURL_blankRejected() {
        assertValidation("baseURL must not be blank") {
            _ = try IPGeolocationClientConfig(apiKey: "k", baseURL: "   ")
        }
    }

    func test_baseURL_rejectsNonHTTPScheme() {
        assertValidation("baseURL must be an absolute http or https URL") {
            _ = try IPGeolocationClientConfig(apiKey: "k", baseURL: "wss://example.com")
        }
    }

    func test_baseURL_trimsTrailingSlash() throws {
        let config = try IPGeolocationClientConfig(apiKey: "k", baseURL: "https://api.example.com/")
        XCTAssertEqual(config.baseURL, "https://api.example.com")
    }

    func test_baseURL_rejectsUserinfo() {
        assertValidation("baseURL must not include userinfo") {
            _ = try IPGeolocationClientConfig(apiKey: "k", baseURL: "https://u:p@api.example.com")
        }
    }

    func test_baseURL_rejectsQuery() {
        assertValidation("baseURL must not include query or fragment") {
            _ = try IPGeolocationClientConfig(apiKey: "k", baseURL: "https://api.example.com?x=1")
        }
    }

    func test_baseURL_rejectsFragment() {
        assertValidation("baseURL must not include query or fragment") {
            _ = try IPGeolocationClientConfig(apiKey: "k", baseURL: "https://api.example.com#frag")
        }
    }

    func test_baseURL_rejectsCRLF() {
        assertValidation("baseURL must not contain CR or LF") {
            _ = try IPGeolocationClientConfig(apiKey: "k", baseURL: "https://api.exa\rmple.com")
        }
        assertValidation("baseURL must not contain CR or LF") {
            _ = try IPGeolocationClientConfig(apiKey: "k", baseURL: "https://api.exa\nmple.com")
        }
        assertValidation("baseURL must not contain CR or LF") {
            _ = try IPGeolocationClientConfig(apiKey: "k", baseURL: "https://api.exa\r\nmple.com")
        }
    }

    func test_baseURL_rejectsHTTPByDefault() {
        do {
            _ = try IPGeolocationClientConfig(apiKey: "k", baseURL: "http://api.example.com")
            XCTFail("expected ValidationError for http baseURL")
        } catch let error as ValidationError {
            XCTAssertTrue(error.message.contains("baseURL must use https"))
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_baseURL_acceptsHTTPWhenAllowInsecureHTTPIsTrue() throws {
        let config = try IPGeolocationClientConfig(
            apiKey: "k",
            baseURL: "http://localhost:8080",
            allowInsecureHTTP: true
        )
        XCTAssertEqual(config.baseURL, "http://localhost:8080")
        XCTAssertTrue(config.allowInsecureHTTP)
    }

    func test_baseURL_httpsAcceptedWithOrWithoutFlag() throws {
        let withoutFlag = try IPGeolocationClientConfig(apiKey: "k", baseURL: "https://api.example.com")
        XCTAssertEqual(withoutFlag.baseURL, "https://api.example.com")
        XCTAssertFalse(withoutFlag.allowInsecureHTTP)

        let withFlag = try IPGeolocationClientConfig(
            apiKey: "k",
            baseURL: "https://api.example.com",
            allowInsecureHTTP: true
        )
        XCTAssertEqual(withFlag.baseURL, "https://api.example.com")
    }

    func test_requestOrigin_wrapsIPv6HostInBrackets() throws {
        let ipv6 = try IPGeolocationClientConfig(requestOrigin: "https://[2001:db8::1]:8443/")
        XCTAssertEqual(ipv6.requestOrigin, "https://[2001:db8::1]:8443")

        let ipv6NoPort = try IPGeolocationClientConfig(requestOrigin: "https://[2001:db8::1]")
        XCTAssertEqual(ipv6NoPort.requestOrigin, "https://[2001:db8::1]")
    }

    func test_requestTimeout_mustBePositive() {
        assertValidation("requestTimeout must be greater than zero") {
            _ = try IPGeolocationClientConfig(apiKey: "k", requestTimeout: 0)
        }
    }

    func test_resourceTimeout_mustBePositive() {
        assertValidation("resourceTimeout must be greater than zero") {
            _ = try IPGeolocationClientConfig(apiKey: "k", resourceTimeout: -1)
        }
    }

    func test_requestTimeoutMustBeLessThanOrEqualToResourceTimeout() {
        assertValidation("requestTimeout must be <= resourceTimeout") {
            _ = try IPGeolocationClientConfig(apiKey: "k", requestTimeout: 60, resourceTimeout: 30)
        }
    }

    func test_maxResponseBodyBytes_mustBePositive() {
        assertValidation("maxResponseBodyBytes must be greater than zero") {
            _ = try IPGeolocationClientConfig(apiKey: "k", maxResponseBodyBytes: 0)
        }
    }

    func test_safeDescription_redactsAPIKey() throws {
        let config = try IPGeolocationClientConfig(apiKey: "secret")
        XCTAssertEqual(config.safeDescription()["apiKey"], "[REDACTED]")
    }

    func test_safeDescription_omitsAPIKeyWhenNil() throws {
        let config = try IPGeolocationClientConfig(requestOrigin: "https://app.example.com")
        XCTAssertEqual(config.safeDescription()["apiKey"], "nil")
    }

    func test_description_doesNotExposeAPIKey() throws {
        let config = try IPGeolocationClientConfig(apiKey: "supersecret")
        XCTAssertFalse(config.description.contains("supersecret"))
        XCTAssertTrue(config.description.contains("[REDACTED]"))
    }

    func test_customMirror_redactsAPIKey() throws {
        let config = try IPGeolocationClientConfig(apiKey: "supersecret")
        let mirror = Mirror(reflecting: config)
        let apiKeyChild = mirror.children.first(where: { $0.label == "apiKey" })
        XCTAssertNotNil(apiKeyChild)
        XCTAssertEqual("\(apiKeyChild!.value)", "[REDACTED]")

        var dumpedOutput = ""
        dump(config, to: &dumpedOutput)
        XCTAssertFalse(dumpedOutput.contains("supersecret"))
        XCTAssertTrue(dumpedOutput.contains("[REDACTED]"))
    }
}
