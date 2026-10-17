// swift-tools-version: 6.0
// Линкер СберKids ↔ JS-прикол. Только системные фреймворки, без внешних зависимостей.

import PackageDescription

let package = Package(
    name: "PrankLinker",
    defaultLocalization: "ru",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "PrankLinker", targets: ["PrankLinker"])
    ],
    targets: [
        .target(name: "PrankLinker"),
        .testTarget(name: "PrankLinkerTests", dependencies: ["PrankLinker"])
    ],
    swiftLanguageModes: [.v6]
)
