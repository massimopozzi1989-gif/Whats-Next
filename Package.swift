// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DoveSonoArrivato",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DoveSonoArrivato", targets: ["DoveSonoArrivato"])],
    targets: [
        .executableTarget(name: "DoveSonoArrivato", resources: [.process("Resources")]),
        .testTarget(name: "DoveSonoArrivatoTests", dependencies: ["DoveSonoArrivato"])
    ]
)
