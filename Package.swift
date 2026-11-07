// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Relief",
    platforms: [.macOS("14.4")],
    targets: [
        .executableTarget(
            name: "Relief",
            path: "Sources/Relief",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "ReliefTests",
            dependencies: ["Relief"],
            path: "Tests/ReliefTests"
        ),
    ]
)
