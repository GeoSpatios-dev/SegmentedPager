//
//  PagerStickyCoordinatorTests.swift
//  SegmentedPagerTests
//
//  Created by yousanflics on 7/1/26.
//
//  Headless-UIWindow tests for the sticky coordination mechanics:
//  KVO-driven chrome frames, header reparenting across freeze/settle,
//  OffsetSyncRule integration on settle, and dynamic chrome heights.
//

#if canImport(UIKit)
import SegmentedPagerCore
import Testing
import UIKit

@MainActor
struct PagerStickyCoordinatorTests {
    // Explicit: a nested type is not main-actor-isolated by its parent on
    // Swift 6.0 toolchains (Xcode 16.x), and `anchor` reads UIKit state.
    @MainActor
    private struct Harness {
        let sticky: PagerStickyCoordinator
        let overlay: PagerChromeOverlay
        let header: UIView
        let bar: UIView
        let pageA: UIScrollView
        let pageB: UIScrollView
        let window: UIWindow

        /// The chrome's top anchor (container safe area) — expectations
        /// are relative to it so the tests hold on any test host.
        var anchor: CGFloat { overlay.safeAreaInsets.top }
    }

    private func makeHarness(headerHeight: CGFloat = 100, barHeight: CGFloat = 40) -> Harness {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        let root = UIViewController()
        window.rootViewController = root
        window.isHidden = false
        window.layoutIfNeeded()

        func makePage() -> UIScrollView {
            let scrollView = UIScrollView(frame: root.view.bounds)
            scrollView.contentSize = CGSize(width: 390, height: 3000)
            scrollView.contentInsetAdjustmentBehavior = .never
            root.view.addSubview(scrollView)
            return scrollView
        }

        let pageA = makePage()
        let pageB = makePage()

        let overlay = PagerChromeOverlay(frame: root.view.bounds)
        root.view.addSubview(overlay)

        let header = UIView()
        let bar = UIView()
        let sticky = PagerStickyCoordinator(overlay: overlay, headerView: header, barView: bar)
        sticky.setHeaderHeight(headerHeight)
        sticky.setBarHeight(barHeight)
        sticky.overlayLayoutChanged()
        sticky.settle(on: pageA)

        return Harness(
            sticky: sticky, overlay: overlay, header: header, bar: bar,
            pageA: pageA, pageB: pageB, window: window
        )
    }

    @Test func settleHostsHeaderInsideActivePage() {
        let h = makeHarness()
        #expect(h.header.superview === h.pageA)
        #expect(h.header.frame == CGRect(x: 0, y: 0, width: 390, height: 100))
        #expect(h.bar.superview === h.overlay)
    }

    @Test func barTracksVerticalScrollThroughKVO() {
        let h = makeHarness()
        h.pageA.contentOffset.y = 60
        #expect(h.bar.frame.origin.y == h.anchor + 40) // headerHeight 100 - collapse 60
        #expect(h.bar.frame.height == 40)
    }

    @Test func barPinsOnceCollapseReachesHeaderHeight() {
        let h = makeHarness()
        h.pageA.contentOffset.y = 500
        #expect(h.bar.frame.origin.y == h.anchor) // clamped: fully pinned
    }

    @Test func pullDownBounceMovesChromeDownWithTheContent() {
        // Rubber-band stretch: the bar rides down with the in-scroll
        // header and content as one surface (legacy single-scroll feel)
        // instead of staying pinned over a growing gap.
        let h = makeHarness()
        h.pageA.contentOffset.y = -80
        #expect(h.bar.frame.origin.y == h.anchor + 180) // 100 + 80 stretch

        // Releasing back to rest restores the expanded chrome.
        h.pageA.contentOffset.y = 0
        #expect(h.bar.frame.origin.y == h.anchor + 100)
    }

    @Test func freezingMidBounceClampsToExpanded() {
        // A horizontal swipe starting mid-bounce must not freeze the
        // chrome at a stretched position.
        let h = makeHarness()
        h.pageA.contentOffset.y = -80
        h.sticky.freezeForHorizontalTransition()
        #expect(h.bar.frame.origin.y == h.anchor + 100)
        #expect(h.header.frame.origin.y == h.anchor)
    }

    @Test func pinProgressIsReportedOnChange() {
        let h = makeHarness()
        var reported: [CGFloat] = []
        h.sticky.onPinProgressChange = { reported.append($0) }
        h.pageA.contentOffset.y = 50
        h.pageA.contentOffset.y = 100
        #expect(reported == [0.5, 1.0])
    }

