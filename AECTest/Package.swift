// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AECTest",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CSpeexDSP",
            path: "Sources/CSpeexDSP",
            exclude: ["COPYING"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .define("HAVE_CONFIG_H"),
            ]
        ),
        .executableTarget(
            name: "AECTest",
            dependencies: ["CSpeexDSP"],
            path: "Sources/AECTest"
        ),
    ]
)
