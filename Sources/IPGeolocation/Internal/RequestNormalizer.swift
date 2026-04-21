import Foundation

struct NormalizedLookupRequest {
    let ip: String?
    let lang: String?
    let include: [String]
    let fields: [String]
    let excludes: [String]
    let userAgent: String?
    let headers: [String: String]
    let output: ResponseFormat
}

struct NormalizedBulkLookupRequest {
    let ips: [String]
    let lang: String?
    let include: [String]
    let fields: [String]
    let excludes: [String]
    let userAgent: String?
    let headers: [String: String]
    let output: ResponseFormat
}

enum RequestNormalizer {
    static let bulkLimit: Int = 50_000

    static func normalizeLookup(_ request: LookupIPGeolocationRequest) throws -> NormalizedLookupRequest {
        NormalizedLookupRequest(
            ip: try normalizeIP(request.ip),
            lang: request.lang?.code,
            include: try normalizeTokenList(request.include, fieldName: "include"),
            fields: try normalizeTokenList(request.fields, fieldName: "fields"),
            excludes: try normalizeTokenList(request.excludes, fieldName: "excludes"),
            userAgent: try normalizeOptionalHeaderValue(request.userAgent, fieldName: "userAgent"),
            headers: try normalizeHeaders(request.headers),
            output: request.output
        )
    }

    static func normalizeBulk(_ request: BulkLookupIPGeolocationRequest) throws -> NormalizedBulkLookupRequest {
        if request.ips.isEmpty {
            throw ValidationError("ips must contain at least one IP address or domain")
        }
        if request.ips.count > bulkLimit {
            throw ValidationError("ips must not contain more than \(bulkLimit) entries")
        }

        var normalizedIPs: [String] = []
        normalizedIPs.reserveCapacity(request.ips.count)
        for rawValue in request.ips {
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                throw ValidationError("ips must not contain blank values")
            }
            if trimmed.containsCROrLF {
                throw ValidationError("ip must not contain CR or LF")
            }
            normalizedIPs.append(trimmed)
        }

        return NormalizedBulkLookupRequest(
            ips: normalizedIPs,
            lang: request.lang?.code,
            include: try normalizeTokenList(request.include, fieldName: "include"),
            fields: try normalizeTokenList(request.fields, fieldName: "fields"),
            excludes: try normalizeTokenList(request.excludes, fieldName: "excludes"),
            userAgent: try normalizeOptionalHeaderValue(request.userAgent, fieldName: "userAgent"),
            headers: try normalizeHeaders(request.headers),
            output: request.output
        )
    }

    static func normalizeIP(_ value: String?) throws -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if !value.isEmpty {
                throw ValidationError("ip must not be blank")
            }
            return nil
        }
        if trimmed.containsCROrLF {
            throw ValidationError("ip must not contain CR or LF")
        }
        return trimmed
    }

    static func normalizeTokenList(_ values: [String], fieldName: String) throws -> [String] {
        if values.isEmpty { return [] }

        var seen: Set<String> = []
        var result: [String] = []
        result.reserveCapacity(values.count)

        for raw in values {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                throw ValidationError("\(fieldName) must not contain blank values")
            }
            // The SDK serializes these lists as CSV query parameters. A
            // caller-supplied comma would split the token on the wire and
            // silently produce a different request. Reject commas so one
            // array element always maps to exactly one API token.
            if trimmed.contains(",") {
                throw ValidationError("\(fieldName) entries must not contain commas")
            }
            if trimmed.containsCROrLF {
                throw ValidationError("\(fieldName) entries must not contain CR or LF")
            }
            if !seen.insert(trimmed).inserted {
                continue
            }
            result.append(trimmed)
        }

        return result
    }

    static func normalizeOptionalHeaderValue(_ value: String?, fieldName: String) throws -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if !value.isEmpty {
                throw ValidationError("\(fieldName) must not be blank")
            }
            return nil
        }
        if trimmed.containsCROrLF {
            throw ValidationError("\(fieldName) must not contain CR or LF")
        }
        return trimmed
    }

    static func normalizeHeaders(_ headers: [String: String]) throws -> [String: String] {
        if headers.isEmpty { return [:] }

        var result: [String: String] = [:]
        result.reserveCapacity(headers.count)

        for (rawName, rawValue) in headers {
            let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedName.isEmpty {
                throw ValidationError("headers must not contain blank names")
            }
            if trimmedValue.isEmpty {
                throw ValidationError("headers must not contain blank values")
            }
            if trimmedName.containsCROrLF || trimmedValue.containsCROrLF {
                throw ValidationError("headers must not contain CR or LF")
            }

            result[canonicalHeaderName(trimmedName)] = trimmedValue
        }

        return result
    }

    static func canonicalHeaderName(_ name: String) -> String {
        var parts: [String] = []
        parts.reserveCapacity(4)
        for segment in name.split(separator: "-", omittingEmptySubsequences: false) {
            let lower = segment.lowercased()
            if lower.isEmpty {
                parts.append("")
                continue
            }
            parts.append(lower.prefix(1).uppercased() + lower.dropFirst())
        }
        return parts.joined(separator: "-")
    }
}
