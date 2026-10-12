//
//  FragileSurfaceSmokeTests.swift
//  SegmentedPagerTests
//
//  Created by yousanflics on 7/1/26.
//
//  CI smoke for the two fragile surfaces that depend on SwiftUI's
//  private bridging behavior. Run on every
//  iOS/Xcode major upgrade — failures here mean the OS changed the
//  contract, and the coordinator must fall back to its degraded paths.
//
//  1. Probe resolution: PagerPageScroll can find its bridged UIScrollView.
//  2. Offset writes stick: setting contentOffset is not silently
//     reverted by SwiftUI's internal scroll state on the next runloop.
//  3. Foreign subviews survive: a view added directly to the bridged
//     scroll view (the header hosting mechanism) stays in the hierarchy
//     across layout passes.
//

#if canImport(UIKit)
@testable import SegmentedPagerUI
import SwiftUI
import Testing
import UIKit

@MainActor
private final class ScrollViewCapture {
    var scrollView: UIScrollView?
}

@MainActor
struct FragileSurfaceSmokeTests {
    private func makeHostedPageScroll() -> (capture: ScrollViewCapture, window: UIWindow) {
        let capture = ScrollViewCapture()
        let page = PagerPageScroll {
            LazyVStack(spacing: 0) {
                ForEach(0 ..< 200, id: \.self) { index in
                    Text("Row \(index)")
                        .frame(height: 44)
                }
            }
        }
        .environment(
            \.pagerScrollViewRegistrar,
            PagerScrollViewRegistrar { [weak capture] scrollView in
                capture?.scrollView = scrollView
            }
        )

        let hosting = UIHostingController(rootView: page)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        window.rootViewController = hosting
        window.isHidden = false
        window.layoutIfNeeded()

        let deadline = Date().addingTimeInterval(2)
        while capture.scrollView == nil, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            window.layoutIfNeeded()
        }

        return (capture, window)
    }

    @Test func probeResolvesTheBridgedScrollView() {
        let (capture, _) = makeHostedPageScroll()
        #expect(capture.scrollView != nil)
        #expect(capture.scrollView?.contentSize.height ?? 0 > 700)
    }

    @Test func contentOffsetWriteIsNotRevertedBySwiftUI() {
        let (capture, window) = makeHostedPageScroll()
        guard let scrollView = capture.scrollView else {
            Issue.record("probe did not resolve — covered by probeResolvesTheBridgedScrollView")
            return
        }

        scrollView.contentOffset.y = 500

        // Give SwiftUI two runloop turns + a layout pass to fight back.
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        #expect(abs(scrollView.contentOffset.y - 500) < 1,
                "SwiftUI reverted a programmatic contentOffset write — switch OffsetSyncRule to the ScrollViewReader fallback (design doc §5.3)")
    }

    @Test func foreignSubviewSurvivesLayoutPasses() {
        let (capture, window) = makeHostedPageScroll()
        guard let scrollView = capture.scrollView else {
            Issue.record("probe did not resolve — covered by probeResolvesTheBridgedScrollView")
            return
        }

        let foreign = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
        scrollView.addSubview(foreign)

        scrollView.contentOffset.y = 300
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        window.setNeedsLayout()
        window.layoutIfNeeded()

        #expect(foreign.superview === scrollView,
                "SwiftUI removed a foreign subview from its bridged scroll view — the header hosting mechanism (design doc §5.3) is broken on this OS")
    }
}
#endif
