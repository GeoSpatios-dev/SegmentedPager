//
//  PagerConfig.swift
//  SegmentedPager
//
//  Created by yousanflics on 7/1/26.
//
//  Public configuration surface shared by Core and the SwiftUI adapter.
//

import CoreGraphics

/// How the tab bar relates to the vertically scrolling content.
public enum PagerBarMode: Equatable, Sendable {
    /// Header scrolls away with the content, bar pins at the top once it
    /// reaches it (full sticky coordination — wired up in M2).
    case pinned
    /// Bar is always fixed above the pages; the degenerate
    /// `headerHeight == 0` case of the same coordination.
    case fixed
}

/// When page view controllers are created.
public enum PagerPreloadPolicy: Equatable, Sendable {
    /// Create a page when it is selected, or once a horizontal drag has
    /// revealed at least `visibleRatio` of it (JXSegmentedView's
    /// `initListPercent`).
    case lazy(visibleRatio: CGFloat)
    /// Additionally pre-create the immediate neighbors of the selected
    /// page so the first swipe never shows an empty page.
    case neighbors
    /// Create every page up front. Only for cheap content.
    case eager

    public static let `default` = PagerPreloadPolicy.lazy(visibleRatio: 0.5)

    /// Visible ratio of an incoming page required before it is created.
    /// Pre-created policies only need the page to become visible at all.
    var initVisibleRatio: CGFloat {
        switch self {
        case .lazy(let visibleRatio):
            return min(max(visibleRatio, 0.01), 1)
        case .neighbors, .eager:
            return 0.01
        }
    }
}
