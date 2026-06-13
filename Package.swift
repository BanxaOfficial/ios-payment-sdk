// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BanxaPaymentSDK",
    platforms: [.iOS("13.1")],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "BanxaPaymentSDK",
            targets: ["BanxaPaymentSDK"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/primer-io/primer-sdk-ios.git", from: "2.49.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "BanxaPaymentSDK",
            dependencies: [
                .product(name: "PrimerSDK", package: "primer-sdk-ios")
            ]
        ),
        .testTarget(
            name: "BanxaPaymentSDKTests",
            dependencies: ["BanxaPaymentSDK"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
