// swift-tools-version:5.9
import PackageDescription

// The library targets the lowest platforms where URLSession async/await is
// available. The test suite is XCTest-based, which ships with Xcode. If you
// do not have Xcode installed, `swift test` will not be able to compile the
// test target on macOS because XCTest is not part of the macOS Command Line
// Tools or the swift.org toolchain.

let package = Package(
    name: "IPGeolocation",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(
            name: "IPGeolocation",
            targets: ["IPGeolocation"]
        ),
    ],
    targets: [
        .target(
            name: "IPGeolocation",
            path: "Sources/IPGeolocation"
        ),
        .testTarget(
            name: "IPGeolocationTests",
            dependencies: ["IPGeolocation"],
            path: "Tests/IPGeolocationTests"
        ),
    ]
)
