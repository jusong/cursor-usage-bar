// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CursorUsageBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CursorUsageBar", targets: ["CursorUsageBar"])
    ],
    targets: [
        .target(
            name: "CursorUsageCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(
            name: "CursorUsageBar",
            dependencies: ["CursorUsageCore"],
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        .executableTarget(
            name: "CursorUsageCoreChecks",
            dependencies: ["CursorUsageCore"]
        ),
    ]
)
