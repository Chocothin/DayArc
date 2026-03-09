// 참고용 샘플 Package.swift (앱 타깃에 자동 포함되지 않음)
// DayflowCoreKit를 독립 모듈로 빌드할 때 활용 가능.
import PackageDescription

let package = Package(
    name: "DayflowCoreKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DayflowCoreKit", targets: ["DayflowCoreKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.25.0")
    ],
    targets: [
        .target(
            name: "DayflowCoreKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: ".",
            exclude: ["Package.sample.swift"]
        )
    ]
)
