// swift-tools-version: 6.0
import PackageDescription

// What Pilot knows about LG TVs and Sonos speakers, with no UI and no network
// of its own, so it can be tested without a TV. Foundation only.
let package = Package(
    name: "PilotKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PilotKit", targets: ["PilotKit"])],
    targets: [
        .target(name: "PilotKit"),
        .testTarget(name: "PilotKitTests", dependencies: ["PilotKit"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v5]
)
