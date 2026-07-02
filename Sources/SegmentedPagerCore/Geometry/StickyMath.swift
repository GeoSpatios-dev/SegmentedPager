//
//  StickyMath.swift
//  SegmentedPager
//
//  Pure geometry for smooth-mode sticky header coordination (design doc
//  §5.3). The header collapse is a function of the active page's
//  normalized offset; the chrome (header + bar) frames are functions of
//  the collapse. Wired up in M2; the math lands in M0 with full tests.
//
//  Model:
//    topInset      = headerHeight + barHeight   (each page's top content inset)
//    normalized(p) = contentOffset.y + adjustedTopInset   (0 == fully expanded)
//    collapse      = clamp(normalized(activePage), 0, headerHeight)
//    header y      = -collapse
//    bar y         = headerHeight - collapse    (bar pins when collapse == headerHeight)
//

import CoreGraphics

public struct StickyMath: Equatable, Sendable {
    public var headerHeight: CGFloat
    public var barHeight: CGFloat

    public init(headerHeight: CGFloat, barHeight: CGFloat) {
        self.headerHeight = headerHeight
        self.barHeight = barHeight
    }

    /// Top content inset every page must reserve for the chrome.
    public var totalTopInset: CGFloat {
        headerHeight + barHeight
    }

    /// Offset in "expanded == 0" space for a page scroll view.
    public func normalizedOffset(contentOffsetY: CGFloat, adjustedTopInset: CGFloat) -> CGFloat {
        contentOffsetY + adjustedTopInset
    }

    /// Header collapse for a normalized offset, clamped to the header's
    /// travel range. Negative offsets (pull-down bounce) keep the header
    /// fully expanded rather than over-expanding it.
    public func collapse(forNormalizedOffset offset: CGFloat) -> CGFloat {
        min(max(offset, 0), headerHeight)
    }

    public func headerOriginY(collapse: CGFloat) -> CGFloat {
        -collapse
    }

    public func barOriginY(collapse: CGFloat) -> CGFloat {
        headerHeight - collapse
    }

    /// `0` fully expanded … `1` pinned. A zero-height header (fixed bar
    /// mode) is always pinned.
    public func pinProgress(collapse: CGFloat) -> CGFloat {
        guard headerHeight > 0 else { return 1 }
        return min(max(collapse / headerHeight, 0), 1)
    }
}
