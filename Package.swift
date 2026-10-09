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

                      // MARK: - Dependencies

                      // ARCMetrics provides the `Tracing` seam. opentelemetry-swift is an approved
                      // third-party exception for this package only — see
                      // docs/adr/0001-opentelemetry-swift-dependency.md.
                      dependencies: [.package(url: "https://github.com/arclabs-studio/ARCMetrics.git", from: "2.1.0"),
                                     .package(url: "https://github.com/open-telemetry/opentelemetry-swift-core.git",
                                              .upToNextMinor(from: "2.6.0")),
                                     .package(url: "https://github.com/open-telemetry/opentelemetry-swift.git",
                                              .upToNextMinor(from: "2.6.0"))],

                      // MARK: - Targets

                      targets: [// Main library
                          .target(name: "ARCMetricsOTel",
                                  dependencies: [.product(name: "ARCMetrics", package: "ARCMetrics"),
                                                 .product(name: "OpenTelemetryApi",
                                                          package: "opentelemetry-swift-core"),
                                                 .product(name: "OpenTelemetrySdk",
                                                          package: "opentelemetry-swift-core"),
                                                 .product(name: "OpenTelemetryProtocolExporterHTTP",
                                                          package: "opentelemetry-swift"),
                                                 .product(name: "PersistenceExporter",
                                                          package: "opentelemetry-swift")],
                                  path: "Sources/ARCMetricsOTel"),

                          // Test doubles for consumers of ARCMetricsOTel
                          .target(name: "ARCMetricsOTelMocks",
                                  dependencies: ["ARCMetricsOTel"],
                                  path: "Sources/ARCMetricsOTelMocks"),

                          // Tests
                          .testTarget(name: "ARCMetricsOTelTests",
                                      dependencies: ["ARCMetricsOTel",
                                                     "ARCMetricsOTelMocks",
                                                     .product(name: "ARCMetricsMocks", package: "ARCMetrics"),
                                                     .product(name: "InMemoryExporter",
                                                              package: "opentelemetry-swift")],
                                      path: "Tests/ARCMetricsOTelTests")],

                      // MARK: - Swift Language

                      swiftLanguageModes: [.v6])
