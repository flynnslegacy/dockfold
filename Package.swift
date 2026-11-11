// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Nido",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Nido", targets: ["Nido"]),
        .executable(name: "NidoFolder", targets: ["NidoFolder"])
    ],
    targets: [
        .target(name: "NidoCore", path: "src/NidoCore"),
        // Manager app: edits folders, builds their bundles and rewrites the Dock.
        .executableTarget(name: "Nido", dependencies: ["NidoCore"], path: "src/Nido"),
        // Tiny launcher copied once per folder: shows the bubble when its Dock tile is clicked.
        .executableTarget(name: "NidoFolder", dependencies: ["NidoCore"], path: "src/NidoFolder"),
        .testTarget(name: "NidoCoreTests", dependencies: ["NidoCore"], path: "tests/NidoCoreTests"),
        .testTarget(name: "NidoTests", dependencies: ["Nido", "NidoCore"], path: "tests/NidoTests")
    ]
)
