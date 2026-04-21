import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct HTTPRequestData {
    let url: URL
    let method: String
    let headers: [String: String]
    let body: Data?
}

struct HTTPResponseData {
    let statusCode: Int
    let body: String
    let headers: [String: [String]]
}

protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequestData) async throws -> HTTPResponseData
    func close()
}

final class URLSessionHTTPTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession
    private let maxResponseBodyBytes: Int
    private let redirectBlocker: RedirectBlocker

    init(
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval,
        maxResponseBodyBytes: Int
    ) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = [:]
        let blocker = RedirectBlocker()
        self.redirectBlocker = blocker
        self.session = URLSession(
            configuration: configuration,
            delegate: blocker,
            delegateQueue: nil
        )
        self.maxResponseBodyBytes = maxResponseBodyBytes
    }

    init(session: URLSession, maxResponseBodyBytes: Int) {
        self.session = session
        self.maxResponseBodyBytes = maxResponseBodyBytes
        self.redirectBlocker = RedirectBlocker()
    }

    func close() {
        session.finishTasksAndInvalidate()
    }

    func send(_ request: HTTPRequestData) async throws -> HTTPResponseData {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        let bytesSequence: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytesSequence, response) = try await session.bytes(for: urlRequest)
        } catch {
            throw Self.mapTransportError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TransportError("HTTP transport error: unexpected non-HTTP response")
        }

        let headers = normalizeHeaders(httpResponse)
        let bodyData: Data
        do {
            bodyData = try await readBody(bytesSequence: bytesSequence)
        } catch let error as TransportError {
            throw error
        } catch let error as RequestTimeoutError {
            throw error
        } catch {
            throw Self.mapTransportError(error)
        }

        guard let bodyString = String(data: bodyData, encoding: .utf8) else {
            throw SerializationError("Response body was not valid UTF-8")
        }

        return HTTPResponseData(
            statusCode: httpResponse.statusCode,
            body: bodyString,
            headers: headers
        )
    }

    private func readBody(bytesSequence: URLSession.AsyncBytes) async throws -> Data {
        let cap = maxResponseBodyBytes
        var buffer = Data()
        buffer.reserveCapacity(min(cap, 64 * 1024))

        for try await byte in bytesSequence {
            buffer.append(byte)
            if buffer.count > cap {
                throw TransportError("Response body exceeded max size of \(cap) bytes")
            }
        }

        return buffer
    }

    private func normalizeHeaders(_ response: HTTPURLResponse) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for (rawKey, rawValue) in response.allHeaderFields {
            guard let name = rawKey as? String else { continue }
            let canonical = RequestNormalizer.canonicalHeaderName(name)
            let stringValue: String
            if let value = rawValue as? String {
                stringValue = value
            } else {
                stringValue = String(describing: rawValue)
            }
            result[canonical, default: []].append(stringValue)
        }
        return result
    }

    /// Maps any error thrown by `URLSession` into a typed SDK error. Every
    /// error chain is run through `sanitizedUnderlyingError` so URL-bearing
    /// NSError userInfo keys are stripped regardless of the concrete error
    /// type. Previously only `URLError` was sanitized; bare `NSError` and
    /// Swift errors bridged through NSError would slip through with the
    /// full request URL (including the `apiKey` query) attached.
    static func mapTransportError(_ error: Error) -> Error {
        let sanitized = sanitizedUnderlyingError(from: error)
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return RequestTimeoutError("HTTP request timed out", underlyingError: sanitized)
            case .cancelled:
                return TransportError("HTTP request was cancelled", underlyingError: sanitized)
            default:
                return TransportError("HTTP transport error", underlyingError: sanitized)
            }
        }
        return TransportError("HTTP transport error", underlyingError: sanitized)
    }

    /// Rebuilds an `NSError` without the URL-bearing keys so the API key,
    /// which is sent in the query string, does not leak into error chains
    /// consumers may log verbatim. Handles `URLError` and any other Error
    /// that bridges to `NSError` (which is every Swift error on Apple
    /// platforms). Recursively sanitizes nested underlying errors.
    static func sanitizedUnderlyingError(from error: Error) -> Error {
        let nsError = error as NSError
        var userInfo = nsError.userInfo
        var changed = false

        for key in urlBearingUserInfoKeys {
            if userInfo.removeValue(forKey: key) != nil {
                changed = true
            }
        }

        if let nested = userInfo[NSUnderlyingErrorKey] as? Error {
            let nestedSanitized = sanitizedUnderlyingError(from: nested)
            userInfo[NSUnderlyingErrorKey] = nestedSanitized
            changed = true
        } else if userInfo.removeValue(forKey: NSUnderlyingErrorKey) != nil {
            changed = true
        }

        if !changed { return error }

        return NSError(
            domain: nsError.domain,
            code: nsError.code,
            userInfo: userInfo
        )
    }

    private static let urlBearingUserInfoKeys: [String] = [
        NSURLErrorFailingURLErrorKey,
        NSURLErrorFailingURLStringErrorKey,
        NSURLErrorFailingURLPeerTrustErrorKey,
        "NSErrorFailingURLKey",
        "NSErrorFailingURLStringKey",
    ]
}

/// `URLSessionTaskDelegate` that rejects every HTTP redirect. The client
/// sends `apiKey` in the query string, so following a 30x to another host
/// (or a downgraded http URL) would leak the credential. Rejecting
/// redirects is the safest default for an API client with query-string auth;
/// consumers who need redirects can point `baseURL` at the final host.
final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
