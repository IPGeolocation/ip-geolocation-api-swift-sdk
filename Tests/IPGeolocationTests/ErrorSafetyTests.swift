import Foundation
import XCTest
@testable import IPGeolocation

final class ErrorSafetyTests: XCTestCase {
    func test_underlyingErrorsRedactDescriptionsAndDiscardUnknownObjects() {
        let key = "fixture-secret-value"
        let nested = NSError(domain: "nested.\(key)", code: 7, userInfo: [
            NSLocalizedDescriptionKey: "Failed for \(key)",
            NSDebugDescriptionErrorKey: "https://example.test/?apiKey=\(key)",
            "metadata": [key: ["value": key]],
        ])
        let original = NSError(domain: "outer.\(key)", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "Request for \(key)",
            NSLocalizedFailureReasonErrorKey: "Reason \(key)",
            NSLocalizedRecoverySuggestionErrorKey: "Retry \(key)",
            NSUnderlyingErrorKey: nested,
            key: Data(key.utf8),
            NSURLErrorFailingURLErrorKey: URL(string: "https://example.test/?apiKey=\(key)")!,
        ])

        let copied = URLSessionHTTPTransport.sanitizedUnderlyingError(from: original, apiKey: key) as NSError
        XCTAssertFalse(copied === original)
        XCTAssertEqual(copied.code, 42)
        XCTAssertFalse("\(copied) \(copied.userInfo)".contains(key))
        XCTAssertTrue(copied.localizedDescription.contains("[REDACTED]"))
        XCTAssertNil(copied.userInfo[key])
        XCTAssertNil(copied.userInfo[NSURLErrorFailingURLErrorKey])
        let inner = copied.userInfo[NSUnderlyingErrorKey] as? NSError
        XCTAssertEqual(inner?.code, 7)
        XCTAssertNil(inner?.userInfo["metadata"])
        XCTAssertFalse(inner === nested)
    }

    func test_underlyingErrorCyclesAreBounded() {
        let error = CyclicDiagnosticError(domain: "fixture", code: 7)
        var current: NSError? = ErrorSanitizer.copyUnderlying(error, apiKey: "fixture-secret-value")
        var count = 0
        while let value = current {
            count += 1
            XCTAssertFalse(value === error)
            XCTAssertFalse(value.localizedDescription.contains("fixture-secret-value"))
            if count > 9 { XCTFail("Unbounded error chain"); break }
            current = value.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        XCTAssertLessThanOrEqual(count, 9)
    }

    func test_transportMappingRetainsTimeoutAndTransportTypes() {
        let key = "fixture-secret-value"
        for code in [URLError.timedOut, .cancelled, .cannotFindHost] {
            let error = URLError(code, userInfo: [NSLocalizedDescriptionKey: "Failed \(key)"])
            let mapped = URLSessionHTTPTransport.mapTransportError(error, apiKey: key)
            let underlying: Error?
            if code == .timedOut {
                XCTAssertTrue(mapped is RequestTimeoutError)
                underlying = (mapped as? RequestTimeoutError)?.underlyingError
            } else {
                XCTAssertTrue(mapped is TransportError)
                underlying = (mapped as? TransportError)?.underlyingError
            }
            XCTAssertEqual((underlying as NSError?)?.code, code.rawValue)
            XCTAssertFalse(String(describing: underlying).contains(key))
        }
    }

    func test_malformedJSONKeepsSerializationErrorWithoutTheKey() {
        let key = "fixture-secret-value"
        for body in ["{\"ip\":\"\(key)\"", "{\(key)}", "[{\"message\":\"\(key)\""] {
            for bulk in [false, true] {
                do {
                    if bulk { _ = try ResponseMapper.parseBulk(body, apiKey: key) }
                    else { _ = try ResponseMapper.parseSingle(body, apiKey: key) }
                    XCTFail("Expected SerializationError")
                } catch let error as SerializationError {
                    XCTAssertNotNil(error.underlyingError)
                    XCTAssertFalse("\(error) \(String(describing: error.underlyingError))".contains(key))
                } catch { XCTFail("Unexpected error type") }
            }
        }
    }
}

private final class CyclicDiagnosticError: NSError, @unchecked Sendable {
    override var userInfo: [String: Any] {
        [NSLocalizedDescriptionKey: "Failed fixture-secret-value", NSUnderlyingErrorKey: self]
    }
}
