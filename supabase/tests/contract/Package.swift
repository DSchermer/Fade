// swift-tools-version:5.9
import PackageDescription
let package = Package(
  name: "FadeContract",
  platforms: [.macOS(.v13)],
  dependencies: [ .package(url: "https://github.com/supabase/supabase-swift", from: "2.0.0") ],
  targets: [
    .target(name: "FadeModels", path: "Sources/FadeModels"),
    .testTarget(name: "ContractTests", dependencies: ["FadeModels", .product(name: "PostgREST", package: "supabase-swift")], path: "Tests/ContractTests"),
  ]
)
