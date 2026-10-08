// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(name: "ARCMetricsOTel",

                      // MARK: - Platforms

                      platforms: [.iOS(.v18)],

                      // MARK: - Products

                      products: [.library(name: "ARCMetricsOTel",
                                          targets: ["ARCMetricsOTel"]),
                                 .library(name: "ARCMetricsOTelMocks",
                                          targets: ["ARCMetricsOTelMocks"])],

                      // MARK: - Targets

                      targets: [// Main library
                          .target(name: "ARCMetricsOTel",
                                  path: "Sources/ARCMetricsOTel"),

                          // Test doubles for consumers of ARCMetricsOTel
                          .target(name: "ARCMetricsOTelMocks",
                                  dependencies: ["ARCMetricsOTel"],
                                  path: "Sources/ARCMetricsOTelMocks"),

                          // Tests
                          .testTarget(name: "ARCMetricsOTelTests",
                                      dependencies: ["ARCMetricsOTel", "ARCMetricsOTelMocks"],
                                      path: "Tests/ARCMetricsOTelTests")],

                      // MARK: - Swift Language

                      swiftLanguageModes: [.v6])
