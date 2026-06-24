// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacDragInstallHelper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "DMGInstallCore", targets: ["DMGInstallCore"]),
        .executable(name: "MacDragInstallHelper", targets: ["MacDragInstallHelper"])
    ],
    targets: [
        .target(name: "DMGInstallCore"),
        .executableTarget(
            name: "MacDragInstallHelper",
            dependencies: ["DMGInstallCore"]
        ),
        .executableTarget(
            name: "DMGInstallCoreTests",
            dependencies: ["DMGInstallCore"],
            path: "Tests/DMGInstallCoreTests"
        )
    ]
)
