import Foundation
import XCTest

enum LiveTestGuard {
    struct Keys {
        let freeKey: String
        let paidKey: String
    }

    static func requireLiveTests() throws -> Keys {
        let env = ProcessInfo.processInfo.environment

        guard env["IPGEO_RUN_LIVE_TESTS"]?.lowercased() == "true" else {
            throw XCTSkip("set IPGEO_RUN_LIVE_TESTS=true to run live Swift integration tests")
        }

        let freeKey = env["IPGEO_FREE_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let paidKey = env["IPGEO_PAID_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if freeKey.isEmpty || paidKey.isEmpty {
            throw XCTSkip("set IPGEO_FREE_KEY and IPGEO_PAID_KEY to run live Swift integration tests")
        }

        return Keys(freeKey: freeKey, paidKey: paidKey)
    }

    static func requireLiveFieldParity() throws -> String {
        let env = ProcessInfo.processInfo.environment

        guard env["IPGEO_RUN_LIVE_FIELD_PARITY"]?.lowercased() == "true"
            || env["IPGEO_RUN_LIVE_HARDENING"]?.lowercased() == "true" else {
            throw XCTSkip("set IPGEO_RUN_LIVE_FIELD_PARITY=true to run live Swift field parity tests")
        }

        let paidKey = env["IPGEO_PAID_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if paidKey.isEmpty {
            throw XCTSkip("set IPGEO_PAID_KEY to run live Swift field parity tests")
        }
        return paidKey
    }
}
