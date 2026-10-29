# IPGeolocation Swift SDK

Official Swift SDK for the IPGeolocation.io IP Geolocation API.

Look up IPv4, IPv6, and domains with `/v3/ipgeo` and `/v3/ipgeo-bulk`. Get geolocation, company, ASN, timezone, network, hostname, abuse, user-agent, currency, and security data from one API.

- Swift Package targeting Swift 5.9, macOS 12+, iOS 15+, tvOS 15+, and watchOS 8+
- Typed JSON responses plus raw JSON and XML methods
- Built on `URLSession` with no third-party dependencies

## Table of Contents

- [Install](#install)
- [Quick Start](#quick-start)
- [At a Glance](#at-a-glance)
- [Get Your API Key](#get-your-api-key)
- [Authentication](#authentication)
- [Plan Behavior](#plan-behavior)
- [Client Configuration](#client-configuration)
- [Available Methods](#available-methods)
- [Request Options](#request-options)
- [JSON Keys and Swift Names](#json-keys-and-swift-names)
- [Examples](#examples)
- [Response Metadata](#response-metadata)
- [JSON Helpers](#json-helpers)
- [Errors](#errors)
- [Troubleshooting](#troubleshooting)
- [Frequently Asked Questions](#frequently-asked-questions)
- [Links](#links)

## Install

Add the package to your Swift Package Manager dependencies.

Swift Package Manifest:

```swift
.package(
    url: "https://github.com/IPGeolocation/ip-geolocation-api-swift-sdk.git",
    from: "1.0.0"
)
```

Then add `IPGeolocation` to your target's dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "IPGeolocation", package: "ip-geolocation-api-swift-sdk"),
    ]
)
```

Xcode: in **File → Add Package Dependencies…**, enter the repository URL and pick the latest `1.x` release.

Package page: <https://github.com/IPGeolocation/ip-geolocation-api-swift-sdk>

All public types live in the `IPGeolocation` module. Xcode will import the types you use in the examples below automatically.

## Quick Start

```swift
import Foundation
import IPGeolocation

struct MissingAPIKey: Error {}

func lookupExample() async throws {
    guard let apiKey = ProcessInfo.processInfo.environment["IPGEO_API_KEY"] else {
        throw MissingAPIKey()
    }

    let client = IPGeolocationClient(
        config: try IPGeolocationClientConfig(apiKey: apiKey)
    )
    defer { client.close() }

    let response = try await client.lookupIPGeolocation(
        LookupIPGeolocationRequest(ip: "8.8.8.8")
    )

    print(response.data.ip ?? "-")                          // 8.8.8.8
    print(response.data.location?.countryName ?? "-")       // United States
    print(response.data.location?.city ?? "-")
    print(response.data.timeZone?.name ?? "-")
    print(response.metadata.creditsCharged ?? 0)
}
```

You can also call `lookupIPGeolocation()` with no request object to resolve the caller IP.

## At a Glance

| Item | Value |
|------|-------|
| Product | Swift Package |
| Module | `IPGeolocation` |
| Supported Endpoints | `/v3/ipgeo`, `/v3/ipgeo-bulk` |
| Supported Inputs | IPv4, IPv6, domain |
| Main Data Returned | Geolocation, company, ASN, timezone, network, hostname, abuse, user-agent, currency, security |
| Authentication | API key, request-origin auth for `/v3/ipgeo` only |
| Response Formats | Typed JSON, raw JSON, raw XML |
| Bulk Limit | Up to 50,000 IPs or domains per request |
| Transport | Foundation `URLSession` |

## Get Your API Key

Create an IPGeolocation account and copy an API key from your dashboard.

1. Sign up: <https://app.ipgeolocation.io/signup>
2. Verify your email if prompted
3. Sign in: <https://app.ipgeolocation.io/login>
4. Open your dashboard: <https://app.ipgeolocation.io/dashboard>
5. Copy an API key from the `API Keys` section

For server-side Swift code, keep the API key in an environment variable or a secret manager. For browser-based single lookups on paid plans, use request-origin auth instead of exposing an API key in frontend code.

## Authentication

### API Key

```swift
import Foundation
import IPGeolocation

let apiKey = ProcessInfo.processInfo.environment["IPGEO_API_KEY"] ?? ""
let client = IPGeolocationClient(
    config: try IPGeolocationClientConfig(apiKey: apiKey)
)
```

If `IPGEO_API_KEY` is missing, `IPGeolocationClientConfig` throws `ValidationError("apiKey must not be blank")` so the failure stays typed instead of crashing the host app.

### Request-Origin Auth

```swift
let client = IPGeolocationClient(
    config: try IPGeolocationClientConfig(
        requestOrigin: "https://app.example.com"
    )
)
```

`requestOrigin` must be an absolute `http` or `https` origin with no path, query string, fragment, or userinfo.

> [!IMPORTANT]
> Request-origin auth does not work with `/v3/ipgeo-bulk`. Bulk lookup always requires `apiKey`.

> [!NOTE]
> If you set both `apiKey` and `requestOrigin`, single lookup still uses the API key. The API key is sent as the `apiKey` query parameter, so avoid logging full request URLs.

## Plan Behavior

Feature availability depends on your plan and request parameters.

| Capability | Free | Paid |
|------------|------|------|
| Single IPv4 and IPv6 lookup | Supported | Supported |
| Domain lookup | Not supported | Supported |
| Bulk lookup | Not supported | Supported |
| Non-English `lang` | Not supported | Supported |
| Request-origin auth | Not supported | Supported for `/v3/ipgeo` only |
| Optional modules via `include` | Not supported | Supported |
| `include: ["*"]` | Base response only | All plan-available modules |

Paid plans still need `include` for optional modules. `fields` and `excludes` only trim the response. They do not turn modules on or unlock paid data.

## Client Configuration

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `apiKey` | `String?` | unset | Required for bulk lookup. Optional for single lookup if `requestOrigin` is set. |
| `requestOrigin` | `String?` | unset | Must be an absolute `http` or `https` origin with no path, query string, fragment, or userinfo. |
| `baseURL` | `String` | `https://api.ipgeolocation.io` | Override the API base URL. |
| `requestTimeout` | `TimeInterval` | `10` | Maximum time `URLSession` will wait for new data on an in-flight request (connect, headers, or inter-chunk body inactivity). Must be greater than zero and less than or equal to `resourceTimeout`. Maps to `URLSessionConfiguration.timeoutIntervalForRequest`. |
| `resourceTimeout` | `TimeInterval` | `30` | Maximum total time for the entire request. Must be greater than zero. Maps to `URLSessionConfiguration.timeoutIntervalForResource`. |
| `maxResponseBodyBytes` | `Int` | `33554432` | Maximum response body size. The SDK enforces this while streaming the body and throws `TransportError` as soon as the limit is exceeded. Must be greater than zero. |
| `allowInsecureHTTP` | `Bool` | `false` | Off by default. The SDK sends `apiKey` in the query string, so `http://` would transmit it in plaintext. Set to `true` only for local testing or a trusted proxy where you have accepted the risk. |

Config values are validated when the config is built. The initializer throws `ValidationError` on invalid input. Request values are validated before each request is sent.

`URLSession` does not expose a connect-only timer, so the SDK uses `URLSession`'s native two-knob model: `requestTimeout` is the inactivity timer that also fires on a stalled body read, and `resourceTimeout` caps the total time. This is honest about the behavior you actually get on iOS and macOS.

## Available Methods

| Method | Returns | Notes |
|--------|---------|-------|
| `lookupIPGeolocation(_:)` | `APIResponse<IPGeolocationResponse>` | Single lookup. Typed JSON response. |
| `lookupIPGeolocationRaw(_:)` | `APIResponse<String>` | Single lookup. Raw JSON or XML string. |
| `bulkLookupIPGeolocation(_:)` | `APIResponse<[BulkLookupResult]>` | Bulk lookup. Typed JSON response. |
| `bulkLookupIPGeolocationRaw(_:)` | `APIResponse<String>` | Bulk lookup. Raw JSON or XML string. |
| `close()` | `Void` | Idempotent. Finishes in-flight tasks and invalidates the session. |
| `IPGeolocationClient.defaultUserAgent()` | `String` | Returns the SDK default outbound `User-Agent` header value. |

> [!NOTE]
> Typed methods support JSON only. Use the raw methods when you need XML output.

## Request Options

| Field | Applies To | Notes |
|-------|------------|-------|
| `ip` | Single lookup | IPv4, IPv6, or domain. Leave it `nil` for caller IP lookup. |
| `ips` | Bulk lookup | Array of 1 to 50,000 IPs or domains. |
| `lang` | Single and bulk | `Language.en`, `.de`, `.ru`, `.ja`, `.fr`, `.cn`, `.es`, `.cs`, `.it`, `.ko`, `.fa`, `.pt`. |
| `include` | Single and bulk | Array of module names such as `security`, `abuse`, `user_agent`, `hostname`, `liveHostname`, `hostnameFallbackLive`, `geo_accuracy`, `dma_code`, or `*`. |
| `fields` | Single and bulk | Array of field paths to keep, for example `location.country_name` or `security.threat_score`. |
| `excludes` | Single and bulk | Array of field paths to remove from the response. |
| `userAgent` | Single and bulk | Overrides the outbound `User-Agent` header. |
| `headers` | Single and bulk | Extra request headers. Header names are normalized to canonical case. |
| `output` | Single and bulk | `.json` or `.xml`. Typed methods require `.json`. |

## JSON Keys and Swift Names

The API returns JSON keys such as `country_metadata` and `calling_code`.
In Swift code, the SDK uses `countryMetadata` and `callingCode`.

The data is the same. Only the names you use in Swift change.

| API JSON key | Swift name |
|--------------|------------|
| `country_metadata` | `response.data.countryMetadata` |
| `calling_code` | `response.data.countryMetadata?.callingCode` |
| `time_zone` | `response.data.timeZone` |
| `current_tz_abbreviation` | `response.data.timeZone?.currentTZAbbreviation` |
| `is_eu` | `response.data.location?.isEU` |
| `user_agent` | `response.data.userAgent` |
| `version_major` | `response.data.userAgent?.versionMajor` |

Example:

```json
{
  "country_metadata": {
    "calling_code": "+46"
  },
  "time_zone": {
    "current_tz_abbreviation": "CET"
  },
  "location": {
    "is_eu": true
  }
}
```

```swift
print(response.data.countryMetadata?.callingCode ?? "-")
print(response.data.timeZone?.currentTZAbbreviation ?? "-")
print(response.data.location?.isEU ?? false)
```

There are two different places where names show up:

- In Swift code, use the names shown by the SDK, such as `response.data.countryMetadata?.callingCode`
- In request parameters, use the API names from the documentation

`include` example:

```swift
let response = try await client.lookupIPGeolocation(
    LookupIPGeolocationRequest(
        ip: "8.8.8.8",
        include: ["user_agent"]
    )
)

print(response.data.userAgent?.name ?? "-")
```

`fields` example:

```swift
let response = try await client.lookupIPGeolocation(
    LookupIPGeolocationRequest(
        ip: "8.8.8.8",
        fields: ["country_metadata.calling_code"]
    )
)

print(response.data.countryMetadata?.callingCode ?? "-")
```

`excludes` example:

```swift
let response = try await client.lookupIPGeolocation(
    LookupIPGeolocationRequest(
        ip: "8.8.8.8",
        excludes: ["time_zone.current_tz_abbreviation"]
    )
)

print(response.data.timeZone?.currentTZAbbreviation ?? "-")
```

More request-parameter examples:
- `include: ["security", "abuse"]`
- `include: ["hostnameFallbackLive"]`
- `fields: ["country_metadata.calling_code"]`
- `fields: ["time_zone.current_tz_abbreviation"]`
- `excludes: ["location.is_eu"]`

## Examples

The examples below assume you already have a configured client in scope:

```swift
import Foundation
import IPGeolocation

let apiKey = ProcessInfo.processInfo.environment["IPGEO_API_KEY"] ?? ""
let client = IPGeolocationClient(
    config: try IPGeolocationClientConfig(apiKey: apiKey)
)
```

### Caller IP

Leave `ip` empty to look up the public IP of the machine making the request.

```swift
let response = try await client.lookupIPGeolocation()
print(response.data.ip ?? "-")
```

### Domain Lookup

Domain lookup is a paid-plan feature.

```swift
let response = try await client.lookupIPGeolocation(
    LookupIPGeolocationRequest(ip: "ipgeolocation.io")
)

print(response.data.domain ?? "-")                    // ipgeolocation.io
print(response.data.location?.countryName ?? "-")
```

### Security and Abuse

```swift
let response = try await client.lookupIPGeolocation(
    LookupIPGeolocationRequest(
        ip: "9.9.9.9",
        include: ["security", "abuse"]
    )
)

print(response.data.security?.threatScore ?? 0)
print(response.data.abuse?.emails?.first ?? "-")
```

### User-Agent Parsing

To parse a visitor user-agent string, pass `include: ["user_agent"]` and set the `userAgent` field on the request. The SDK uses it as the outbound `User-Agent` header, and the API parses it and returns the result in `response.data.userAgent`.

```swift
let visitorUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_2) AppleWebKit/601.3.9 (KHTML, like Gecko) Version/9.0.2 Safari/601.3.9"

let response = try await client.lookupIPGeolocation(
    LookupIPGeolocationRequest(
        ip: "115.240.90.163",
        include: ["user_agent"],
        userAgent: visitorUA
    )
)

print(response.data.userAgent?.name ?? "-")
print(response.data.userAgent?.operatingSystem?.name ?? "-")
```

> [!NOTE]
> The `userAgent` request field overrides the SDK's default outbound `User-Agent` header. It also takes precedence over `headers["User-Agent"]` if both are set.
> `response.data.userAgent` is different. That field is the parsed visitor user-agent data returned by the API.

### Filtered Response

```swift
let response = try await client.lookupIPGeolocation(
    LookupIPGeolocationRequest(
        ip: "8.8.8.8",
        include: ["security"],
        fields: [
            "location.country_name",
            "security.threat_score",
            "security.is_vpn",
        ],
        excludes: ["currency"]
    )
)

print(response.data.location?.countryName ?? "-")
print(response.data.security?.isVPN ?? false)
print(response.data.currency == nil)
```

### Raw XML

```swift
let response = try await client.lookupIPGeolocationRaw(
    LookupIPGeolocationRequest(ip: "8.8.8.8", output: .xml)
)

print(response.data)
```

### Bulk Lookup

```swift
let response = try await client.bulkLookupIPGeolocation(
    BulkLookupIPGeolocationRequest(ips: ["8.8.8.8", "1.1.1.1"])
)

for result in response.data {
    if result.isSuccess {
        print(result.data?.ip ?? "-")
    } else {
        print(result.error?.message ?? "-")
    }
}
```

### Raw Bulk JSON

```swift
let response = try await client.bulkLookupIPGeolocationRaw(
    BulkLookupIPGeolocationRequest(ips: ["8.8.8.8", "1.1.1.1"])
)

print(response.data)
```

## Response Metadata

Every method returns `APIResponse<T>`, where:

- `data` contains the typed object or raw response string
- `metadata` contains response details such as:
  - `creditsCharged`
  - `successfulRecords`
  - `statusCode`
  - `durationMs`
  - `rawHeaders`

Example:

```swift
print(response.metadata.statusCode)
print(response.metadata.durationMs)
print(response.metadata.firstHeaderValue("content-type") ?? "-")
```

## JSON Helpers

Use `JSONOutput` for logs, debugging, or CLI output.

| Method | Notes |
|--------|-------|
| `JSONOutput.toJSON(value)` | Compact JSON. Omits `nil` fields. |
| `JSONOutput.toJSON(value, mode: .full)` | Includes `nil` fields as `null`. |
| `JSONOutput.toPrettyJSON(value)` | Pretty-printed compact JSON. |
| `JSONOutput.toPrettyJSON(value, mode: .full)` | Pretty-printed full JSON. |

Example:

```swift
let compact = try JSONOutput.toPrettyJSON(response.data)
let full = try JSONOutput.toPrettyJSON(response.data, mode: .full)

print(compact)
print(full)
```

## Errors

All SDK errors conform to the `IPGeolocationError` protocol.

| Error Type | When it happens |
|------------|-----------------|
| `ValidationError` | Invalid config, invalid request values, or typed XML request |
| `RequestTimeoutError` | Request or resource timeout |
| `TransportError` | Network or transport failure |
| `SerializationError` | Request or response serialization failure |
| `APIError` | API returned a non-2xx response |

`APIError` exposes:

- `statusCode`
- `message`
- `apiMessage`
- `kind` (`APIErrorKind`, which covers `.badRequest`, `.unauthorized`, `.forbidden`, `.notFound`, `.methodNotAllowed`, `.contentTooLarge`, `.unsupportedMediaType`, `.locked`, `.tooManyRequests`, `.clientClosedRequest`, `.internalServerError`, `.other`)

Example:

```swift
do {
    _ = try await client.lookupIPGeolocation(
        LookupIPGeolocationRequest(ip: "8.8.8.8", output: .xml)
    )
} catch let error as ValidationError {
    print(error.message)
}
```

## Troubleshooting

- Bulk lookup always requires `apiKey`. `requestOrigin` is not enough.
- Typed methods only support JSON. Use the raw methods for XML.
- If you need security, abuse, user-agent, or hostname data, include those modules explicitly.
- `fields` and `excludes` filter the response. They do not unlock paid data.
- `requestOrigin` must be an origin only. Do not include a path, query string, fragment, or userinfo.
- Response fields are optional so omitted fields stay omitted.
- `requestTimeout` must be less than or equal to `resourceTimeout`.
- The SDK rejects responses larger than `maxResponseBodyBytes`. The default cap is `32 MiB`.

## Frequently Asked Questions

<details>
<summary>Can I use this SDK without an API key?</summary>
Only for single lookup with paid-plan request-origin auth. Bulk lookup always requires an API key.
</details>

<details>
<summary>Can I request XML and still get typed models?</summary>
No. Typed methods only support JSON. Use `lookupIPGeolocationRaw` or `bulkLookupIPGeolocationRaw` for XML.
</details>

<details>
<summary>Why are many response fields optional?</summary>
Optional fields let the SDK preserve omitted fields instead of inventing default values for data the API did not send.
</details>

<details>
<summary>Does the SDK support async/await?</summary>
Yes. All request methods are `async throws`. The SDK targets platforms that support Swift Concurrency (macOS 12+, iOS 15+, tvOS 15+, watchOS 8+).
</details>

<details>
<summary>Does domain lookup work on the free plan?</summary>
No. Domain lookup is a paid-plan feature.
</details>

## Links

- Homepage: <https://ipgeolocation.io>
- IP Geolocation API product page: <https://ipgeolocation.io/ip-location-api.html>
- Documentation: <https://ipgeolocation.io/documentation/ip-location-api.html>
- GitHub repository: <https://github.com/IPGeolocation/ip-geolocation-api-swift-sdk>
