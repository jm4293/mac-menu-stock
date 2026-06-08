// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "StockBar",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "StockBar",
            path: ".",
            sources: ["main.swift"]
        )
    ]
)
