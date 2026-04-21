import Foundation
import XCTest
@testable import IPGeolocation

final class MockTransport: HTTPTransport, @unchecked Sendable {
    struct Stub {
        var statusCode: Int = 200
        var body: String = "{}"
        var headers: [String: [String]] = [:]
        var error: Error?
        var delay: TimeInterval = 0
    }

    enum MockError: Error {
        case outOfStubs
    }

    private let lock = NSLock()
    private var stubs: [Stub] = []
    private(set) var capturedRequests: [HTTPRequestData] = []
    private(set) var closeCount: Int = 0

    func enqueue(_ stub: Stub) {
        lock.lock()
        stubs.append(stub)
        lock.unlock()
    }

    func enqueue(
        statusCode: Int = 200,
        body: String = "{}",
        headers: [String: [String]] = [:],
        error: Error? = nil,
        delay: TimeInterval = 0
    ) {
        enqueue(Stub(statusCode: statusCode, body: body, headers: headers, error: error, delay: delay))
    }

    func send(_ request: HTTPRequestData) async throws -> HTTPResponseData {
        lock.lock()
        capturedRequests.append(request)
        guard !stubs.isEmpty else {
            lock.unlock()
            throw MockError.outOfStubs
        }
        let stub = stubs.removeFirst()
        lock.unlock()

        if stub.delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(stub.delay * 1_000_000_000))
        }

        if let error = stub.error {
            throw error
        }

        var headers: [String: [String]] = [:]
        for (name, values) in stub.headers {
            headers[RequestNormalizer.canonicalHeaderName(name)] = values
        }
        return HTTPResponseData(statusCode: stub.statusCode, body: stub.body, headers: headers)
    }

    func close() {
        lock.lock()
        closeCount += 1
        lock.unlock()
    }

    func requireLast(file: StaticString = #file, line: UInt = #line) -> HTTPRequestData {
        lock.lock()
        defer { lock.unlock() }
        guard let last = capturedRequests.last else {
            XCTFail("MockTransport has no captured requests", file: file, line: line)
            return HTTPRequestData(url: URL(string: "about:blank")!, method: "GET", headers: [:], body: nil)
        }
        return last
    }
}

enum TestFixtures {
    static let singleLookup: String = """
    {
      "ip": "8.8.8.8",
      "hostname": "dns.google",
      "domain": "google.com",
      "location": {
        "continent_code": "NA",
        "continent_name": "North America",
        "country_code2": "US",
        "country_code3": "USA",
        "country_name": "United States",
        "country_name_official": "United States of America",
        "country_capital": "Washington, D.C.",
        "state_prov": "California",
        "state_code": "US-CA",
        "district": "Santa Clara County",
        "city": "Mountain View",
        "locality": "Mountain View",
        "accuracy_radius": "10",
        "confidence": "high",
        "dma_code": "807",
        "zipcode": "94043",
        "latitude": "37.4056",
        "longitude": "-122.0775",
        "is_eu": false,
        "country_flag": "https://example.test/us.svg",
        "geoname_id": "5375480",
        "country_emoji": "\u{1F1FA}\u{1F1F8}"
      },
      "country_metadata": {
        "calling_code": "+1",
        "tld": ".us",
        "languages": ["en-US", "es-US"]
      },
      "currency": {"code": "USD", "name": "US Dollar", "symbol": "$"},
      "network": {
        "connection_type": "Corporate",
        "route": "8.8.8.0/24",
        "is_anycast": true
      },
      "asn": {
        "as_number": "AS15169",
        "organization": "Google LLC",
        "country": "US",
        "type": "Content",
        "domain": "google.com",
        "date_allocated": "2000-03-30",
        "rir": "ARIN"
      },
      "company": {"name": "Google LLC", "type": "Business", "domain": "google.com"},
      "time_zone": {
        "name": "America/Los_Angeles",
        "offset": -8.0,
        "offset_with_dst": -7.0,
        "current_time": "2026-04-18T10:00:00-07:00",
        "current_time_unix": 1745000000.0,
        "current_tz_abbreviation": "PDT",
        "current_tz_full_name": "Pacific Daylight Time",
        "standard_tz_abbreviation": "PST",
        "standard_tz_full_name": "Pacific Standard Time",
        "is_dst": true,
        "dst_savings": 1.0,
        "dst_exists": true,
        "dst_tz_abbreviation": "PDT",
        "dst_tz_full_name": "Pacific Daylight Time",
        "dst_start": {
          "utc_time": "2026-03-08T10:00:00Z",
          "duration": "+1H",
          "gap": true,
          "date_time_after": "2026-03-08T03:00:00-07:00",
          "date_time_before": "2026-03-08T02:00:00-08:00",
          "overlap": false
        },
        "dst_end": {
          "utc_time": "2026-11-01T09:00:00Z",
          "duration": "-1H",
          "gap": false,
          "date_time_after": "2026-11-01T01:00:00-08:00",
          "date_time_before": "2026-11-01T02:00:00-07:00",
          "overlap": true
        }
      },
      "security": {
        "threat_score": 0.1,
        "is_tor": false,
        "is_proxy": false,
        "proxy_provider_names": [],
        "proxy_confidence_score": 0.0,
        "is_vpn": false,
        "vpn_provider_names": [],
        "vpn_confidence_score": 0.0,
        "is_relay": false,
        "is_anonymous": false,
        "is_known_attacker": false,
        "is_bot": false,
        "is_spam": false,
        "is_cloud_provider": true,
        "cloud_provider_name": "Google Cloud"
      },
      "abuse": {
        "route": "8.8.8.0/24",
        "country": "US",
        "name": "Google LLC",
        "organization": "Google LLC",
        "kind": "network",
        "address": "1600 Amphitheatre Parkway",
        "emails": ["abuse@google.com"],
        "phone_numbers": ["+1-650-253-0000"]
      },
      "user_agent": {
        "user_agent_string": "Mozilla/5.0",
        "name": "Safari",
        "type": "Browser",
        "version": "9.0.2",
        "version_major": "9",
        "device": {"name": "Desktop", "type": "desktop", "brand": "Apple", "cpu": "Intel"},
        "engine": {"name": "AppleWebKit", "type": "Browser", "version": "601.3.9", "version_major": "601"},
        "operating_system": {"name": "macOS", "version": "10.11.2", "version_major": "10"}
      }
    }
    """

    static let bulkMixed: String = """
    [
      {
        "ip": "8.8.8.8",
        "location": {"country_name": "United States"}
      },
      {"message": "Invalid IP address"},
      {"error": {"message": "rate limited"}}
    ]
    """
}

func assertValidation(
    _ expectedMessage: String,
    file: StaticString = #file,
    line: UInt = #line,
    _ body: () throws -> Void
) {
    do {
        try body()
        XCTFail("expected ValidationError(\"\(expectedMessage)\") to be thrown", file: file, line: line)
    } catch let error as ValidationError {
        XCTAssertEqual(error.message, expectedMessage, file: file, line: line)
    } catch {
        XCTFail("expected ValidationError but got \(type(of: error)): \(error)", file: file, line: line)
    }
}

func assertValidationAsync(
    _ expectedMessage: String,
    file: StaticString = #file,
    line: UInt = #line,
    _ body: () async throws -> Void
) async {
    do {
        try await body()
        XCTFail("expected ValidationError(\"\(expectedMessage)\") to be thrown", file: file, line: line)
    } catch let error as ValidationError {
        XCTAssertEqual(error.message, expectedMessage, file: file, line: line)
    } catch {
        XCTFail("expected ValidationError but got \(type(of: error)): \(error)", file: file, line: line)
    }
}
