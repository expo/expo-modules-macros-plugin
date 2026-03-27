// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import CompilerPluginSupport
import PackageDescription

let package = Package(
  name: "ExpoModulesOptimized",
  platforms: [.macOS(.v10_15)],
  products: [
    .executable(
      name: "ExpoModulesOptimized",
      targets: ["ExpoModulesOptimized"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0-latest")
  ],
  targets: [
    .macro(
      name: "ExpoModulesOptimizedMacros",
      dependencies: [
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
      ]
    ),

    .executableTarget(name: "ExpoModulesOptimized", dependencies: ["ExpoModulesOptimizedMacros"]),

    .testTarget(
      name: "ExpoModulesOptimizedTests",
      dependencies: [
        "ExpoModulesOptimizedMacros",
        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
      ]
    ),
  ]
)
