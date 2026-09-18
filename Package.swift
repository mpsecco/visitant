// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Visitant",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Visitant", targets: ["Visitant"])
    ],
    targets: [
        .executableTarget(
            name: "Visitant",
            path: "Sources/Visitant"
        ),
        .testTarget(
            name: "VisitantTests",
            dependencies: ["Visitant"],
            path: "Tests/VisitantTests"
        )
    ]
)
