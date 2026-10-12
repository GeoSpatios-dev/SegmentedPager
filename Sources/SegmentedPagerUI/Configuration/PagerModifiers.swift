//
//  PagerModifiers.swift
//  SegmentedPager
//
//  Created by yousanflics on 7/1/26.
//
//  Public configuration modifiers (environment-carried, apply them to a
//  `SegmentedPager` or any ancestor) and the page lifecycle modifiers
//  (apply them inside page content).
//

import CoreGraphics
import SegmentedPagerCore
import SwiftUI

extension View {
    /// `.pinned`: header scrolls away and the bar pins.
    /// `.fixed`: bar always fixed above the pages.
    public func pagerBarMode(_ mode: PagerBarMode) -> some View {
        environment(\.pagerBarMode, mode)
    }

    /// When page view controllers are created. Read once when the pager
    /// is set up; later changes are ignored.
    public func pagerPreloadPolicy(_ policy: PagerPreloadPolicy) -> some View {
        environment(\.pagerPreloadPolicy, policy)
    }

    /// Disables horizontal swipe paging; bar taps still switch pages.
    public func pagerSwipeEnabled(_ isEnabled: Bool) -> some View {
        environment(\.pagerSwipeEnabled, isEnabled)
    }

    /// Opaque background behind the bar row, e.g. to keep half-sheet
    /// content from showing through a translucent chrome.
    public func pagerBarBackground(_ style: some ShapeStyle) -> some View {
        environment(\.pagerBarBackground, AnyShapeStyle(style))
    }

    /// Extra scrollable space below each page's content for host chrome
    /// that overlaps the bottom edge. Consumed by `PagerPageScroll`.
    public func pagerContentBottomPadding(_ padding: CGFloat) -> some View {
        environment(\.pagerContentBottomPadding, padding)
    }

    /// Opts the pager into cheap updates. The page, header and bar
    /// closures are not comparable, so by default every update of the
    /// pager re-evaluates every hosted root (pages, header, bar) in case a
    /// closure captured a changed input. With a key, the roots re-evaluate
    /// only when the key changes, when `tabs`/`selection` change, or when
    /// an observable environment trait (colour scheme, dynamic type, size
    /// class, locale, accessibility, …) changes. Pass every value the
    /// closures capture that is not observed inside the pages themselves;
    /// state the pages read through an `@Observable` object needs no key.
    public func pagerContentKey(_ key: AnyHashable?) -> some View {
        environment(\.pagerContentKey, key)
    }

    /// Continuous header pin progress (0 fully expanded … 1 pinned),
    /// for scroll-linked chrome effects. Pinned bar mode only.
    public func onPagerPinProgress(
        _ action: @escaping @MainActor @Sendable (CGFloat) -> Void
    ) -> some View {
        environment(\.pagerPinProgressAction, action)
    }

    /// Runs when the page containing this view becomes the pager's
    /// active page (including the first time it is created).
    public func onPagerPageAppear(_ action: @escaping () -> Void) -> some View {
        modifier(PagerPageAppearModifier(action: action))
    }

    /// Runs when the page containing this view stops being the pager's
    /// active page.
    public func onPagerPageDisappear(_ action: @escaping () -> Void) -> some View {
        modifier(PagerPageDisappearModifier(action: action))
    }
}

private struct PagerPageAppearModifier: ViewModifier {
    @Environment(\.pagerPageIsActive) private var isActive
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                if isActive { action() }
            }
            .onChange(of: isActive) { oldValue, newValue in
                if !oldValue, newValue { action() }
            }
    }
}

private struct PagerPageDisappearModifier: ViewModifier {
    @Environment(\.pagerPageIsActive) private var isActive
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: isActive) { oldValue, newValue in
                if oldValue, !newValue { action() }
            }
    }
}
