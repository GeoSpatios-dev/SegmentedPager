//
//  PagerPinnedGeometryTests.swift
//  SegmentedPagerTests
//
//  Regression coverage for pinned-mode chrome geometry across hosting
//  environments. The invariant, in window coordinates at rest:
//
//      headerTop == chromeAnchor
//      barTop    == chromeAnchor + headerHeight
//      contentTop >= barTop + barHeight   (page content below the chrome)
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
                            ForEach(0..<80, id: \.self) { index in
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

        return Geometry(
            anchorY: overlay.convert(overlay.bounds, to: window).minY + overlay.safeAreaInsets.top,
            headerTopY: windowY(headerView),
            headerParentIsPageScroll: headerView.superview === pageScroll,
            barTopY: windowY(barView),
            barHeight: barView.bounds.height,
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

extension UIView {
    fileprivate func firstDescendant<T: UIView>(of type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T { return match }
            if let match = subview.firstDescendant(of: type) { return match }
        }
        return nil
    }
}
#endif
