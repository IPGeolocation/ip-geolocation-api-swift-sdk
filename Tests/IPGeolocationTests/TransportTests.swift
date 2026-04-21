import Foundation
import XCTest
@testable import IPGeolocation

final class TransportTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ChunkedStubURLProtocol.reset()
        BlockingStubURLProtocol.reset()
        RedirectingStubURLProtocol.reset()
    }

    override func tearDown() {
        ChunkedStubURLProtocol.reset()
        BlockingStubURLProtocol.reset()
        RedirectingStubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Streaming cap enforcement during body read

    func test_urlSessionTransport_rejectsOversizedBodyDuringStreaming() async throws {
        let session = makeStubSession(protocolClasses: [ChunkedStubURLProtocol.self])
        defer { session.invalidateAndCancel() }
        let transport = URLSessionHTTPTransport(session: session, maxResponseBodyBytes: 64)

        // Server tries to send 1 MiB in 32 KiB chunks. Transport must throw
        // on the first chunk that pushes the accumulated body past 64 bytes.
        let chunkSize = 32 * 1024
        let chunkCount = 32
        ChunkedStubURLProtocol.statusCode = 200
        ChunkedStubURLProtocol.headers = ["Content-Type": "application/octet-stream"]
        ChunkedStubURLProtocol.chunks = Array(repeating: Data(repeating: 0x41, count: chunkSize), count: chunkCount)

        let url = URL(string: "http://stream.test/oversize")!
        do {
            _ = try await transport.send(HTTPRequestData(url: url, method: "GET", headers: [:], body: nil))
            XCTFail("expected TransportError for oversized body")
        } catch let error as TransportError {
            XCTAssertTrue(error.message.contains("Response body exceeded max size"))
        }

        XCTAssertLessThan(
            ChunkedStubURLProtocol.chunksDelivered,
            chunkCount,
            "transport should have cancelled mid-stream instead of accepting every chunk"
        )
    }

    // MARK: - URLSession inactivity timeout surfaces as RequestTimeoutError

    func test_urlSessionTransport_inactivityTimeoutFiresWhenServerStalls() async throws {
        let session = makeStubSession(
            protocolClasses: [BlockingStubURLProtocol.self],
            requestTimeout: 0.5,
            resourceTimeout: 10
        )
        defer { session.invalidateAndCancel() }
        let transport = URLSessionHTTPTransport(session: session, maxResponseBodyBytes: 1024)

        BlockingStubURLProtocol.statusCode = 200
        BlockingStubURLProtocol.headers = ["Content-Type": "application/json"]
        BlockingStubURLProtocol.deliverInitialByte = true
        BlockingStubURLProtocol.blockBodyForever = true

        let url = URL(string: "http://stream.test/stall")!
        let started = Date()
        do {
            _ = try await transport.send(HTTPRequestData(url: url, method: "GET", headers: [:], body: nil))
            XCTFail("expected RequestTimeoutError")
        } catch is RequestTimeoutError {
            let elapsed = Date().timeIntervalSince(started)
            XCTAssertLessThan(elapsed, 3.0, "URLSession inactivity timer should fire close to requestTimeout=0.5s")
            XCTAssertGreaterThanOrEqual(elapsed, 0.3)
        } catch {
            XCTFail("expected RequestTimeoutError, got \(type(of: error)): \(error)")
        }
    }

    // MARK: - Invalid UTF-8 surfaces as SerializationError

    func test_urlSessionTransport_invalidUTF8BodyThrowsSerializationError() async throws {
        let session = makeStubSession(protocolClasses: [ChunkedStubURLProtocol.self])
        defer { session.invalidateAndCancel() }
        let transport = URLSessionHTTPTransport(session: session, maxResponseBodyBytes: 1024)

        ChunkedStubURLProtocol.statusCode = 200
        ChunkedStubURLProtocol.headers = ["Content-Type": "application/json"]
        // 0xC3 opens a two-byte UTF-8 sequence but 0x28 is not a continuation byte.
        ChunkedStubURLProtocol.chunks = [Data([0xC3, 0x28, 0xC3, 0x28])]

        let url = URL(string: "http://stream.test/bad-utf8")!
        do {
            _ = try await transport.send(HTTPRequestData(url: url, method: "GET", headers: [:], body: nil))
            XCTFail("expected SerializationError")
        } catch let error as SerializationError {
            XCTAssertTrue(error.message.contains("not valid UTF-8"))
        }
    }

    // MARK: - Generic NSError sanitization strips the API-key-bearing URL

    func test_sanitizedUnderlyingError_stripsFailingURLFromGenericNSError() {
        let secretURL = "https://api.ipgeolocation.io/v3/ipgeo?apiKey=supersecret&ip=8.8.8.8"
        let userInfo: [String: Any] = [
            NSURLErrorFailingURLErrorKey: URL(string: secretURL)!,
            NSURLErrorFailingURLStringErrorKey: secretURL,
            NSLocalizedDescriptionKey: "some other error",
        ]
        let genericError = NSError(domain: "com.example.custom", code: 42, userInfo: userInfo)

        let sanitized = URLSessionHTTPTransport.sanitizedUnderlyingError(from: genericError) as NSError
        let dumped = "\(sanitized) \(sanitized.userInfo)"
        XCTAssertFalse(dumped.contains("supersecret"))
        XCTAssertFalse(dumped.contains(secretURL))
        XCTAssertFalse(dumped.contains("apiKey"))
        XCTAssertEqual(sanitized.domain, "com.example.custom")
        XCTAssertEqual(sanitized.code, 42)
    }

    func test_sanitizedUnderlyingError_recursesIntoNSUnderlyingErrorKey() {
        let secretURL = "https://api.ipgeolocation.io/v3/ipgeo?apiKey=supersecret"
        let inner = NSError(
            domain: URLError.errorDomain,
            code: URLError.Code.cannotFindHost.rawValue,
            userInfo: [NSURLErrorFailingURLStringErrorKey: secretURL]
        )
        let outer = NSError(
            domain: "com.example.outer",
            code: 1,
            userInfo: [NSUnderlyingErrorKey: inner]
        )

        let sanitized = URLSessionHTTPTransport.sanitizedUnderlyingError(from: outer) as NSError
        let innerSanitized = sanitized.userInfo[NSUnderlyingErrorKey] as? NSError
        XCTAssertNotNil(innerSanitized)
        XCTAssertNil(innerSanitized?.userInfo[NSURLErrorFailingURLStringErrorKey])
    }

    // MARK: - URLError sanitization strips the API-key-bearing URL

    func test_sanitizedUnderlyingError_stripsFailingURL() {
        let secretURL = "https://api.ipgeolocation.io/v3/ipgeo?apiKey=supersecret&ip=8.8.8.8"
        let userInfo: [String: Any] = [
            NSURLErrorFailingURLErrorKey: URL(string: secretURL)!,
            NSURLErrorFailingURLStringErrorKey: secretURL,
            NSLocalizedDescriptionKey: "timed out",
        ]
        let urlError = URLError(.timedOut, userInfo: userInfo)

        let sanitized = URLSessionHTTPTransport.sanitizedUnderlyingError(from: urlError) as NSError
        let sanitizedUserInfo = sanitized.userInfo

        XCTAssertNil(sanitizedUserInfo[NSURLErrorFailingURLErrorKey])
        XCTAssertNil(sanitizedUserInfo[NSURLErrorFailingURLStringErrorKey])

        let dumped = "\(sanitized) \(sanitizedUserInfo)"
        XCTAssertFalse(dumped.contains("supersecret"))
        XCTAssertFalse(dumped.contains(secretURL))

        XCTAssertEqual(sanitized.domain, URLError.errorDomain)
        XCTAssertEqual(sanitized.code, URLError.Code.timedOut.rawValue)
        XCTAssertEqual(sanitizedUserInfo[NSLocalizedDescriptionKey] as? String, "timed out")

        XCTAssertFalse(sanitized.localizedDescription.contains("supersecret"))
        XCTAssertFalse(sanitized.localizedDescription.contains(secretURL))
        XCTAssertFalse(sanitized.localizedDescription.contains("apiKey"))
    }

    // MARK: - Redirect blocker keeps the API-key URL on the originating host

    func test_urlSessionTransport_rejectsRedirectInsteadOfFollowingToNewHost() async throws {
        // The SDK sends `apiKey` in the query string. If URLSession ever
        // started following a 30x to a new host or a downgraded http URL
        // the credential would leak. `RedirectBlocker` must stop that at
        // the delegate callback, and the transport must surface the 30x
        // response as-is so the caller sees an explicit failure instead
        // of a silent follow.
        let blocker = RedirectBlocker()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectingStubURLProtocol.self] + (configuration.protocolClasses ?? [])
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        let session = URLSession(configuration: configuration, delegate: blocker, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let transport = URLSessionHTTPTransport(session: session, maxResponseBodyBytes: 4096)

        RedirectingStubURLProtocol.redirectStatusCode = 301
        RedirectingStubURLProtocol.redirectLocation = "http://evil.test/secondary?apiKey=leaked"
        RedirectingStubURLProtocol.body = Data("original".utf8)

        let url = URL(string: "https://api.ipgeolocation.io/v3/ipgeo?apiKey=supersecret&ip=8.8.8.8")!
        let result = try await transport.send(HTTPRequestData(url: url, method: "GET", headers: [:], body: nil))

        XCTAssertEqual(result.statusCode, 301, "transport should surface the 30x instead of following it")
        XCTAssertEqual(
            RedirectingStubURLProtocol.secondaryRequestCount,
            0,
            "RedirectBlocker must prevent URLSession from issuing the follow-up request to the redirect target"
        )
    }

    // MARK: - Header normalization on success

    func test_urlSessionTransport_normalizesResponseHeaders() async throws {
        let session = makeStubSession(protocolClasses: [ChunkedStubURLProtocol.self])
        defer { session.invalidateAndCancel() }
        let transport = URLSessionHTTPTransport(session: session, maxResponseBodyBytes: 4096)

        ChunkedStubURLProtocol.statusCode = 200
        ChunkedStubURLProtocol.headers = [
            "x-credits-charged": "3",
            "content-type": "application/json",
        ]
        ChunkedStubURLProtocol.chunks = [Data("{\"ok\": true}".utf8)]

        let url = URL(string: "http://stream.test/headers")!
        let result = try await transport.send(HTTPRequestData(url: url, method: "GET", headers: [:], body: nil))
        XCTAssertEqual(result.statusCode, 200)
        XCTAssertEqual(result.headers["X-Credits-Charged"], ["3"])
        XCTAssertEqual(result.headers["Content-Type"], ["application/json"])
    }

    // MARK: - Helpers

    private func makeStubSession(
        protocolClasses: [AnyClass],
        requestTimeout: TimeInterval = 30,
        resourceTimeout: TimeInterval = 30
    ) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = protocolClasses + (configuration.protocolClasses ?? [])
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        return URLSession(configuration: configuration)
    }
}

