// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "FanPicker",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "FanPicker",
            targets: ["FanPicker"]
        ),
    ],
    targets: [
        .target(
            name: "FanPicker"
        ),
        .testTarget(
            name: "FanPickerTests",
            dependencies: ["FanPicker"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
