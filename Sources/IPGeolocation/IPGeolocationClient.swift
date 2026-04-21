import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Main client for the IPGeolocation.io IP Location API.
///
/// Homepage: https://ipgeolocation.io
///
/// IP Location API: https://ipgeolocation.io/ip-location-api.html
///
/// Documentation: https://ipgeolocation.io/documentation/ip-location-api.html
public final class IPGeolocationClient: @unchecked Sendable {
    private let config: IPGeolocationClientConfig
    private let transport: HTTPTransport
    private let stateLock = NSLock()
    private var closedState: Bool = false

    public convenience init(config: IPGeolocationClientConfig) {
        let transport = URLSessionHTTPTransport(
            requestTimeout: config.requestTimeout,
            resourceTimeout: config.resourceTimeout,
            maxResponseBodyBytes: config.maxResponseBodyBytes
        )
        self.init(config: config, transport: transport)
    }

    init(config: IPGeolocationClientConfig, transport: HTTPTransport) {
        self.config = config
        self.transport = transport
    }

    public static func defaultUserAgent() -> String {
        SDKVersion.defaultUserAgent()
    }

    public func close() {
        stateLock.lock()
        defer { stateLock.unlock() }
        if closedState { return }
        closedState = true
        transport.close()
    }

    public var isClosed: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return closedState
    }

    public func lookupIPGeolocation(
        _ request: LookupIPGeolocationRequest = LookupIPGeolocationRequest()
    ) async throws -> APIResponse<IPGeolocationResponse> {
        try ensureOpen()
        try ensureSingleLookupConfigured()
        let normalized = try RequestNormalizer.normalizeLookup(request)
        try validateJSONOutput(normalized.output)
        let data = try buildLookupHTTPRequest(normalized)
        let execution = try await executeWithMetrics(data)
        try ensureSuccessfulStatus(execution.response)
        let parsed = try ResponseMapper.parseSingle(execution.response.body)
        return APIResponse(data: parsed, metadata: metadata(from: execution))
    }

    public func lookupIPGeolocationRaw(
        _ request: LookupIPGeolocationRequest = LookupIPGeolocationRequest()
    ) async throws -> APIResponse<String> {
        try ensureOpen()
        try ensureSingleLookupConfigured()
        let normalized = try RequestNormalizer.normalizeLookup(request)
        let data = try buildLookupHTTPRequest(normalized)
        let execution = try await executeWithMetrics(data)
        try ensureSuccessfulStatus(execution.response)
        return APIResponse(data: execution.response.body, metadata: metadata(from: execution))
    }

    public func bulkLookupIPGeolocation(
        _ request: BulkLookupIPGeolocationRequest
    ) async throws -> APIResponse<[BulkLookupResult]> {
        try ensureOpen()
        try ensureBulkLookupConfigured()
        let normalized = try RequestNormalizer.normalizeBulk(request)
        try validateJSONOutput(normalized.output)
        let data = try buildBulkHTTPRequest(normalized)
        let execution = try await executeWithMetrics(data)
        try ensureSuccessfulStatus(execution.response)
        let parsed = try ResponseMapper.parseBulk(execution.response.body, apiKey: config.apiKey)
        return APIResponse(data: parsed, metadata: metadata(from: execution))
    }

    public func bulkLookupIPGeolocationRaw(
        _ request: BulkLookupIPGeolocationRequest
    ) async throws -> APIResponse<String> {
        try ensureOpen()
        try ensureBulkLookupConfigured()
        let normalized = try RequestNormalizer.normalizeBulk(request)
        let data = try buildBulkHTTPRequest(normalized)
        let execution = try await executeWithMetrics(data)
        try ensureSuccessfulStatus(execution.response)
        return APIResponse(data: execution.response.body, metadata: metadata(from: execution))
    }

    private func buildLookupHTTPRequest(_ request: NormalizedLookupRequest) throws -> HTTPRequestData {
        let query = QueryBuilder.build([
            ("apiKey", config.apiKey),
            ("ip", request.ip),
            ("lang", request.lang),
            ("include", request.include.isEmpty ? nil : request.include.joined(separator: ",")),
            ("fields", request.fields.isEmpty ? nil : request.fields.joined(separator: ",")),
            ("excludes", request.excludes.isEmpty ? nil : request.excludes.joined(separator: ",")),
            ("output", request.output.wireValue),
        ])

        guard let url = URL(string: config.baseURL + "/v3/ipgeo" + query) else {
            throw ValidationError("failed to construct request URL from baseURL and query parameters")
        }

        let headers = resolveHeaders(
            requestHeaders: request.headers,
            userAgent: request.userAgent,
            output: request.output,
            includeContentType: false,
            includeOrigin: true
        )

        return HTTPRequestData(url: url, method: "GET", headers: headers, body: nil)
    }

    private func buildBulkHTTPRequest(_ request: NormalizedBulkLookupRequest) throws -> HTTPRequestData {
        let bodyObject: [String: Any] = ["ips": request.ips]
        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: bodyObject, options: [])
        } catch {
            throw SerializationError("Failed to serialize bulk lookup request body", underlyingError: error)
        }

        let query = QueryBuilder.build([
            ("apiKey", config.apiKey),
            ("lang", request.lang),
            ("include", request.include.isEmpty ? nil : request.include.joined(separator: ",")),
            ("fields", request.fields.isEmpty ? nil : request.fields.joined(separator: ",")),
            ("excludes", request.excludes.isEmpty ? nil : request.excludes.joined(separator: ",")),
            ("output", request.output.wireValue),
        ])

        guard let url = URL(string: config.baseURL + "/v3/ipgeo-bulk" + query) else {
            throw ValidationError("failed to construct request URL from baseURL and query parameters")
        }

        let headers = resolveHeaders(
            requestHeaders: request.headers,
            userAgent: request.userAgent,
            output: request.output,
            includeContentType: true,
            includeOrigin: false
        )

        return HTTPRequestData(url: url, method: "POST", headers: headers, body: body)
    }

    private func resolveHeaders(
        requestHeaders: [String: String],
        userAgent: String?,
        output: ResponseFormat,
        includeContentType: Bool,
        includeOrigin: Bool
    ) -> [String: String] {
        var headers: [String: String] = [:]

        for (name, value) in requestHeaders {
            headers[name] = value
        }

        headers["User-Agent"] = resolveUserAgent(userAgent: userAgent, requestHeaders: requestHeaders)
        headers["Accept"] = output.acceptHeader

        // The Origin header backs request-origin auth, which the API only
        // supports on `/v3/ipgeo`. Bulk lookups always require `apiKey`, so
        // sending Origin on bulk would be a docs mismatch and could confuse
        // proxies or access logs. Callers pass `includeOrigin: false` for
        // bulk to keep the header strictly scoped to single lookup.
        if includeOrigin, let origin = config.requestOrigin {
            headers["Origin"] = origin
        }

        if includeContentType {
            headers["Content-Type"] = "application/json"
        }

        return headers
    }

    private func resolveUserAgent(userAgent: String?, requestHeaders: [String: String]) -> String {
        if let explicit = userAgent, !explicit.isEmpty {
            return explicit
        }
        if let fromHeaders = requestHeaders["User-Agent"], !fromHeaders.isEmpty {
            return fromHeaders
        }
        return SDKVersion.defaultUserAgent()
    }

    private func executeWithMetrics(_ request: HTTPRequestData) async throws -> ExecutionResult {
        // `systemUptime` is monotonic (seconds since boot). Using it instead of
        // `Date()` means the reported duration can't go negative or jump if the
        // wall clock is adjusted by NTP mid-request.
        let startedAt = ProcessInfo.processInfo.systemUptime
        do {
            let response = try await transport.send(request)
            let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
            let durationMs = Int((elapsed * 1000).rounded())
            return ExecutionResult(response: response, durationMs: durationMs)
        } catch {
            // If a concurrent `close()` invalidated the session while this send
            // was in flight, the transport error is really a "client closed"
            // signal from the consumer's perspective. Translate it so error
            // handling can match on the typed ValidationError instead of a
            // generic TransportError. `isClosed` is a sync property so it is
            // safe to read from this async catch.
            if isClosed && (error is TransportError || error is RequestTimeoutError) {
                throw ValidationError("client is closed")
            }
            throw error
        }
    }

    private func ensureOpen() throws {
        stateLock.lock()
        let closed = closedState
        stateLock.unlock()
        if closed {
            throw ValidationError("client is closed")
        }
    }

    private func ensureSingleLookupConfigured() throws {
        if config.apiKey == nil && config.requestOrigin == nil {
            throw ValidationError("single lookup requires apiKey or requestOrigin in client config")
        }
    }

    private func ensureBulkLookupConfigured() throws {
        if config.apiKey == nil {
            throw ValidationError("bulk lookup requires apiKey in client config")
        }
    }

    private func validateJSONOutput(_ output: ResponseFormat) throws {
        if output != .json {
            throw ValidationError("typed methods support JSON only")
        }
    }

    private func ensureSuccessfulStatus(_ response: HTTPResponseData) throws {
        if (200...299).contains(response.statusCode) { return }
        throw APIErrorFactory.make(
            statusCode: response.statusCode,
            body: response.body,
            apiKey: config.apiKey
        )
    }

    private func metadata(from execution: ExecutionResult) -> ResponseMetadata {
        ResponseMetadata(
            statusCode: execution.response.statusCode,
            durationMs: execution.durationMs,
            creditsCharged: parseIntHeader(execution.response.headers, "X-Credits-Charged"),
            successfulRecords: parseIntHeader(execution.response.headers, "X-Successful-Records")
                ?? parseIntHeader(execution.response.headers, "X-Successful-Record"),
            rawHeaders: execution.response.headers
        )
    }

    private func parseIntHeader(_ headers: [String: [String]], _ name: String) -> Int? {
        let canonical = RequestNormalizer.canonicalHeaderName(name)
        guard let values = headers[canonical], let first = values.first else { return nil }
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        guard trimmed.allSatisfy({ $0 == "-" || ("0"..."9").contains($0) }) else { return nil }
        return Int(trimmed)
    }
}

private struct ExecutionResult {
    let response: HTTPResponseData
    let durationMs: Int
}
