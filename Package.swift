// swift-tools-version:6.0
//
//  Package.swift
//  SegmentedPager
//
//  Local Swift Package hosting the segmented paging component described
//  in Doc/SegmentedPager_Design.md: a JXSegmentedView-style pager with
//  per-page scroll retention, native UIKit gesture arbitration, explicit
//  page lifecycle, and (from M2) smooth sticky-header coordination.
//
//  - SegmentedPagerCore: UIKit container + pure geometry/state machines.
//    No SwiftUI import. UIKit-dependent files are gated behind
//    `#if canImport(UIKit)` so pure logic builds and tests on macOS.
//  - SegmentedPagerUI: SwiftUI adapter (SegmentedPager view, page scroll
//    container, environment bridging, bar protocol).
//

import PackageDescription

let package = Package(
    name: "SegmentedPager",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SegmentedPagerCore", targets: ["SegmentedPagerCore"]),
        .library(name: "SegmentedPagerUI", targets: ["SegmentedPagerUI"]),
    ],
    targets: [
        .target(
            name: "SegmentedPagerCore",
            path: "Sources/SegmentedPagerCore"
        ),
        .target(
            name: "SegmentedPagerUI",
            dependencies: ["SegmentedPagerCore"],
            path: "Sources/SegmentedPagerUI"
        ),
        .testTarget(
            name: "SegmentedPagerTests",
            dependencies: ["SegmentedPagerCore", "SegmentedPagerUI"],
            path: "Tests/SegmentedPagerTests"
        ),
    ]
)
