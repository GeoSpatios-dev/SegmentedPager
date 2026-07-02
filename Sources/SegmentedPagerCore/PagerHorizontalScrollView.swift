//
//  PagerHorizontalScrollView.swift
//  SegmentedPager
//
//  The horizontal paging container. All gesture arbitration against the
//  vertically scrolling pages is native UIKit nested-scroll behavior;
//  this subclass only adds opt-out regions (`pagerSwipeExclusion`) where
//  a horizontal pan must not begin — e.g. an embedded chart that owns
//  horizontal drags outright.
//

#if canImport(UIKit)
import UIKit

@MainActor
public final class PagerHorizontalScrollView: UIScrollView {
    /// Views registered as swipe-exclusion regions. Weakly held; a
    /// deallocated view simply stops excluding.
    private let exclusionViews = NSHashTable<UIView>.weakObjects()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isPagingEnabled = true
        isDirectionalLockEnabled = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        scrollsToTop = false
        bounces = true
        alwaysBounceVertical = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public func registerSwipeExclusion(_ view: UIView) {
        exclusionViews.add(view)
    }

    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer {
            if touchIsInsideExclusionRegion(gestureRecognizer) {
                return false
            }
            if touchStartsInNestedHorizontalScrollable(gestureRecognizer) {
                return false
            }
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    private func touchIsInsideExclusionRegion(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let exclusions = exclusionViews.allObjects
        guard !exclusions.isEmpty else { return false }

        return exclusions.contains { exclusion in
            guard exclusion.window != nil else { return false }
            let location = gestureRecognizer.location(in: exclusion)
            return exclusion.bounds.contains(location)
        }
    }

    /// Touches beginning inside a nested horizontally-scrollable region
    /// (chart carousels, route-fix strips) never begin a page-switch pan,
    /// even when the inner scroller declines the drag (at its content
    /// edge, or bounce disabled with near-fit content). Mirrors the
    /// legacy panel's guarantee; `pagerSwipeExclusion()` remains for
    /// non-scroll-view regions.
    private func touchStartsInNestedHorizontalScrollable(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let location = gestureRecognizer.location(in: self)
        guard let hitView = hitTest(location, with: nil) else { return false }

        var current: UIView? = hitView
        while let view = current, view !== self {
            if let scrollView = view as? UIScrollView,
               scrollView !== self,
               scrollView.isScrollEnabled,
               scrollView.alwaysBounceHorizontal
                   || scrollView.contentSize.width > scrollView.bounds.width + 1 {
                return true
            }
            current = view.superview
        }
        return false
    }
}
#endif
