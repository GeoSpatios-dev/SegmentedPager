//
//  PagerPinnedGeometryTests.swift
//  SegmentedPagerTests
//
//  Created by yousanflics on 7/1/26.
//
//  Regression coverage for pinned-mode chrome geometry across hosting
//  environments. The invariant, in window coordinates at rest:
//
//      headerTop == chromeAnchor
//      barTop    == chromeAnchor + headerHeight
//      contentTop >= barTop + barHeight   (page content below the chrome)
//      bar leaves the trailing scroll-indicator lane uncovered
//
//  A NavigationStack host gives the page's bridged scroll view a
//  different adjusted content inset than a bare host — the bug class
//  where the header lands below the bar and overlaps page content.
//

#if canImport(UIKit)
@testable import SegmentedPagerCore
@testable import SegmentedPagerUI
import SwiftUI
import Testing
import UIKit

@MainActor
struct PagerPinnedGeometryTests {
    private static let headerHeight: CGFloat = 120
    private static let minimumIndicatorGutter: CGFloat = 7.5

    private struct PinnedHarnessView: View {
        @State private var selection = 0

        var body: some View {
            SegmentedPager(
                tabs: [0, 1, 2],
                selection: $selection,
                title: { "Tab \($0)" },
                header: {
                    Color.red
                        .frame(height: PagerPinnedGeometryTests.headerHeight)
                        .accessibilityIdentifier("harness-header")
                },
                page: { tab in
                    PagerPageScroll {
                        LazyVStack(spacing: 0) {
                            ForEach(0 ..< 80, id: \.self) { index in
                                Text("Row \(tab)-\(index)")
                                    .frame(height: 44)
                            }
                        }
                    }
                }
            )
            .pagerBarMode(.pinned)
        }
    }

    private struct Geometry {
        let anchorY: CGFloat
        let headerTopY: CGFloat
        let headerParentIsPageScroll: Bool
        let barTopY: CGFloat
        let barHeight: CGFloat
        let barTrailingGutter: CGFloat
        let pageContentTopY: CGFloat
        let pageAdjustedTopInset: CGFloat
        let pageRestOffsetY: CGFloat
    }

    /// Hosts `content` in a window, waits for the pinned chrome to
    /// assemble, and measures everything in window coordinates.
    private func measure(_ content: some View) -> Geometry? {
        let hosting = UIHostingController(rootView: content)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = hosting
        window.isHidden = false
        window.layoutIfNeeded()

        var overlay: PagerChromeOverlay?
        var horizontal: PagerHorizontalScrollView?
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            window.layoutIfNeeded()
            overlay = window.firstDescendant(of: PagerChromeOverlay.self)
            horizontal = window.firstDescendant(of: PagerHorizontalScrollView.self)
            if let overlay, overlay.subviews.count >= 2,
               let horizontal,
               horizontal.firstDescendant(of: UIScrollView.self) != nil ||
               overlay.subviews.count == 2 {
                // Header may live in the page scroll view (settled) or the
                // overlay; require the page scroll to exist either way.
                if horizontal.firstDescendant(of: UIScrollView.self) != nil { break }
            }
        }

        guard let overlay, let horizontal,
              let pageScroll = horizontal.firstDescendant(of: UIScrollView.self)
        else { return nil }

        // Give the settle path (reparenting) time to run after the probe
        // registered.
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        window.layoutIfNeeded()

        // Chrome views: bar is the overlay subview at barOriginY; header is
        // the red fixed-height hosting view, wherever it currently lives.
        let overlaySubviews = overlay.subviews
        guard let barView = overlaySubviews.last else { return nil }

        let headerView = (pageScroll.subviews + overlaySubviews.dropLast())
            .first { abs($0.bounds.height - Self.headerHeight) < 30 && $0 !== barView }

        guard let headerView else { return nil }

        // The SwiftUI page content's top: the topmost non-header subview of
        // the page scroll view (SwiftUI's unified content view).
        let contentView = pageScroll.subviews
            .filter { $0 !== headerView }
            .max(by: { $0.bounds.height < $1.bounds.height })

        func windowY(_ view: UIView) -> CGFloat {
            view.convert(view.bounds, to: window).minY
        }

        let overlayFrame = overlay.convert(overlay.bounds, to: window)
        let barFrame = barView.convert(barView.bounds, to: window)

