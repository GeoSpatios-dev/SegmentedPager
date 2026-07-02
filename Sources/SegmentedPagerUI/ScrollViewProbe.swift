//
//  ScrollViewProbe.swift
//  SegmentedPager
//
//  Bridging probes between SwiftUI page content and the UIKit core.
//
//  `ScrollViewProbe` sits as the first child of a `PagerPageScroll`'s
//  content and reports the enclosing (SwiftUI-bridged) UIScrollView to
//  the pager — the formalized version of the walk-up trick, with a
//  clear contract: resolution failure degrades gracefully (no sticky
//  coordination for that page), never crashes.
//
//  `pagerSwipeExclusion()` registers a region in which the horizontal
//  paging pan must not begin (nested charts that own horizontal drags).
//

#if canImport(UIKit)
import SegmentedPagerCore
import SwiftUI
import UIKit

/// Environment-carried registration callback a page's scroll view
/// reports itself through. Injected per page by the pager.
struct PagerScrollViewRegistrar: Sendable {
    let register: @MainActor @Sendable (UIScrollView) -> Void
}

private struct PagerScrollViewRegistrarKey: EnvironmentKey {
    static let defaultValue: PagerScrollViewRegistrar? = nil
}

extension EnvironmentValues {
    var pagerScrollViewRegistrar: PagerScrollViewRegistrar? {
        get { self[PagerScrollViewRegistrarKey.self] }
        set { self[PagerScrollViewRegistrarKey.self] = newValue }
    }
}

// MARK: - Scroll view resolution

struct ScrollViewProbe: UIViewRepresentable {
    let onResolve: @MainActor @Sendable (UIScrollView) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.onResolve = onResolve
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.onResolve = onResolve
        uiView.resolveIfNeeded()
    }

    final class ProbeView: UIView {
        var onResolve: (@MainActor @Sendable (UIScrollView) -> Void)?
        private weak var resolved: UIScrollView?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            resolveIfNeeded()
        }

        func resolveIfNeeded() {
            guard window != nil else { return }
            guard let scrollView = enclosingSuperview(of: UIScrollView.self) else {
                // SwiftUI bridging hierarchy changed (new OS?) — the
                // fragile-surface CI smoke exists to catch exactly this.
                assertionFailure("ScrollViewProbe could not resolve its enclosing UIScrollView")
                return
            }
            guard scrollView !== resolved else { return }
            resolved = scrollView
            onResolve?(scrollView)
        }
    }
}

// MARK: - Swipe exclusion

extension View {
    /// Marks this view's region as owning horizontal drags: the pager's
    /// page-switching pan will not begin from touches inside it.
    /// Same-axis nested scroll views usually don't need this (the inner
    /// one wins natively); use it when a region must never switch pages.
    public func pagerSwipeExclusion() -> some View {
        background {
            SwipeExclusionProbe()
                .accessibilityHidden(true)
        }
    }
}

private struct SwipeExclusionProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> ExclusionView {
        let view = ExclusionView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: ExclusionView, context: Context) {}

    final class ExclusionView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            enclosingSuperview(of: PagerHorizontalScrollView.self)?
                .registerSwipeExclusion(self)
        }
    }
}

// MARK: - Shared helper

extension UIView {
    func enclosingSuperview<ViewType: UIView>(of type: ViewType.Type) -> ViewType? {
        var current = superview
        while let view = current {
            if let typed = view as? ViewType {
                return typed
            }
            current = view.superview
        }
        return nil
    }
}
#endif