// MARK: - Chunked URLProtocol stub

final class ChunkedStubURLProtocol: URLProtocol, @unchecked Sendable {
    static var statusCode: Int = 200
    static var headers: [String: String] = [:]
    static var chunks: [Data] = []
    static var chunksDelivered: Int = 0

    static func reset() {
        statusCode = 200
        headers = [:]
        chunks = []
        chunksDelivered = 0
    }

    private var cancelled = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let client = client else { return }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: Self.headers
        )!
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        for chunk in Self.chunks {
            if cancelled { return }
            client.urlProtocol(self, didLoad: chunk)
            Self.chunksDelivered += 1
            Thread.sleep(forTimeInterval: 0.01)
        }

        if !cancelled {
            client.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        cancelled = true
    }
}

// MARK: - Redirect URLProtocol stub

final class RedirectingStubURLProtocol: URLProtocol, @unchecked Sendable {
    static var redirectStatusCode: Int = 301
    static var redirectLocation: String = "http://evil.test/secondary"
    static var body: Data = Data()
    static var secondaryRequestCount: Int = 0
    private static let lock = NSLock()

    static func reset() {
        redirectStatusCode = 301
        redirectLocation = "http://evil.test/secondary"
        body = Data()
        secondaryRequestCount = 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let client = client else { return }

        if let host = request.url?.host, host != "api.ipgeolocation.io" {
            Self.lock.lock()
            Self.secondaryRequestCount += 1
            Self.lock.unlock()
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/plain"]
            )!
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: Data("followed".utf8))
            client.urlProtocolDidFinishLoading(self)
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.redirectStatusCode,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Location": Self.redirectLocation,
                "Content-Type": "text/plain",
            ]
        )!
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !Self.body.isEmpty {
            client.urlProtocol(self, didLoad: Self.body)
        }
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Blocking URLProtocol stub

final class BlockingStubURLProtocol: URLProtocol, @unchecked Sendable {
    static var statusCode: Int = 200
    static var headers: [String: String] = [:]
    static var blockBodyForever: Bool = true
    static var deliverInitialByte: Bool = true

    static func reset() {
        statusCode = 200
        headers = [:]
        blockBodyForever = true
        deliverInitialByte = true
    }

    private var cancelled = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let client = client else { return }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: Self.headers
        )!
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        if Self.deliverInitialByte {
            client.urlProtocol(self, didLoad: Data([0x7B]))
        }

        if Self.blockBodyForever {
            while !cancelled { Thread.sleep(forTimeInterval: 0.05) }
            return
        }

        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        cancelled = true
    }
}
