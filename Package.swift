// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Dockfold",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Dockfold", targets: ["Dockfold"]),
        .executable(name: "DockfoldFolder", targets: ["DockfoldFolder"])
    ],
    targets: [
        .target(name: "DockfoldCore", path: "src/DockfoldCore"),
        // Manager app: edits folders, builds their bundles and rewrites the Dock.
        .executableTarget(name: "Dockfold", dependencies: ["DockfoldCore"], path: "src/Dockfold"),
        // Tiny launcher copied once per folder: shows the bubble when its Dock tile is clicked.
        .executableTarget(name: "DockfoldFolder", dependencies: ["DockfoldCore"], path: "src/DockfoldFolder"),
        .testTarget(name: "DockfoldCoreTests", dependencies: ["DockfoldCore"], path: "tests/DockfoldCoreTests"),
        .testTarget(name: "DockfoldTests", dependencies: ["Dockfold", "DockfoldCore"], path: "tests/DockfoldTests")
    ]
)
