// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QLabWaveform",
    platforms: [.macOS(.v11)],
    products: [
        .executable(name: "QLabWaveform", targets: ["QLabWaveform"])
    ],
    targets: [
        .executableTarget(
            name: "QLabWaveform",
            path: "Sources/QLabWaveform"
        )
    ]
)
