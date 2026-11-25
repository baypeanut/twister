// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Twister",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "TwisterCore", targets: ["TwisterCore"]),
        .executable(name: "Twister", targets: ["TwisterApp"]),
        .executable(name: "twister-cli", targets: ["TwisterCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .target(name: "TwisterCore", resources: [.copy("Resources")]),
        .target(name: "TwisterUpdates", dependencies: [.product(name: "Sparkle", package: "Sparkle")]),
        .executableTarget(name: "TwisterApp", dependencies: ["TwisterCore", "TwisterUpdates"], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "TwisterCLI", dependencies: ["TwisterCore"]),
        .testTarget(name: "TwisterCoreTests", dependencies: ["TwisterCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "TwisterUpdatesTests", dependencies: ["TwisterUpdates"])
    ],
    swiftLanguageModes: [.v5]
)
