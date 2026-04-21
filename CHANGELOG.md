# Changelog

All notable changes to the Swift SDK for the IPGeolocation.io IP Location API are recorded here.

## 1.0.0

First public release.

- Swift Package covering `/v3/ipgeo` and `/v3/ipgeo-bulk`
- Typed single and bulk lookup with raw JSON and XML variants
- Config validation, request validation, and typed errors
- API key and request-origin auth for single lookup; API key required for bulk
- Response metadata with credits charged, successful records, duration, status code, and raw headers
- JSON helpers for compact, full, and pretty output
- `URLSession`-based transport with response size cap and timeout handling
- Unit, live integration, and live field-parity tests
