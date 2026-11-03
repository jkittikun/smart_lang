// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SmartLang",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SmartLang", targets: ["SmartLang"]),
        .library(name: "SmartLangCore", targets: ["SmartLangCore"]),
    ],
    targets: [
        .target(name: "SmartLangCore"),
        .executableTarget(
            name: "SmartLang",
            dependencies: ["SmartLangCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "SmartLangCoreTests", dependencies: ["SmartLangCore"]),
    ]
)
