import Foundation

public enum SDKVersion {
    public static let current: String = "1.0.0"

    public static func defaultUserAgent() -> String {
        "ipgeolocation-swift-sdk/\(current)"
    }
}
