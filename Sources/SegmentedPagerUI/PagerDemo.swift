//
//  PagerDemo.swift
//  SegmentedPager
//
//  Created by yousanflics on 7/1/26.
//
//  In-package demo doubling as the M1 spike page (design doc §12): one
//  heavy LazyVStack page, one page with nested horizontal scrollers
//  (plus a swipe-exclusion region), one long-text page, and one page
//  that visibly proves keep-alive semantics (.task runs once, @State and
//  scroll position survive tab switches).
//
//  Run on device to validate the fragile surfaces: probe resolution and
//  lifecycle callbacks (Xcode previews also work for a first pass).
//

#if DEBUG && canImport(UIKit)
import SwiftUI

private enum DemoTab: String, CaseIterable, Hashable {
    case feed = "Feed"
    case charts = "Charts"
    case text = "Text"
    case state = "State"
}

private struct PagerDemoView: View {
    @State private var selection: DemoTab = .feed

    var body: some View {
        SegmentedPager(
            tabs: DemoTab.allCases,
            selection: $selection,
            title: { $0.rawValue },
            header: {
                Text("SegmentedPager Demo")
                    .font(.headline)
                    .padding(.vertical, 8)
            },
            page: { tab in
                PagerPageScroll {
                    Self.pageContent(for: tab)
                        .padding(.horizontal, 16)
                }
            }
        )
        .pagerPreloadPolicy(.lazy(visibleRatio: 0.5))
    }

    @ViewBuilder
    static func pageContent(for tab: DemoTab) -> some View {
        switch tab {
        case .feed:
            feedPage
        case .charts:
            chartsPage
        case .text:
            textPage
        case .state:
            statePage
        }
    }

    /// Spike: heavy list — checks LazyVStack laziness inside the hosted
    /// ScrollView and scroll-position retention across switches.
    private static var feedPage: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(0 ..< 400, id: \.self) { index in
                Text("Row \(index)")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quaternary.opacity(0.4))
                    .clipShape(.rect(cornerRadius: 8))
            }
        }
        .padding(.vertical, 12)
    }

    /// Spike: nested horizontal scrollers — the first row relies on
    /// native same-axis arbitration, the second opts out of page swipes
    /// entirely via pagerSwipeExclusion().
    private static var chartsPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Native nested horizontal scroll")
                .font(.subheadline.weight(.semibold))
            horizontalCards(prefix: "A")

            Text("Swipe-exclusion region (never switches pages)")
                .font(.subheadline.weight(.semibold))
            horizontalCards(prefix: "B")
                .pagerSwipeExclusion()

            ForEach(0 ..< 20, id: \.self) { index in
                Text("Vertical filler \(index)")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quaternary.opacity(0.4))
                    .clipShape(.rect(cornerRadius: 8))
            }
        }
        .padding(.vertical, 12)
    }

    private static func horizontalCards(prefix: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0 ..< 12, id: \.self) { index in
                    Text("\(prefix)\(index)")
                        .font(.title2.weight(.bold))
                        .frame(width: 140, height: 90)
                        .background(.tint.opacity(0.15))
                        .clipShape(.rect(cornerRadius: 12))
                }
            }
        }
    }

    private static var textPage: some View {
        Text(
            String(
                repeating: "Long-form content keeps its reading position when you switch away and back. ",
                count: 120
            )
        )
        .padding(.vertical, 12)
    }

    /// Keep-alive proof: the task counter must stay at 1 no matter how
    /// often you switch tabs; the stepper value and appear/disappear log
    /// must survive switches.
    private static var statePage: some View {
        StateDemoPage()
    }
}

private struct StateDemoPage: View {
    @State private var taskRuns = 0
    @State private var stepperValue = 0
    @State private var log: [String] = []
    @Environment(\.pagerPageIsActive) private var isActive

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LabeledContent(".task runs (must stay 1)", value: "\(taskRuns)")
            Stepper("Retained @State: \(stepperValue)", value: $stepperValue)
            LabeledContent("pagerPageIsActive", value: isActive ? "true" : "false")

            Text("Lifecycle log")
                .font(.subheadline.weight(.semibold))
            ForEach(Array(log.enumerated()), id: \.offset) { entry in
                Text(entry.element)
                    .font(.caption.monospaced())
            }
        }
        .padding(.vertical, 12)
        .task {
            taskRuns += 1
        }
        .onPagerPageAppear {
            log.append("appear #\(log.count)")
        }
        .onPagerPageDisappear {
            log.append("disappear #\(log.count)")
        }
    }
}

// MARK: - Pinned (sticky header) demo

/// M2 spike surface: interactive header (tap vs drag coexistence),
/// dynamic header height, pin-progress readout, and deep/shallow page
/// combinations to exercise every OffsetSyncRule quadrant by hand.
private struct PinnedPagerDemoView: View {
    @State private var selection: DemoTab = .feed
    @State private var headerTaps = 0
    @State private var isHeaderExpanded = false
    @State private var pinProgress: CGFloat = 0

    var body: some View {
        SegmentedPager(
            tabs: DemoTab.allCases,
            selection: $selection,
            title: { $0.rawValue },
            header: {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pinned Header")
                        .font(.title2.weight(.bold))
                    Text("Drag anywhere on this header to collapse it — the pan IS the page's scroll gesture.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        Button("Tap me (\(headerTaps))") {
                            headerTaps += 1
                        }
                        .buttonStyle(.borderedProminent)

                        Toggle("Taller", isOn: $isHeaderExpanded)
                            .fixedSize()
                    }

                    if isHeaderExpanded {
                        Text("Dynamic height region — page insets and pin point follow without a jump.")
                            .font(.footnote)
                            .padding(.vertical, 24)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.tint.opacity(0.12))
            },
            page: { tab in
                PagerPageScroll {
                    PagerDemoView.pageContent(for: tab)
                        .padding(.horizontal, 16)
                }
            }
        )
        .pagerBarMode(.pinned)
        .pagerBarBackground(.regularMaterial)
        .onPagerPinProgress { pinProgress = $0 }
        .overlay(alignment: .bottom) {
            Text("pinProgress \(pinProgress, format: .number.precision(.fractionLength(2)))")
                .font(.caption.monospaced())
                .padding(6)
                .background(.thinMaterial)
                .clipShape(.rect(cornerRadius: 6))
                .padding(.bottom, 8)
        }
    }
}

#Preview("SegmentedPager Demo (fixed)") {
    PagerDemoView()
}

#Preview("SegmentedPager Demo (pinned)") {
    PinnedPagerDemoView()
}
#endif
