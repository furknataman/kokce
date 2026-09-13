// swift-tools-version: 6.0
import PackageDescription

// KokenKit — Köken'in alan mantığı: katalog modelleri, günün kelimesi,
// Türkçeye duyarlı arama, içerik deposu (bundle → önbellek → uzak) ve favoriler.
//
// Uygulama ve widget hedeflerinin ikisi de bunu tüketir. SolvyKit'e bilerek
// bağlanmaz: bağımsız kalması `swift test`in macOS host'ta yalıtık çalışmasını
// sağlar. macOS dilimi yalnızca bu test koşusu için vardır.
let package = Package(
    name: "KokenKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "KokenKit", targets: ["KokenKit"])
    ],
    targets: [
        .target(
            name: "KokenKit",
            path: "Sources/KokenKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "KokenKitTests",
            dependencies: ["KokenKit"],
            path: "Tests/KokenKitTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
