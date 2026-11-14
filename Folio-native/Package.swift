// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FolioNative",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "FolioCore", targets: ["FolioCore"])],
    targets: [
        .systemLibrary(name: "CZlib", path: "Sources/CZlib", pkgConfig: "zlib"),
        .target(name: "FolioCore", dependencies: ["CZlib"]),
        .testTarget(name: "FolioCoreTests", dependencies: ["FolioCore"],
                    resources: [.copy("Fixtures")])
    ]
)
