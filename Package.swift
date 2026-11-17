// swift-tools-version: 6.0
import PackageDescription

let libraries = ["SSCore", "SSCoreFakes", "SSData", "SSTemplates", "SSRender", "SSSeed", "SSApp"]
let allLibraries: [Target.Dependency] = libraries.map { .target(name: $0) }

let package = Package(
  name: "SergnaneseSocial",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.12.0"),
    .package(url: "https://github.com/hummingbird-project/swift-mustache.git", exact: "2.1.1"),
    .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
  ],
  targets: [
    .target(name: "SSCore"),
    .target(name: "SSCoreFakes", dependencies: ["SSCore"]),
    .target(name: "SSData", dependencies: ["SSCore", .product(name: "GRDB", package: "GRDB.swift")]),
    .target(name: "SSTemplates", dependencies: ["SSCore", "ZIPFoundation"]),
    .target(
      name: "SSRender",
      dependencies: ["SSCore", "SSTemplates", .product(name: "Mustache", package: "swift-mustache")]),
    .target(name: "SSSeed", dependencies: ["SSCore"]),
    .target(name: "SSApp", dependencies: ["SSCore", "SSCoreFakes"]),
    .executableTarget(name: "SergnaneseSocial", dependencies: allLibraries),
    .executableTarget(name: "ss-tool", dependencies: allLibraries),

    .testTarget(name: "SSCoreTests", dependencies: ["SSCore", "SSCoreFakes"]),
    .testTarget(name: "SSDataTests", dependencies: ["SSData", "SSCoreFakes"]),
    .testTarget(name: "SSTemplatesTests", dependencies: ["SSTemplates", "SSCoreFakes"]),
    .testTarget(name: "SSRenderTests", dependencies: ["SSRender", "SSCoreFakes"]),
    .testTarget(name: "SSSeedTests", dependencies: ["SSSeed", "SSCoreFakes"]),
    .testTarget(name: "SSAppTests", dependencies: ["SSApp", "SSCoreFakes"]),
    .testTarget(name: "IntegrationTests", dependencies: allLibraries),
  ],
  swiftLanguageModes: [.v6]
)