    @Test func freezeFloatsHeaderAndStopsChromeUpdates() {
        let h = makeHarness()
        h.pageA.contentOffset.y = 30
        h.sticky.freezeForHorizontalTransition()

        #expect(h.header.superview === h.overlay)
        #expect(h.header.frame.origin.y == h.anchor - 30)

        // Vertical offsets during the horizontal transition must not
        // move the frozen chrome.
        h.pageA.contentOffset.y = 200
        #expect(h.bar.frame.origin.y == h.anchor + 70)
        #expect(h.header.frame.origin.y == h.anchor - 30)
    }

    // MARK: - OffsetSyncRule integration on settle

    @Test func settleWithHeaderVisibleSyncsDestinationToSharedCollapse() {
        let h = makeHarness()
        h.pageA.contentOffset.y = 30
        h.sticky.freezeForHorizontalTransition()
        h.pageB.contentOffset.y = 800 // deep — still overridden for continuity

        h.sticky.settle(on: h.pageB)

        #expect(h.pageB.contentOffset.y == 30)
        #expect(h.header.superview === h.pageB)
        #expect(h.bar.frame.origin.y == h.anchor + 70)
    }

    @Test func settleWithHeaderPinnedKeepsDeepDestination() {
        let h = makeHarness()
        h.pageA.contentOffset.y = 400 // pinned
        h.sticky.freezeForHorizontalTransition()
        h.pageB.contentOffset.y = 800

        h.sticky.settle(on: h.pageB)

        #expect(h.pageB.contentOffset.y == 800)
        #expect(h.bar.frame.origin.y == h.anchor) // stays pinned
    }

    @Test func settleWithHeaderPinnedClampsShallowDestinationToPinPoint() {
        let h = makeHarness()
        h.pageA.contentOffset.y = 400 // pinned
        h.sticky.freezeForHorizontalTransition()
        h.pageB.contentOffset.y = 20

        h.sticky.settle(on: h.pageB)

        #expect(h.pageB.contentOffset.y == 100) // clamped to pin point
        #expect(h.bar.frame.origin.y == h.anchor)
    }

    @Test func settleUnfreezesAndFollowsTheDestination() {
        let h = makeHarness()
        h.sticky.freezeForHorizontalTransition()
        h.sticky.settle(on: h.pageB)

        h.pageB.contentOffset.y = 25
        #expect(h.bar.frame.origin.y == h.anchor + 75)

        // The abandoned page no longer drives the chrome.
        h.pageA.contentOffset.y = 90
        #expect(h.bar.frame.origin.y == h.anchor + 75)
    }

    // MARK: - Dynamic chrome heights

    @Test func headerHeightChangePreservesPinProgress() {
        let h = makeHarness()
        var insets: [CGFloat] = []
        h.sticky.onTopInsetChange = { insets.append($0) }

        h.pageA.contentOffset.y = 50 // pinProgress 0.5

        h.sticky.setHeaderHeight(200)

        #expect(h.pageA.contentOffset.y == 100) // collapse' = 0.5 × 200
        #expect(insets == [240]) // 200 + 40
        #expect(h.bar.frame.origin.y == h.anchor + 100) // 200 - 100
    }

    @Test func headerGrowingFromZeroAppearsExpanded() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        let root = UIViewController()
        window.rootViewController = root
        window.isHidden = false

        let overlay = PagerChromeOverlay(frame: root.view.bounds)
        root.view.addSubview(overlay)
        let header = UIView()
        let sticky = PagerStickyCoordinator(overlay: overlay, headerView: header, barView: UIView())

        let scrollView = UIScrollView(frame: root.view.bounds)
        scrollView.contentSize = CGSize(width: 390, height: 3000)
        scrollView.contentInsetAdjustmentBehavior = .never
        root.view.addSubview(scrollView)
        sticky.settle(on: scrollView)

        sticky.setHeaderHeight(120)

        // First measurement must not pin the header (pinProgress of a
        // zero-height header is defined as 1, but growth from 0 treats
        // the header as expanded).
        #expect(scrollView.contentOffset.y == 0)
        #expect(sticky.currentCollapse == 0)
    }

    @Test func barHeightChangeUpdatesInsetWithoutTouchingOffsets() {
        let h = makeHarness()
        var insets: [CGFloat] = []
        h.sticky.onTopInsetChange = { insets.append($0) }
        h.pageA.contentOffset.y = 10

        h.sticky.setBarHeight(56)

        #expect(insets == [156])
        #expect(h.pageA.contentOffset.y == 10)
        #expect(h.bar.frame.height == 56)
    }
}
#endif
