// swift-tools-version:6.0
//
//  Package.swift
//  SegmentedPager
//
//  Keep-alive segmented paging for SwiftUI on iOS.
//
//  - SegmentedPagerCore: UIKit container, page lifecycle state machine,
//    sticky-chrome coordination and geometry. No SwiftUI. UIKit-dependent
//    files are gated behind `#if canImport(UIKit)`, so the pure logic
//    builds and tests on macOS.
//  - SegmentedPagerUI: the SwiftUI `SegmentedPager` view, page scroll
//    container, bar context and configuration modifiers.
//

import PackageDescription

let package = Package(
    name: "SegmentedPager",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "SegmentedPagerUI", targets: ["SegmentedPagerUI"]),
        .library(name: "SegmentedPagerCore", targets: ["SegmentedPagerCore"]),
    ],
    targets: [
        .target(name: "SegmentedPagerCore"),
        .target(
            name: "SegmentedPagerUI",
            dependencies: ["SegmentedPagerCore"]
        ),
        .testTarget(
            name: "SegmentedPagerCoreTests",
            dependencies: ["SegmentedPagerCore"]
        ),
        .testTarget(
            name: "SegmentedPagerUITests",
            dependencies: ["SegmentedPagerCore", "SegmentedPagerUI"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
