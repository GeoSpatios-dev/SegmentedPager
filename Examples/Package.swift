// swift-tools-version:6.0
//
//  Example views for SegmentedPager. Open this folder in Xcode and use the
//  previews, or add the `SegmentedPagerExamples` library to a scratch app.
//  Not part of the published products.
//

import PackageDescription

let package = Package(
    name: "SegmentedPagerExamples",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "SegmentedPagerExamples", targets: ["SegmentedPagerExamples"]),
    ],
    dependencies: [
        .package(name: "SegmentedPager", path: ".."),
    ],
    targets: [
        .target(
            name: "SegmentedPagerExamples",
            dependencies: [
                .product(name: "SegmentedPagerUI", package: "SegmentedPager"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
