// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TetrisCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "TetrisCore", targets: ["TetrisCore"])],
    targets: [
        .target(name: "TetrisCore", path: "TetrisDuel/Core"),
        .testTarget(name: "TetrisCoreTests", dependencies: ["TetrisCore"], path: "TetrisDuelTests/Core")
    ]
)
