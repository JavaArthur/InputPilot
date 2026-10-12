// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InputPilot",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "InputPilot", targets: ["InputPilot"])],
    targets: [
        .target(name: "InputPilotCore"),
        .executableTarget(name: "InputPilot", dependencies: ["InputPilotCore"]),
        .executableTarget(name: "InputPilotCoreChecks", dependencies: ["InputPilotCore"], path: "Tests/InputPilotCoreTests")
    ]
)