        return Geometry(
            anchorY: overlayFrame.minY + overlay.safeAreaInsets.top,
            headerTopY: windowY(headerView),
            headerParentIsPageScroll: headerView.superview === pageScroll,
            barTopY: barFrame.minY,
            barHeight: barView.bounds.height,
            barTrailingGutter: overlayFrame.maxX - barFrame.maxX,
            pageContentTopY: contentView.map(windowY) ?? -1,
            pageAdjustedTopInset: pageScroll.adjustedContentInset.top,
            pageRestOffsetY: pageScroll.contentOffset.y
        )
    }

    private func assertInvariants(_ geometry: Geometry, host: String) {
        #expect(
            geometry.headerParentIsPageScroll,
            "[\(host)] header should ride inside the page scroll view at rest; geometry: \(geometry)"
        )
        #expect(
            abs(geometry.headerTopY - geometry.anchorY) < 2,
            "[\(host)] header must sit at the chrome anchor; geometry: \(geometry)"
        )
        #expect(
            abs(geometry.barTopY - (geometry.anchorY + Self.headerHeight)) < 2,
            "[\(host)] bar must pin right below the header; geometry: \(geometry)"
        )
        #expect(
            geometry.pageContentTopY >= geometry.barTopY + geometry.barHeight - 2,
            "[\(host)] page content must start below the chrome; geometry: \(geometry)"
        )
        #expect(
            geometry.barTrailingGutter >= Self.minimumIndicatorGutter,
            "[\(host)] pinned bar must leave the native scroll indicator lane visible; geometry: \(geometry)"
        )
    }

    /// First switch to a lazily created page: the fresh page's content
    /// must land below the chrome exactly like the first page's did —
    /// SwiftUI initializes a bridged scroll view's offset without
    /// accounting for content margins, which shows up as a chrome-sized
    /// offset between the bar and the content on first visit.
    @Test func firstSwitchToFreshPageAlignsContentWithChrome() {
        let box = SelectionBox()
        let harness = ObservedSelectionHarnessView(box: box)

        let hosting = UIHostingController(rootView: harness)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = hosting
        window.isHidden = false
        window.layoutIfNeeded()

        // Wait for the initial page + chrome to assemble.
        var deadline = Date().addingTimeInterval(3)
        while window.firstDescendant(of: PagerChromeOverlay.self) == nil, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            window.layoutIfNeeded()
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        // First visit to tab 1 (lazy → created now, animated transition).
        box.value = 1

        // Mid-transition sample: the fresh page must already be aligned
        // while it is riding in — the settle correction is too late for
        // the frames the user actually sees.
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        window.layoutIfNeeded()
        if let horizontal = window.firstDescendant(of: PagerHorizontalScrollView.self) {
            let freshMidTransition = horizontal.allDescendants(of: UIScrollView.self).first {
                $0.convert($0.bounds, to: horizontal).minX >= 389
            }
            if let fresh = freshMidTransition {
                let normalized = fresh.contentOffset.y + fresh.adjustedContentInset.top
                #expect(
                    abs(normalized) < 2,
                    "fresh page misaligned mid-transition: normalized \(normalized), offset \(fresh.contentOffset.y), inset \(fresh.adjustedContentInset.top)"
                )
            }
        }

        deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            window.layoutIfNeeded()
            if let horizontal = window.firstDescendant(of: PagerHorizontalScrollView.self),
               abs(horizontal.contentOffset.x - 390) < 1, !horizontal.isDecelerating {
                break
            }
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        guard let overlay = window.firstDescendant(of: PagerChromeOverlay.self),
              let horizontal = window.firstDescendant(of: PagerHorizontalScrollView.self),
              let barView = overlay.subviews.last
        else {
            Issue.record("chrome did not assemble for the fresh-page switch")
            return
        }

        // The fresh page is the one horizontally positioned at x == width.
        let pageScrolls = horizontal.allDescendants(of: UIScrollView.self)
        guard let freshScroll = pageScrolls.first(where: {
            $0.convert($0.bounds, to: horizontal).minX >= 389
        }) else {
            Issue.record("fresh page scroll view not found; pages: \(pageScrolls.count)")
            return
        }

        let normalized = freshScroll.contentOffset.y + freshScroll.adjustedContentInset.top
        let barBottomY = barView.convert(barView.bounds, to: window).maxY

        // Chrome was fully expanded before the switch → the fresh page
        // must rest fully expanded too (normalized == 0), with its
        // content starting right below the bar.
        #expect(
            abs(normalized) < 2,
            "fresh page rests at spurious normalized offset \(normalized); offset \(freshScroll.contentOffset.y), inset \(freshScroll.adjustedContentInset.top)"
        )

        if let contentView = freshScroll.subviews.max(by: { $0.bounds.height < $1.bounds.height }) {
            let contentTopY = contentView.convert(contentView.bounds, to: window).minY
            #expect(
                contentTopY >= barBottomY - 2,
                "fresh page content (top \(contentTopY)) must start below the bar (bottom \(barBottomY))"
            )
        }
    }

    /// Reproduces the async-loading case: the header starts small (a
    /// skeleton) and grows once "data" arrives. The chrome inset change
    /// must not leave already-created pages resting at a spurious
    /// normalized offset (content misaligned with the bar until the
    /// user scrolls).
    @Test func headerGrowthAfterLoadKeepsRestingPagesAligned() {
        let box = SelectionBox()
        let harness = GrowingHeaderHarnessView(box: box)

        let hosting = UIHostingController(rootView: harness)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = hosting
        window.isHidden = false
        window.layoutIfNeeded()

        var deadline = Date().addingTimeInterval(3)
        while window.firstDescendant(of: PagerChromeOverlay.self) == nil, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            window.layoutIfNeeded()
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        // "Data arrives": the header grows from 40 to 160.
        box.headerHeight = 160
        deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            window.layoutIfNeeded()
        }

        guard let overlay = window.firstDescendant(of: PagerChromeOverlay.self),
              let horizontal = window.firstDescendant(of: PagerHorizontalScrollView.self),
              let pageScroll = horizontal.firstDescendant(of: UIScrollView.self),
              let barView = overlay.subviews.last
        else {
            Issue.record("chrome did not assemble for the growing-header harness")
            return
        }

        let normalized = pageScroll.contentOffset.y + pageScroll.adjustedContentInset.top
        #expect(
            abs(normalized) < 2,
            "page must still rest fully expanded after header growth; normalized \(normalized), offset \(pageScroll.contentOffset.y), inset \(pageScroll.adjustedContentInset.top)"
        )

        let anchorY = overlay.convert(overlay.bounds, to: window).minY + overlay.safeAreaInsets.top
        let barTopY = barView.convert(barView.bounds, to: window).minY
        #expect(
            abs(barTopY - (anchorY + 160)) < 2,
            "bar must sit below the grown header; barTop \(barTopY), anchor \(anchorY)"
        )

        if let contentView = pageScroll.subviews.max(by: { $0.bounds.height < $1.bounds.height }) {
            let contentTopY = contentView.convert(contentView.bounds, to: window).minY
            let barBottomY = barView.convert(barView.bounds, to: window).maxY
            #expect(
                contentTopY >= barBottomY - 2,
                "content (top \(contentTopY)) must start below the bar (bottom \(barBottomY)) after header growth"
            )
        }
    }

    private struct GrowingHeaderHarnessView: View {
        let box: SelectionBox
        @State private var selection = 0

        var body: some View {
            SegmentedPager(
                tabs: [0, 1, 2],
                selection: $selection,
                title: { "Tab \($0)" },
                header: {
                    Color.red.frame(height: box.headerHeight)
                },
                page: { tab in
                    PagerPageScroll {
                        LazyVStack(spacing: 0) {
                            ForEach(0 ..< 80, id: \.self) { index in
                                Text("Row \(tab)-\(index)")
                                    .frame(height: 44)
                            }
                        }
                    }
                }
            )
            .pagerBarMode(.pinned)
        }
    }

    private struct ObservedSelectionHarnessView: View {
        let box: SelectionBox

        var body: some View {
            SegmentedPager(
                tabs: [0, 1, 2],
                selection: Binding(
                    get: { box.value },
                    set: { box.value = $0 }
                ),
                title: { "Tab \($0)" },
                header: {
                    Color.red.frame(height: PagerPinnedGeometryTests.headerHeight)
                },
                page: { tab in
                    PagerPageScroll {
                        LazyVStack(spacing: 0) {
                            ForEach(0 ..< 80, id: \.self) { index in
                                Text("Row \(tab)-\(index)")
                                    .frame(height: 44)
                            }
                        }
                    }
                }
            )
            .pagerBarMode(.pinned)
        }
    }

    @Test func pinnedChromeGeometryInBareHost() {
        guard let geometry = measure(PinnedHarnessView()) else {
            Issue.record("pinned chrome did not assemble in bare host")
            return
        }
        assertInvariants(geometry, host: "bare")
    }

    @Test func pinnedChromeGeometryInsideNavigationStack() {
        let hosted = NavigationStack {
            PinnedHarnessView()
                .navigationTitle("KSFO")
                .navigationBarTitleDisplayMode(.inline)
        }
        guard let geometry = measure(hosted) else {
            Issue.record("pinned chrome did not assemble under NavigationStack")
            return
        }
        assertInvariants(geometry, host: "nav-stack")
    }
}

@MainActor
@Observable
private final class SelectionBox {
    var value = 0
    var headerHeight: CGFloat = 40
}

extension UIView {
    fileprivate func firstDescendant<T: UIView>(of type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T { return match }
            if let match = subview.firstDescendant(of: type) { return match }
        }
        return nil
    }

    fileprivate func allDescendants<T: UIView>(of type: T.Type) -> [T] {
        var result: [T] = []
        for subview in subviews {
            if let match = subview as? T { result.append(match) }
            result.append(contentsOf: subview.allDescendants(of: type))
        }
        return result
    }
}
#endif
