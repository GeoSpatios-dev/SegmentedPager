//
//  PagerPageScroll.swift
//  SegmentedPager
//
//  Created by yousanflics on 7/1/26.
//
//  The vertical scroll container every page wraps its content in. Owning
//  the ScrollView here (instead of letting pages bring their own) is the
//  contract that lets the pager find the page's UIScrollView (probe),
//  manage scrollsToTop uniqueness, and — from M2 — drive sticky header
//  coordination and top insets.
//
//  Pages that skip this wrapper simply render as static, non-scrolling
//  content and don't participate in scroll-linked behavior.
//

#if canImport(UIKit)
import SwiftUI

public struct PagerPageScroll<Content: View>: View {
    private let showsIndicators: Bool
    private let content: () -> Content

    @Environment(\.pagerScrollViewRegistrar) private var registrar
    @Environment(\.pagerContentBottomPadding) private var contentBottomPadding
    @Environment(\.pagerChromeTopInset) private var chromeTopInset

    public init(
        showsIndicators: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.showsIndicators = showsIndicators
        self.content = content
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: showsIndicators) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, contentBottomPadding)
                .background(alignment: .top) {
                    ScrollViewProbe { scrollView in
                        registrar?.register(scrollView)
                    }
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
                }
        }
        // Pinned-chrome reservation: rest offset stays 0 and scroll
        // content y=0 is the top of this margin, which is exactly the
        // geometry StickyMath expects (design doc §5.3 spike outcome).
        // Indicators intentionally keep their native full-height track;
        // pinned chrome leaves the trailing indicator lane uncovered.
        .contentMargins(.top, chromeTopInset, for: .scrollContent)
    }
}
#endif
